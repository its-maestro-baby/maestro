import Foundation
import Combine

/// Watches the MCP server status file for changes and publishes server statuses.
/// This enables the Swift app to react to servers started via MCP tools.
class MCPStatusWatcher: ObservableObject {
    @Published var serverStatuses: [ServerStatus] = []

    private var fileDescriptor: Int32 = -1
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var retryTimer: Timer?

    struct ServerStatus: Codable {
        let sessionId: Int
        let status: String
        let port: Int?
        let url: String?
    }

    private struct StatusFile: Codable {
        let servers: [ServerStatus]
        let updatedAt: String
    }

    private var statusFilePath: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Claude Maestro/server-status.json")
    }

    init() {
        readStatusFile()
        startWatching()
    }

    deinit {
        stopWatching()
        retryTimer?.invalidate()
    }

    func startWatching() {
        let path = statusFilePath.path

        // If file doesn't exist yet, retry periodically
        guard FileManager.default.fileExists(atPath: path) else {
            scheduleRetry()
            return
        }

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            scheduleRetry()
            return
        }

        dispatchSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )

        dispatchSource?.setEventHandler { [weak self] in
            self?.readStatusFile()
        }

        dispatchSource?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        dispatchSource?.resume()

        // Cancel retry timer since we're now watching
        retryTimer?.invalidate()
        retryTimer = nil
    }

    func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    func readStatusFile() {
        guard FileManager.default.fileExists(atPath: statusFilePath.path),
              let data = try? Data(contentsOf: statusFilePath),
              let statusFile = try? JSONDecoder().decode(StatusFile.self, from: data) else {
            return
        }
        serverStatuses = statusFile.servers
    }

    private func scheduleRetry() {
        retryTimer?.invalidate()
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.startWatching()
        }
    }
}
