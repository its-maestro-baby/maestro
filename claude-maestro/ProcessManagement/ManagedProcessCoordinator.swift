import Foundation
import Combine

/// Status of a managed process
public enum ManagedProcessStatus: String, Sendable {
    case starting
    case running
    case stopping
    case stopped
    case error
}

/// A managed process with full lifecycle tracking
public struct ManagedProcess: Sendable, Identifiable {
    public let id: Int // sessionId
    public let sessionId: Int
    public let pid: pid_t
    public let pgid: pid_t
    public let command: String
    public let workingDirectory: String
    public let port: UInt16?
    public let startedAt: Date
    public var status: ManagedProcessStatus
    public var serverURL: String?
    public var exitCode: Int32?
    public var errorMessage: String?

    public init(
        sessionId: Int,
        pid: pid_t,
        pgid: pid_t,
        command: String,
        workingDirectory: String,
        port: UInt16? = nil,
        status: ManagedProcessStatus = .starting
    ) {
        self.id = sessionId
        self.sessionId = sessionId
        self.pid = pid
        self.pgid = pgid
        self.command = command
        self.workingDirectory = workingDirectory
        self.port = port
        self.startedAt = Date()
        self.status = status
    }

    /// Uptime in seconds
    public var uptime: TimeInterval {
        Date().timeIntervalSince(startedAt)
    }
}

