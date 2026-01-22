import Foundation
import Darwin

/// Callback type for process exit events
public typealias ProcessExitCallback = @Sendable (pid_t, Int32) -> Void

/// Real-time process exit monitoring using kqueue/kevent
/// No polling - callbacks fire immediately when processes exit
public actor ProcessMonitor {

    /// Errors that can occur during monitoring
    public enum MonitorError: Error, LocalizedError {
        case kqueueCreationFailed
        case watchFailed(pid: pid_t, errno: Int32)
        case invalidPid

        public var errorDescription: String? {
            switch self {
            case .kqueueCreationFailed:
                return "Failed to create kqueue"
            case .watchFailed(let pid, let errno):
                return "Failed to watch pid \(pid): \(String(cString: strerror(errno)))"
            case .invalidPid:
                return "Invalid process ID"
            }
        }
    }

    /// Info about a watched process
    private struct WatchedProcess {
        let pid: pid_t
        let callback: ProcessExitCallback
        let addedAt: Date
    }

    private var kq: Int32 = -1
    private var watchedProcesses: [pid_t: WatchedProcess] = [:]
    private var monitorTask: Task<Void, Never>?
    private var isRunning = false

    public init() {}

    deinit {
        if kq >= 0 {
            close(kq)
        }
    }

    /// Start the monitor
    public func start() throws {
        guard !isRunning else { return }

        // Create kqueue
        kq = kqueue()
        guard kq >= 0 else {
            throw MonitorError.kqueueCreationFailed
        }

        isRunning = true

        // Start the monitor loop
        monitorTask = Task { [weak self] in
            await self?.monitorLoop()
        }
    }

    /// Stop the monitor and clean up
    public func stop() {
        isRunning = false
        monitorTask?.cancel()
        monitorTask = nil

        if kq >= 0 {
            close(kq)
            kq = -1
        }

        watchedProcesses.removeAll()
    }

    /// Watch a process for exit
    /// - Parameters:
    ///   - pid: Process ID to watch
    ///   - callback: Called when process exits (pid, exit status)
    public func watch(pid: pid_t, callback: @escaping ProcessExitCallback) throws {
        guard pid > 0 else {
            throw MonitorError.invalidPid
        }

        guard isRunning else {
            try start()
        }

        // Register the event with kqueue
        var event = Darwin.kevent(
            ident: UInt(pid),
            filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_ADD | EV_ONESHOT),
            fflags: UInt32(NOTE_EXIT),
            data: 0,
            udata: nil
        )

        let result = kevent(kq, &event, 1, nil, 0, nil)
        if result < 0 {
            // ESRCH means process already exited - call callback immediately
            if errno == ESRCH {
                Task {
                    callback(pid, -1) // -1 indicates we missed the exit
                }
                return
            }
            throw MonitorError.watchFailed(pid: pid, errno: errno)
        }

        // Store the watched process info
        watchedProcesses[pid] = WatchedProcess(
            pid: pid,
            callback: callback,
            addedAt: Date()
        )
    }

    /// Stop watching a specific process
    /// - Parameter pid: Process ID to unwatch
    public func unwatch(pid: pid_t) {
        guard watchedProcesses.removeValue(forKey: pid) != nil else { return }

        // Remove from kqueue
        var event = Darwin.kevent(
            ident: UInt(pid),
            filter: Int16(EVFILT_PROC),
            flags: UInt16(EV_DELETE),
            fflags: 0,
            data: 0,
            udata: nil
        )

        kevent(kq, &event, 1, nil, 0, nil)
    }

    /// Get all currently watched PIDs
    public var watchedPIDs: [pid_t] {
        Array(watchedProcesses.keys)
    }

    /// Check if a specific PID is being watched
    public func isWatching(pid: pid_t) -> Bool {
        watchedProcesses[pid] != nil
    }

    // MARK: - Private Monitor Loop

    private func monitorLoop() async {
        while isRunning && !Task.isCancelled {
            // Wait for events with a timeout to allow cancellation checks
            let emptyEvent = Darwin.kevent(ident: 0, filter: 0, flags: 0, fflags: 0, data: 0, udata: nil)
            var events = [Darwin.kevent](repeating: emptyEvent, count: 16)
            var timeout = timespec(tv_sec: 1, tv_nsec: 0)

            let nEvents = kevent(kq, nil, 0, &events, Int32(events.count), &timeout)

            if nEvents < 0 {
                if errno == EINTR { continue } // Interrupted, retry
                break // Error, stop monitoring
            }

            if nEvents > 0 {
                await processEvents(events[0..<Int(nEvents)])
            }
        }
    }

    private func processEvents(_ events: ArraySlice<kevent>) async {
        for event in events {
            let pid = pid_t(event.ident)

            // Get exit status from event data
            let exitStatus = Int32(truncatingIfNeeded: event.data)

            // Fire callback and remove from watched
            if let watched = watchedProcesses.removeValue(forKey: pid) {
                // Call callback on a separate task to not block the monitor
                let callback = watched.callback
                Task.detached {
                    callback(pid, exitStatus)
                }
            }
        }
    }
}

/// Convenience class for monitoring multiple processes with a shared callback
public actor ProcessGroupMonitor {
    private let monitor: ProcessMonitor
    private var groupProcesses: [pid_t: Int] = [:] // pid -> sessionId

    public init(monitor: ProcessMonitor) {
        self.monitor = monitor
    }

    /// Watch a process as part of a session group
    /// - Parameters:
    ///   - pid: Process ID to watch
    ///   - sessionId: Session this process belongs to
    ///   - callback: Called when process exits
    public func watch(pid: pid_t, sessionId: Int, callback: @escaping ProcessExitCallback) async throws {
        groupProcesses[pid] = sessionId
        try await monitor.watch(pid: pid, callback: { [weak self] pid, status in
            Task {
                await self?.removeProcess(pid: pid)
            }
            callback(pid, status)
        })
    }

    /// Stop watching a process
    public func unwatch(pid: pid_t) async {
        groupProcesses.removeValue(forKey: pid)
        await monitor.unwatch(pid: pid)
    }

    /// Get all processes for a session
    public func processes(forSession sessionId: Int) -> [pid_t] {
        groupProcesses.filter { $0.value == sessionId }.map { $0.key }
    }

    /// Unwatch all processes for a session
    public func unwatchSession(_ sessionId: Int) async {
        let pids = processes(forSession: sessionId)
        for pid in pids {
            groupProcesses.removeValue(forKey: pid)
            await monitor.unwatch(pid: pid)
        }
    }

    private func removeProcess(pid: pid_t) {
        groupProcesses.removeValue(forKey: pid)
    }
}

// MARK: - Process Wait Utilities

public extension ProcessMonitor {
    /// Wait for a process to exit (async)
    /// - Parameter pid: Process ID to wait for
    /// - Returns: Exit status of the process
    func waitForExit(pid: pid_t) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            do {
                try watch(pid: pid) { _, status in
                    continuation.resume(returning: status)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Wait for a process with timeout
    /// - Parameters:
    ///   - pid: Process ID to wait for
    ///   - timeout: Maximum time to wait
    /// - Returns: Exit status, or nil if timeout
    func waitForExit(pid: pid_t, timeout: TimeInterval) async throws -> Int32? {
        try await withThrowingTaskGroup(of: Int32?.self) { group in
            group.addTask {
                try await self.waitForExit(pid: pid)
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }

            let result = try await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }
}
