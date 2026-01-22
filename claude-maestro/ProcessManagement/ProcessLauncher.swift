import Foundation
import Darwin

/// Result of launching a process with posix_spawn
public struct LaunchedProcess: Sendable {
    public let pid: pid_t
    public let pgid: pid_t
    public let stdinPipe: FileHandle
    public let stdoutPipe: FileHandle
    public let stderrPipe: FileHandle

    /// Kill the entire process group
    public func killGroup(signal: Int32 = SIGTERM) -> Bool {
        guard pgid > 0 else { return false }
        return Darwin.killpg(pgid, signal) == 0
    }

    /// Kill just this process
    public func kill(signal: Int32 = SIGTERM) -> Bool {
        guard pid > 0 else { return false }
        return Darwin.kill(pid, signal) == 0
    }

    /// Check if process is still running
    public var isRunning: Bool {
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        return result == 0 // 0 means child still running
    }
}

/// Native process launcher using posix_spawn with process groups
public actor ProcessLauncher {

    /// Errors that can occur during process launch
    public enum LaunchError: Error, LocalizedError {
        case spawnFailed(errno: Int32)
        case invalidWorkingDirectory
        case attributeInitFailed
        case fileActionsFailed
        case pipeCreationFailed
        case forkFailed

        public var errorDescription: String? {
            switch self {
            case .spawnFailed(let errno):
                return "posix_spawn failed: \(String(cString: strerror(errno)))"
            case .invalidWorkingDirectory:
                return "Invalid working directory"
            case .attributeInitFailed:
                return "Failed to initialize spawn attributes"
            case .fileActionsFailed:
                return "Failed to set up file actions"
            case .pipeCreationFailed:
                return "Failed to create pipes"
            case .forkFailed:
                return "Fork failed"
            }
        }
    }

    public init() {}

    /// Launch a process with full process group support
    /// - Parameters:
    ///   - command: The command to execute (resolved via PATH)
    ///   - arguments: Arguments to pass (command is NOT included)
    ///   - workingDirectory: Directory to run in
    ///   - environment: Environment variables (defaults to current environment)
    ///   - useProcessGroup: If true, creates a new process group (pgid = pid)
    /// - Returns: LaunchedProcess with pid, pgid, and stdio handles
    public func spawn(
        command: String,
        arguments: [String] = [],
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        useProcessGroup: Bool = true
    ) throws -> LaunchedProcess {
        // Resolve command path
        let commandPath = resolveCommand(command)

        // Validate working directory
        if let dir = workingDirectory {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                throw LaunchError.invalidWorkingDirectory
            }
        }

        // Create pipes for stdin, stdout, stderr
        var stdinPipe: [Int32] = [0, 0]
        var stdoutPipe: [Int32] = [0, 0]
        var stderrPipe: [Int32] = [0, 0]

        guard pipe(&stdinPipe) == 0,
              pipe(&stdoutPipe) == 0,
              pipe(&stderrPipe) == 0 else {
            throw LaunchError.pipeCreationFailed
        }

        // Build environment array
        var envArray: [UnsafeMutablePointer<CChar>?]
        if let env = environment {
            envArray = env.map { key, value in
                strdup("\(key)=\(value)")
            }
        } else {
            // Use current environment
            var currentEnv: [UnsafeMutablePointer<CChar>?] = []
            var index = 0
            while let ptr = environ[index] {
                currentEnv.append(strdup(String(cString: ptr)))
                index += 1
            }
            envArray = currentEnv
        }
        envArray.append(nil)

        defer {
            for ptr in envArray {
                free(ptr)
            }
        }

        // Build arguments array (command must be first)
        let args = [command] + arguments
        var argArray = args.map { strdup($0) }
        argArray.append(nil)

        defer {
            for ptr in argArray {
                free(ptr)
            }
        }

        // Initialize spawn attributes
        var attr: posix_spawnattr_t?
        guard posix_spawnattr_init(&attr) == 0 else {
            closeAllPipes(stdin: stdinPipe, stdout: stdoutPipe, stderr: stderrPipe)
            throw LaunchError.attributeInitFailed
        }
        defer { posix_spawnattr_destroy(&attr) }

        // Set process group flag if requested
        if useProcessGroup {
            var flags: Int16 = 0
            posix_spawnattr_getflags(&attr, &flags)
            flags |= Int16(POSIX_SPAWN_SETPGROUP)
            posix_spawnattr_setflags(&attr, flags)
            posix_spawnattr_setpgroup(&attr, 0) // pgid = pid
        }

        // Set up file actions
        var fileActions: posix_spawn_file_actions_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            closeAllPipes(stdin: stdinPipe, stdout: stdoutPipe, stderr: stderrPipe)
            throw LaunchError.fileActionsFailed
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }

        // stdin: close write end, dup read end to fd 0
        posix_spawn_file_actions_addclose(&fileActions, stdinPipe[1])
        posix_spawn_file_actions_adddup2(&fileActions, stdinPipe[0], STDIN_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, stdinPipe[0])

        // stdout: close read end, dup write end to fd 1
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[0])
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[1])

        // stderr: close read end, dup write end to fd 2
        posix_spawn_file_actions_addclose(&fileActions, stderrPipe[0])
        posix_spawn_file_actions_adddup2(&fileActions, stderrPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, stderrPipe[1])

        // Change working directory if specified
        if let dir = workingDirectory {
            // Use posix_spawn_file_actions_addchdir (the non-np version)
            // Falls back to addchdir_np on older systems
            if #available(macOS 26.0, *) {
                posix_spawn_file_actions_addchdir(&fileActions, dir.path)
            } else {
                posix_spawn_file_actions_addchdir_np(&fileActions, dir.path)
            }
        }

        // Spawn the process
        var pid: pid_t = 0
        let spawnResult = posix_spawn(
            &pid,
            commandPath,
            &fileActions,
            &attr,
            &argArray,
            &envArray
        )

        // Close child ends of pipes in parent
        close(stdinPipe[0])   // Child's stdin read end
        close(stdoutPipe[1])  // Child's stdout write end
        close(stderrPipe[1])  // Child's stderr write end

        guard spawnResult == 0 else {
            close(stdinPipe[1])
            close(stdoutPipe[0])
            close(stderrPipe[0])
            throw LaunchError.spawnFailed(errno: spawnResult)
        }

        // Get the process group ID
        let pgid = useProcessGroup ? pid : getpgid(pid)

        return LaunchedProcess(
            pid: pid,
            pgid: pgid,
            stdinPipe: FileHandle(fileDescriptor: stdinPipe[1], closeOnDealloc: true),
            stdoutPipe: FileHandle(fileDescriptor: stdoutPipe[0], closeOnDealloc: true),
            stderrPipe: FileHandle(fileDescriptor: stderrPipe[0], closeOnDealloc: true)
        )
    }

    /// Spawn a shell command (via /bin/zsh -l -c)
    public func spawnShell(
        command: String,
        workingDirectory: URL? = nil,
        environment: [String: String]? = nil,
        useProcessGroup: Bool = true
    ) throws -> LaunchedProcess {
        try spawn(
            command: "/bin/zsh",
            arguments: ["-l", "-c", command],
            workingDirectory: workingDirectory,
            environment: environment,
            useProcessGroup: useProcessGroup
        )
    }

    /// Kill an entire process group
    /// - Parameters:
    ///   - pgid: Process group ID to kill
    ///   - signal: Signal to send (default SIGTERM)
    /// - Returns: True if signal was sent successfully
    public func killGroup(pgid: pid_t, signal: Int32 = SIGTERM) -> Bool {
        guard pgid > 0 else { return false }
        return Darwin.killpg(pgid, signal) == 0
    }

    /// Kill a single process
    /// - Parameters:
    ///   - pid: Process ID to kill
    ///   - signal: Signal to send (default SIGTERM)
    /// - Returns: True if signal was sent successfully
    public func killProcess(pid: pid_t, signal: Int32 = SIGTERM) -> Bool {
        guard pid > 0 else { return false }
        return Darwin.kill(pid, signal) == 0
    }

    /// Gracefully terminate a process group with escalation
    /// - Parameters:
    ///   - pgid: Process group ID
    ///   - gracePeriod: Time to wait after SIGTERM before SIGKILL
    public func terminateGroup(pgid: pid_t, gracePeriod: TimeInterval = 5.0) async {
        guard pgid > 0 else { return }

        // First, send SIGTERM to the group
        Darwin.killpg(pgid, SIGTERM)

        // Wait for grace period, checking if processes exit
        let checkInterval: TimeInterval = 0.1
        var elapsed: TimeInterval = 0

        while elapsed < gracePeriod {
            try? await Task.sleep(nanoseconds: UInt64(checkInterval * 1_000_000_000))
            elapsed += checkInterval

            // Check if any processes remain in the group
            if !hasProcessesInGroup(pgid: pgid) {
                return
            }
        }

        // Grace period expired, send SIGKILL
        Darwin.killpg(pgid, SIGKILL)
    }

    // MARK: - Private Helpers

    private func resolveCommand(_ command: String) -> String {
        // If it's already an absolute path, return it
        if command.hasPrefix("/") {
            return command
        }

        // Search in PATH
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        for path in paths {
            let fullPath = "\(path)/\(command)"
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        // Return as-is, let posix_spawn fail with proper error
        return command
    }

    private func closeAllPipes(stdin: [Int32], stdout: [Int32], stderr: [Int32]) {
        close(stdin[0]); close(stdin[1])
        close(stdout[0]); close(stdout[1])
        close(stderr[0]); close(stderr[1])
    }

    private func hasProcessesInGroup(pgid: pid_t) -> Bool {
        // Use kill with signal 0 to check if any process exists
        return Darwin.killpg(pgid, 0) == 0
    }
}