/// High-level API for managing dev server processes
/// Replaces ProcessManager.ts functionality with native Darwin APIs
@MainActor
public class ManagedProcessCoordinator: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var processes: [Int: ManagedProcess] = [:]
    @Published public private(set) var isReady = false

    // MARK: - Dependencies

    private let launcher: ProcessLauncher
    private let monitor: ProcessMonitor
    private let processTree: ProcessTree
    private let portManager: NativePortManager
    private let logManager: NativeLogManager
    private let registry: ProcessRegistry

    // MARK: - Internal State

    private var streamReaders: [Int: ProcessStreamReader] = [:]
    private var launchedProcesses: [Int: LaunchedProcess] = [:]

    /// URL detection patterns
    private static let urlPatterns: [NSRegularExpression] = {
        let patterns = [
            #"https?://localhost:\d+"#,
            #"https?://127\.0\.0\.1:\d+"#,
            #"https?://\[::1\]:\d+"#,
            #"Local:\s+(https?://[^\s]+)"#,
            #"ready on (https?://[^\s]+)"#,
            #"listening on (https?://[^\s]+)"#,
            #"Server running at (https?://[^\s]+)"#,
            #"Started server on (https?://[^\s]+)"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    // MARK: - Initialization

    public init() {
        self.launcher = ProcessLauncher()
        self.monitor = ProcessMonitor()
        self.processTree = ProcessTree()
        self.portManager = NativePortManager()
        self.logManager = NativeLogManager()
        self.registry = ProcessRegistry()

        Task {
            await initialize()
        }
    }

    private func initialize() async {
        do {
            try await monitor.start()
            isReady = true
        } catch {
            print("Failed to initialize process monitor: \(error)")
        }
    }

    // MARK: - Dev Server Management

    /// Start a development server for a session
    /// - Parameters:
    ///   - sessionId: Session ID
    ///   - command: Command to run (e.g., "npm run dev")
    ///   - workingDirectory: Directory to run in
    ///   - preferredPort: Optional preferred port
    /// - Returns: The started process info
    public func startDevServer(
        sessionId: Int,
        command: String,
        workingDirectory: String,
        preferredPort: UInt16? = nil
    ) async throws -> ManagedProcess {
        // Stop existing server if any
        if processes[sessionId] != nil {
            try await stopDevServer(sessionId: sessionId)
        }

        // Allocate port
        let port = await portManager.allocatePort(for: sessionId, preferredPort: preferredPort)

        // Build environment with PORT variable
        var env = ProcessInfo.processInfo.environment
        if let port = port {
            env["PORT"] = String(port)
        }

        // Launch the process
        let launchedProcess = try await launcher.spawnShell(
            command: command,
            workingDirectory: URL(fileURLWithPath: workingDirectory),
            environment: env,
            useProcessGroup: true
        )

        // Create managed process record
        var managedProcess = ManagedProcess(
            sessionId: sessionId,
            pid: launchedProcess.pid,
            pgid: launchedProcess.pgid,
            command: command,
            workingDirectory: workingDirectory,
            port: port,
            status: .starting
        )

        // Register with registry
        await registry.register(
            pid: launchedProcess.pid,
            pgid: launchedProcess.pgid,
            sessionId: sessionId,
            source: .devServer,
            command: command,
            workingDirectory: workingDirectory
        )

        // Store the launched process for later
        launchedProcesses[sessionId] = launchedProcess

        // Set up output streaming
        let streamReader = ProcessStreamReader(sessionId: sessionId, logManager: logManager)
        streamReader.onOutput = { [weak self] stream, content in
            Task { @MainActor in
                self?.handleOutput(sessionId: sessionId, stream: stream, content: content)
            }
        }
        streamReader.start(stdout: launchedProcess.stdoutPipe, stderr: launchedProcess.stderrPipe)
        streamReaders[sessionId] = streamReader

        // Watch for process exit
        try await monitor.watch(pid: launchedProcess.pid) { [weak self] pid, exitCode in
            Task { @MainActor in
                self?.handleProcessExit(sessionId: sessionId, pid: pid, exitCode: exitCode)
            }
        }

        // Update state
        managedProcess.status = .running
        processes[sessionId] = managedProcess

        // Log start
        await logManager.appendSystem(sessionId: sessionId, content: "Started: \(command)")

        return managedProcess
    }

    /// Stop a development server
    /// - Parameter sessionId: Session ID
    public func stopDevServer(sessionId: Int) async throws {
        guard var process = processes[sessionId] else { return }

        process.status = .stopping
        processes[sessionId] = process

        // Stop stream reader
        streamReaders[sessionId]?.stop()
        streamReaders.removeValue(forKey: sessionId)

        // Kill the process group
        if let launched = launchedProcesses[sessionId] {
            await launcher.terminateGroup(pgid: launched.pgid, gracePeriod: 5.0)
            launchedProcesses.removeValue(forKey: sessionId)
        }

        // Unregister
        await registry.unregister(pid: process.pid)

        // Release port
        if let port = process.port {
            await portManager.releasePort(port)
        }

        // Update state
        process.status = .stopped
        processes.removeValue(forKey: sessionId)

        // Log stop
        await logManager.appendSystem(sessionId: sessionId, content: "Stopped")
    }

    /// Restart a development server
    /// - Parameter sessionId: Session ID
    public func restartDevServer(sessionId: Int) async throws {
        guard let process = processes[sessionId] else {
            throw CoordinatorError.processNotFound(sessionId: sessionId)
        }

        // Clear logs
        await logManager.clearLogs(sessionId: sessionId)

        // Stop and restart
        try await stopDevServer(sessionId: sessionId)
        _ = try await startDevServer(
            sessionId: sessionId,
            command: process.command,
            workingDirectory: process.workingDirectory,
            preferredPort: process.port
        )
    }

    // MARK: - Status Queries

    /// Get status for a session
    public func getStatus(sessionId: Int) -> ManagedProcess? {
        processes[sessionId]
    }

    /// Get all statuses
    public func getAllStatuses() -> [ManagedProcess] {
        Array(processes.values)
    }

    /// Check if a session has a running server
    public func isRunning(sessionId: Int) -> Bool {
        guard let process = processes[sessionId] else { return false }
        return process.status == .running
    }

    // MARK: - Process Tree

    /// Get the process tree for a session
    public func getProcessTree(sessionId: Int) async -> [ProcessNode] {
        guard let process = processes[sessionId] else { return [] }
        return await processTree.buildTree(rootPid: process.pid)
    }

    /// Get all processes for a session (including children)
    public func getAllSessionProcesses(sessionId: Int) async -> [ProcessInfo] {
        guard let process = processes[sessionId] else { return [] }

        var all: [ProcessInfo] = []

        if let rootInfo = await processTree.getProcessInfo(pid: process.pid) {
            all.append(rootInfo)
        }

        let descendants = await processTree.getDescendants(of: process.pid)
        all.append(contentsOf: descendants)

        return all
    }

    // MARK: - Logs

    /// Get logs for a session
    public func getLogs(sessionId: Int, count: Int = 50) async -> [LogEntry] {
        await logManager.getLogs(sessionId: sessionId, count: count)
    }

    /// Get logs as string
    public func getLogsAsString(sessionId: Int, count: Int = 50) async -> String {
        await logManager.getLogsAsString(sessionId: sessionId, count: count)
    }

    // MARK: - Port Management

    /// Get available ports
    public func getAvailablePorts(count: Int = 5) async -> [UInt16] {
        await portManager.findAvailablePorts(count: count)
    }

    /// Get port for session
    public func getPort(sessionId: Int) async -> UInt16? {
        await portManager.getPort(for: sessionId)
    }

    // MARK: - Cleanup

    /// Cleanup a session (stop server, release port, clear logs)
    public func cleanupSession(_ sessionId: Int) async {
        try? await stopDevServer(sessionId: sessionId)
        await logManager.clearLogs(sessionId: sessionId)
        await portManager.releasePortsForSession(sessionId)
    }

    /// Cleanup all sessions
    public func cleanupAll() async {
        for sessionId in processes.keys {
            await cleanupSession(sessionId)
        }
    }

    // MARK: - Private Helpers

    private func handleOutput(sessionId: Int, stream: LogStream, content: String) {
        // Check for URL in output
        if let url = detectServerURL(in: content) {
            if var process = processes[sessionId] {
                process.serverURL = url
                process.status = .running
                processes[sessionId] = process

                // Auto-open browser
                if let nsUrl = URL(string: url) {
                    NSWorkspace.shared.open(nsUrl)
                }
            }
        }
    }

    private func handleProcessExit(sessionId: Int, pid: pid_t, exitCode: Int32) {
        guard var process = processes[sessionId], process.pid == pid else { return }

        // Clean up stream reader
        streamReaders[sessionId]?.stop()
        streamReaders.removeValue(forKey: sessionId)

        // Update process state
        process.exitCode = exitCode
        process.status = exitCode == 0 ? .stopped : .error

        if exitCode != 0 {
            process.errorMessage = "Process exited with code \(exitCode)"
        }

        // Remove from active processes
        processes.removeValue(forKey: sessionId)
        launchedProcesses.removeValue(forKey: sessionId)

        // Unregister
        Task {
            await registry.unregister(pid: pid)
            if let port = process.port {
                await portManager.releasePort(port)
            }
            await logManager.appendSystem(sessionId: sessionId, content: "Exited with code \(exitCode)")
        }
    }

    private func detectServerURL(in text: String) -> String? {
        for pattern in Self.urlPatterns {
            if let match = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                // Try to get captured group first (for patterns with groups)
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: text) {
                    return String(text[range])
                }
                // Fall back to full match
                if let range = Range(match.range, in: text) {
                    return String(text[range])
                }
            }
        }
        return nil
    }

    // MARK: - Errors

    public enum CoordinatorError: Error, LocalizedError {
        case processNotFound(sessionId: Int)
        case alreadyRunning(sessionId: Int)
        case launchFailed(reason: String)

        public var errorDescription: String? {
            switch self {
            case .processNotFound(let sessionId):
                return "No process found for session \(sessionId)"
            case .alreadyRunning(let sessionId):
                return "Session \(sessionId) already has a running process"
            case .launchFailed(let reason):
                return "Failed to launch process: \(reason)"
            }
        }
    }
}

// MARK: - System Process Scanning

public extension ManagedProcessCoordinator {
    /// Scan for system processes listening on ports
    func scanSystemProcesses() async -> [ListeningPort] {
        await portManager.scanListeningPorts(processTree: processTree)
    }

    /// Get managed process PIDs
    func getManagedPIDs() async -> [pid_t] {
        await registry.allPids
    }

    /// Check if a process is managed by us
    func isManaged(pid: pid_t) async -> Bool {
        await registry.isRegistered(pid: pid)
    }
}
