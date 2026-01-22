import Foundation

/// Log entry for process output
public struct LogEntry: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let stream: LogStream
    public let content: String

    public init(timestamp: Date = Date(), stream: LogStream, content: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.stream = stream
        self.content = content
    }

    /// Formatted log line with timestamp
    public var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return "[\(formatter.string(from: timestamp))] [\(stream.rawValue)] \(content)"
    }
}

/// Log stream type
public enum LogStream: String, Sendable, CaseIterable {
    case stdout = "OUT"
    case stderr = "ERR"
    case system = "SYS"
}

/// Native log manager for process output capture
public actor NativeLogManager {

    /// Maximum number of log entries to keep per session
    public static let maxEntriesPerSession = 1000

    /// Log directory path
    private let logDirectory: URL

    /// In-memory log buffers per session
    private var sessionLogs: [Int: [LogEntry]] = [:]

    /// File handles for disk logging
    private var fileHandles: [Int: FileHandle] = [:]

    public init() {
        // Use Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.logDirectory = appSupport.appendingPathComponent("Claude Maestro/logs")

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Log Writing

    /// Append a log entry for a session
    /// - Parameters:
    ///   - sessionId: Session ID
    ///   - stream: stdout, stderr, or system
    ///   - content: Log content
    public func append(sessionId: Int, stream: LogStream, content: String) {
        let entry = LogEntry(stream: stream, content: content)

        // Add to in-memory buffer
        if sessionLogs[sessionId] == nil {
            sessionLogs[sessionId] = []
        }

        sessionLogs[sessionId]?.append(entry)

        // Trim if over limit
        if let count = sessionLogs[sessionId]?.count, count > Self.maxEntriesPerSession {
            sessionLogs[sessionId]?.removeFirst(count - Self.maxEntriesPerSession)
        }

        // Write to disk
        writeToFile(sessionId: sessionId, entry: entry)
    }

    /// Append stdout content
    public func appendStdout(sessionId: Int, content: String) {
        append(sessionId: sessionId, stream: .stdout, content: content)
    }

    /// Append stderr content
    public func appendStderr(sessionId: Int, content: String) {
        append(sessionId: sessionId, stream: .stderr, content: content)
    }

    /// Append system message
    public func appendSystem(sessionId: Int, content: String) {
        append(sessionId: sessionId, stream: .system, content: content)
    }

    // MARK: - Log Reading

    /// Get recent log entries for a session
    /// - Parameters:
    ///   - sessionId: Session ID
    ///   - count: Maximum number of entries (default 50)
    ///   - stream: Optional filter by stream type
    /// - Returns: Array of log entries (newest last)
    public func getLogs(sessionId: Int, count: Int = 50, stream: LogStream? = nil) -> [LogEntry] {
        guard let logs = sessionLogs[sessionId] else { return [] }

        var filtered = logs
        if let stream = stream {
            filtered = logs.filter { $0.stream == stream }
        }

        if filtered.count <= count {
            return filtered
        }

        return Array(filtered.suffix(count))
    }

    /// Get all log entries for a session
    public func getAllLogs(sessionId: Int) -> [LogEntry] {
        sessionLogs[sessionId] ?? []
    }

    /// Get logs as a formatted string
    /// - Parameters:
    ///   - sessionId: Session ID
    ///   - count: Maximum number of entries
    /// - Returns: Formatted log string
    public func getLogsAsString(sessionId: Int, count: Int = 50) -> String {
        getLogs(sessionId: sessionId, count: count)
            .map { $0.formatted }
            .joined(separator: "\n")
    }

    /// Search logs for a pattern
    /// - Parameters:
    ///   - sessionId: Session ID
    ///   - pattern: Search string (case-insensitive)
    /// - Returns: Matching log entries
    public func searchLogs(sessionId: Int, pattern: String) -> [LogEntry] {
        let lowercased = pattern.lowercased()
        return (sessionLogs[sessionId] ?? []).filter {
            $0.content.lowercased().contains(lowercased)
        }
    }

    // MARK: - Log Management

    /// Clear logs for a session
    /// - Parameter sessionId: Session ID
    public func clearLogs(sessionId: Int) {
        sessionLogs[sessionId] = []

        // Close file handle
        if let handle = fileHandles.removeValue(forKey: sessionId) {
            try? handle.close()
        }

        // Delete log file
        let logFile = logFileURL(for: sessionId)
        try? FileManager.default.removeItem(at: logFile)
    }

    /// Clear all logs
    public func clearAllLogs() {
        for sessionId in sessionLogs.keys {
            clearLogs(sessionId: sessionId)
        }
    }

    /// Get log file path for a session
    public func logFileURL(for sessionId: Int) -> URL {
        logDirectory.appendingPathComponent("session-\(sessionId).log")
    }

    /// Read logs from disk for a session
    /// - Parameter sessionId: Session ID
    /// - Returns: Log file contents or nil
    public func readLogFile(sessionId: Int) -> String? {
        let url = logFileURL(for: sessionId)
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Get all session IDs with logs
    public var activeSessions: [Int] {
        Array(sessionLogs.keys.sorted())
    }

    // MARK: - Private Helpers

    private func writeToFile(sessionId: Int, entry: LogEntry) {
        let handle: FileHandle

        if let existing = fileHandles[sessionId] {
            handle = existing
        } else {
            // Create or open log file
            let url = logFileURL(for: sessionId)

            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

            guard let newHandle = try? FileHandle(forWritingTo: url) else { return }
            newHandle.seekToEndOfFile()
            fileHandles[sessionId] = newHandle
            handle = newHandle
        }

        // Write formatted line
        let line = entry.formatted + "\n"
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
    }
}

// MARK: - Stream Reader Helper

/// Helper class for reading process output streams asynchronously
public class ProcessStreamReader {
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?

    private let sessionId: Int
    private let logManager: NativeLogManager

    /// Callback for new output (stream, content)
    public var onOutput: ((LogStream, String) -> Void)?

    public init(sessionId: Int, logManager: NativeLogManager) {
        self.sessionId = sessionId
        self.logManager = logManager
    }

    /// Start reading from stdout and stderr file handles
    /// - Parameters:
    ///   - stdout: stdout FileHandle
    ///   - stderr: stderr FileHandle
    public func start(stdout: FileHandle, stderr: FileHandle) {
        stdoutTask = Task { [weak self] in
            await self?.readStream(handle: stdout, stream: .stdout)
        }

        stderrTask = Task { [weak self] in
            await self?.readStream(handle: stderr, stream: .stderr)
        }
    }

    /// Stop reading
    public func stop() {
        stdoutTask?.cancel()
        stderrTask?.cancel()
    }

    private func readStream(handle: FileHandle, stream: LogStream) async {
        do {
            for try await data in handle.bytes.lines {
                guard !Task.isCancelled else { break }

                await logManager.append(sessionId: sessionId, stream: stream, content: data)
                onOutput?(stream, data)
            }
        } catch {
            // Stream closed or error - stop reading
        }
    }
}
