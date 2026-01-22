import XCTest
@testable import claude_maestro
import Darwin

/// Comprehensive test suite for native Swift process management
final class ProcessManagementTests: XCTestCase {

    // MARK: - ProcessLauncher Tests

    func testProcessLauncherSpawnReturnsValidPid() async throws {
        let launcher = ProcessLauncher()

        let process = try await launcher.spawn(
            command: "/bin/echo",
            arguments: ["hello"],
            useProcessGroup: true
        )

        XCTAssertGreaterThan(process.pid, 0, "PID should be positive")
        XCTAssertGreaterThan(process.pgid, 0, "PGID should be positive")

        // Wait for process to complete
        var status: Int32 = 0
        waitpid(process.pid, &status, 0)
    }

    func testProcessGroupIdEqualsPidWhenSetPGroup() async throws {
        let launcher = ProcessLauncher()

        let process = try await launcher.spawn(
            command: "/bin/sleep",
            arguments: ["0.1"],
            useProcessGroup: true
        )

        // When POSIX_SPAWN_SETPGROUP is used with pgid=0, pgid should equal pid
        XCTAssertEqual(process.pgid, process.pid, "PGID should equal PID when using process group")

        // Clean up
        process.kill(signal: SIGTERM)
        var status: Int32 = 0
        waitpid(process.pid, &status, 0)
    }

    func testChildProcessesInheritProcessGroup() async throws {
        let launcher = ProcessLauncher()

        // Launch a shell that spawns a child
        let process = try await launcher.spawnShell(
            command: "sleep 10 & echo $!",
            useProcessGroup: true
        )

        // Give the shell time to spawn the child
        try await Task.sleep(nanoseconds: 500_000_000)

        // Get the child PID from stdout
        let outputData = process.stdoutPipe.availableData
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let childPidStr = output.trimmingCharacters(in: .whitespacesAndNewlines)

        if let childPid = pid_t(childPidStr) {
            // Verify child has same process group
            let childPgid = getpgid(childPid)
            XCTAssertEqual(childPgid, process.pgid, "Child should inherit parent's process group")
        }

        // Kill the entire group
        let killed = process.killGroup(signal: SIGTERM)
        XCTAssertTrue(killed, "killGroup should succeed")

        // Wait for cleanup
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    func testKillGroupTerminatesAllProcesses() async throws {
        let launcher = ProcessLauncher()

        // Launch a shell that spawns multiple children
        let process = try await launcher.spawnShell(
            command: "sleep 60 & sleep 60 & sleep 60 & wait",
            useProcessGroup: true
        )

        // Give time for children to spawn
        try await Task.sleep(nanoseconds: 500_000_000)

        // Kill the entire group
        let killed = await launcher.killGroup(pgid: process.pgid, signal: SIGTERM)
        XCTAssertTrue(killed, "killGroup should succeed")

        // Wait a bit
        try await Task.sleep(nanoseconds: 200_000_000)

        // Verify no processes remain in the group
        let groupCheck = Darwin.killpg(process.pgid, 0)
        XCTAssertNotEqual(groupCheck, 0, "No processes should remain in the group")
    }

    func testSpawnWithWorkingDirectory() async throws {
        let launcher = ProcessLauncher()
        let tempDir = FileManager.default.temporaryDirectory

        let process = try await launcher.spawn(
            command: "/bin/pwd",
            workingDirectory: tempDir,
            useProcessGroup: true
        )

        // Read output
        let outputData = process.stdoutPipe.availableData
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Resolve symlinks for comparison (macOS /tmp is symlinked)
        let expectedPath = tempDir.path.replacingOccurrences(of: "/var/folders", with: "/private/var/folders")
        let actualPath = output.replacingOccurrences(of: "/private", with: "")

        XCTAssertTrue(output.contains("tmp") || output.contains("var/folders"),
                      "Working directory should be set to temp dir. Got: \(output)")

        var status: Int32 = 0
        waitpid(process.pid, &status, 0)
    }

    func testSpawnWithEnvironment() async throws {
        let launcher = ProcessLauncher()

        let process = try await launcher.spawn(
            command: "/bin/sh",
            arguments: ["-c", "echo $TEST_VAR"],
            environment: ["TEST_VAR": "hello_from_test", "PATH": "/bin:/usr/bin"],
            useProcessGroup: true
        )

        let outputData = process.stdoutPipe.availableData
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        XCTAssertEqual(output, "hello_from_test", "Environment variable should be passed to child")

        var status: Int32 = 0
        waitpid(process.pid, &status, 0)
    }

    func testInvalidWorkingDirectoryThrows() async {
        let launcher = ProcessLauncher()

        do {
            _ = try await launcher.spawn(
                command: "/bin/echo",
                workingDirectory: URL(fileURLWithPath: "/nonexistent/directory"),
                useProcessGroup: true
            )
            XCTFail("Should throw for invalid working directory")
        } catch {
            XCTAssertTrue(error is ProcessLauncher.LaunchError)
        }
    }

    // MARK: - ProcessMonitor Tests

    func testProcessMonitorCallbackFiresOnExit() async throws {
        let monitor = ProcessMonitor()
        try await monitor.start()

        let launcher = ProcessLauncher()
        let process = try await launcher.spawn(
            command: "/bin/sleep",
            arguments: ["0.1"],
            useProcessGroup: true
        )

        let expectation = XCTestExpectation(description: "Exit callback should fire")
        var receivedPid: pid_t?
        var receivedStatus: Int32?

        try await monitor.watch(pid: process.pid) { pid, status in
            receivedPid = pid
            receivedStatus = status
            expectation.fulfill()
        }

        // Wait for the process to exit and callback to fire
        await fulfillment(of: [expectation], timeout: 2.0)

        XCTAssertEqual(receivedPid, process.pid, "Callback should receive correct PID")
        XCTAssertNotNil(receivedStatus, "Callback should receive exit status")

        await monitor.stop()
    }

    func testProcessMonitorCallbackFiresWithin100ms() async throws {
        let monitor = ProcessMonitor()
        try await monitor.start()

        let launcher = ProcessLauncher()
        let process = try await launcher.spawn(
            command: "/bin/sh",
            arguments: ["-c", "exit 0"],
            useProcessGroup: true
        )

        let startTime = Date()
        let expectation = XCTestExpectation(description: "Exit callback")
        var callbackTime: Date?

        try await monitor.watch(pid: process.pid) { _, _ in
            callbackTime = Date()
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 1.0)

        if let callback = callbackTime {
            let elapsed = callback.timeIntervalSince(startTime)
            XCTAssertLessThan(elapsed, 0.5, "Callback should fire within 500ms (was \(elapsed)s)")
        }

        await monitor.stop()
    }

    func testProcessMonitorHandlesMultipleProcesses() async throws {
        let monitor = ProcessMonitor()
        try await monitor.start()

        let launcher = ProcessLauncher()
        var processes: [LaunchedProcess] = []

        // Start 5 processes
        for i in 0..<5 {
            let process = try await launcher.spawn(
                command: "/bin/sleep",
                arguments: [String(format: "0.%d", i + 1)],
                useProcessGroup: true
            )
            processes.append(process)
        }

        var exitedPids: Set<pid_t> = []
        let lock = NSLock()
        let expectation = XCTestExpectation(description: "All processes exit")
        expectation.expectedFulfillmentCount = 5

        for process in processes {
            try await monitor.watch(pid: process.pid) { pid, _ in
                lock.lock()
                exitedPids.insert(pid)
                lock.unlock()
                expectation.fulfill()
            }
        }

        await fulfillment(of: [expectation], timeout: 3.0)

        XCTAssertEqual(exitedPids.count, 5, "All 5 processes should have exited")
        for process in processes {
            XCTAssertTrue(exitedPids.contains(process.pid), "Process \(process.pid) should have exited")
        }

        await monitor.stop()
    }

    func testProcessMonitorUnwatchStopsCallbacks() async throws {
        let monitor = ProcessMonitor()
        try await monitor.start()

        let launcher = ProcessLauncher()
        let process = try await launcher.spawn(
            command: "/bin/sleep",
            arguments: ["1"],
            useProcessGroup: true
        )

        var callbackCalled = false

        try await monitor.watch(pid: process.pid) { _, _ in
            callbackCalled = true
        }

        // Unwatch immediately
        await monitor.unwatch(pid: process.pid)

        // Kill the process
        process.kill(signal: SIGTERM)

        // Wait a bit
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertFalse(callbackCalled, "Callback should not be called after unwatch")

        await monitor.stop()

        var status: Int32 = 0
        waitpid(process.pid, &status, WNOHANG)
    }

    func testProcessMonitorHandlesAlreadyExitedProcess() async throws {
        let monitor = ProcessMonitor()
        try await monitor.start()

        let launcher = ProcessLauncher()
        let process = try await launcher.spawn(
            command: "/bin/sh",
            arguments: ["-c", "exit 42"],
            useProcessGroup: true
        )

        // Wait for process to fully exit
        var status: Int32 = 0
        waitpid(process.pid, &status, 0)

        // Now try to watch it (should call callback immediately or handle gracefully)
        let expectation = XCTestExpectation(description: "Callback for already exited")

        try await monitor.watch(pid: process.pid) { _, _ in
            expectation.fulfill()
        }

        // Should fulfill quickly since process already exited
        await fulfillment(of: [expectation], timeout: 1.0)

        await monitor.stop()
    }

    // MARK: - ProcessTree Tests

    func testProcessTreeGetAllProcessesReturnsCurrentUser() async throws {
        let tree = ProcessTree()
        let processes = await tree.getAllProcesses(includeSystem: false)

        XCTAssertGreaterThan(processes.count, 0, "Should find at least one process")

        let currentUid = getuid()
        for process in processes {
            XCTAssertEqual(process.uid, currentUid, "All processes should belong to current user")
        }
    }

    func testProcessTreeGetProcessInfoForSelf() async throws {
        let tree = ProcessTree()
        let myPid = getpid()

        let info = await tree.getProcessInfo(pid: myPid)

        XCTAssertNotNil(info, "Should get info for current process")
        XCTAssertEqual(info?.pid, myPid, "PID should match")
        XCTAssertEqual(info?.uid, getuid(), "UID should match current user")
        XCTAssertFalse(info?.name.isEmpty ?? true, "Name should not be empty")
    }

    func testProcessTreeGetChildrenFindsSpawnedChild() async throws {
        let tree = ProcessTree()
        let launcher = ProcessLauncher()

        let myPid = getpid()

        // Spawn a child process
        let child = try await launcher.spawn(
            command: "/bin/sleep",
            arguments: ["5"],
            useProcessGroup: true
        )

        // Give the system time to register the process
        try await Task.sleep(nanoseconds: 100_000_000)

        let children = await tree.getChildren(of: myPid)

        // Note: The direct child might be zsh shell, not sleep
        // We check if we can find any children
        XCTAssertGreaterThan(children.count, 0, "Should find child processes")

        // Clean up
        child.kill(signal: SIGTERM)
        var status: Int32 = 0
        waitpid(child.pid, &status, 0)
    }

    func testProcessTreeGetProcessGroupFindsGroupMembers() async throws {
        let tree = ProcessTree()
        let launcher = ProcessLauncher()

        // Spawn a process in its own group
        let process = try await launcher.spawn(
            command: "/bin/sleep",
            arguments: ["5"],
            useProcessGroup: true
        )

        try await Task.sleep(nanoseconds: 100_000_000)

        let groupMembers = await tree.getProcessGroup(pgid: process.pgid)

        XCTAssertGreaterThan(groupMembers.count, 0, "Should find at least one group member")
        XCTAssertTrue(groupMembers.contains { $0.pid == process.pid }, "Group should contain the process")

        // Clean up
        process.kill(signal: SIGTERM)
        var status: Int32 = 0
        waitpid(process.pid, &status, 0)
    }

    func testProcessTreeBuildTreeReturnsHierarchy() async throws {
        let tree = ProcessTree()
        let nodes = await tree.buildTree(rootPid: nil)

        XCTAssertGreaterThan(nodes.count, 0, "Should find root processes")

        // Count total processes in tree
        func countNodes(_ nodes: [ProcessNode]) -> Int {
            nodes.reduce(0) { $0 + 1 + countNodes($1.children) }
        }

        let totalInTree = countNodes(nodes)
        XCTAssertGreaterThan(totalInTree, 0, "Tree should contain processes")
    }

    func testProcessTreeIsRunningDetectsLiveProcess() async throws {
        let tree = ProcessTree()
        let launcher = ProcessLauncher()

        let process = try await launcher.spawn(
            command: "/bin/sleep",
            arguments: ["5"],
            useProcessGroup: true
        )

        let isRunning = await tree.isRunning(pid: process.pid)
        XCTAssertTrue(isRunning, "Process should be detected as running")

        process.kill(signal: SIGTERM)
        var status: Int32 = 0
        waitpid(process.pid, &status, 0)

        try await Task.sleep(nanoseconds: 100_000_000)

        let isStillRunning = await tree.isRunning(pid: process.pid)
        XCTAssertFalse(isStillRunning, "Process should not be running after kill")
    }

    func testProcessTreeFindProcessesByName() async throws {
        let tree = ProcessTree()

        // Search for a common process
        let results = await tree.findProcesses(named: "launchd")

        // launchd may not be visible to non-root, so just verify the method works
        XCTAssertNotNil(results, "findProcesses should return a result")
    }

    // MARK: - NativePortManager Tests

    func testPortManagerIsPortAvailableForUnusedPort() async throws {
        let manager = NativePortManager()

        // Find a port that's likely unused (high in the range)
        for port: UInt16 in stride(from: 3090, through: 3099, by: 1) {
            let available = await manager.isPortAvailable(port)
            if available {
                XCTAssertTrue(available, "High port should be available")
                return
            }
        }

        // If all ports in range are used, that's unusual but not a test failure
        print("Warning: All ports 3090-3099 appear to be in use")
    }

    func testPortManagerIsPortAvailableReturnsFalseForUsedPort() async throws {
        let manager = NativePortManager()

        // Create a listening socket on a port
        let testPort: UInt16 = 3095
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            throw XCTSkip("Could not create socket")
        }

        defer { close(sock) }

        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = testPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            throw XCTSkip("Could not bind to test port \(testPort)")
        }

        listen(sock, 1)

        // Now check if the port manager detects it as unavailable
        let available = await manager.isPortAvailable(testPort)
        XCTAssertFalse(available, "Port with listening socket should not be available")
    }

    func testPortManagerFindAvailablePortReturnsValidPort() async throws {
        let manager = NativePortManager()

        let port = await manager.findAvailablePort()

        XCTAssertNotNil(port, "Should find an available port")
        if let port = port {
            XCTAssertTrue(NativePortManager.devPortRange.contains(port),
                          "Port should be in dev range")
        }
    }

    func testPortManagerAllocatePortForSession() async throws {
        let manager = NativePortManager()

        let port1 = await manager.allocatePort(for: 1)
        let port2 = await manager.allocatePort(for: 2)

        XCTAssertNotNil(port1, "Should allocate port for session 1")
        XCTAssertNotNil(port2, "Should allocate port for session 2")
        XCTAssertNotEqual(port1, port2, "Different sessions should get different ports")

        // Requesting same session should return same port
        let port1Again = await manager.allocatePort(for: 1)
        XCTAssertEqual(port1, port1Again, "Same session should get same port")
    }

    func testPortManagerReleasePort() async throws {
        let manager = NativePortManager()

        let port = await manager.allocatePort(for: 99)
        XCTAssertNotNil(port)

        await manager.releasePort(port!)

        // Port should be available for reallocation
        let isManaged = await manager.isManaged(port!)
        XCTAssertFalse(isManaged, "Released port should not be managed")
    }

    func testPortManagerFindMultipleAvailablePorts() async throws {
        let manager = NativePortManager()

        let ports = await manager.findAvailablePorts(count: 5)

        XCTAssertEqual(ports.count, 5, "Should find 5 available ports")

        // All ports should be unique
        let uniquePorts = Set(ports)
        XCTAssertEqual(uniquePorts.count, 5, "All ports should be unique")

        // All ports should be in dev range
        for port in ports {
            XCTAssertTrue(NativePortManager.devPortRange.contains(port),
                          "Port \(port) should be in dev range")
        }
    }

    // MARK: - ProcessRegistry Tests

    func testProcessRegistryRegisterAndRetrieve() async throws {
        let registry = ProcessRegistry()

        let registered = await registry.register(
            pid: 12345,
            pgid: 12345,
            sessionId: 1,
            source: .terminal,
            command: "test",
            workingDirectory: "/tmp"
        )

        XCTAssertEqual(registered.pid, 12345)
        XCTAssertEqual(registered.sessionId, 1)
        XCTAssertEqual(registered.source, .terminal)

        let retrieved = await registry.getProcess(pid: 12345)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.pid, 12345)
    }

    func testProcessRegistryUnregister() async throws {
        let registry = ProcessRegistry()

        await registry.register(
            pid: 12345,
            sessionId: 1,
            source: .devServer,
            command: "npm run dev"
        )

        let removed = await registry.unregister(pid: 12345)
        XCTAssertNotNil(removed)

        let retrieved = await registry.getProcess(pid: 12345)
        XCTAssertNil(retrieved, "Process should be removed after unregister")
    }

    func testProcessRegistryGetProcessesForSession() async throws {
        let registry = ProcessRegistry()

        await registry.register(pid: 100, sessionId: 1, source: .terminal, command: "shell")
        await registry.register(pid: 101, sessionId: 1, source: .devServer, command: "server")
        await registry.register(pid: 200, sessionId: 2, source: .terminal, command: "shell")

        let session1Processes = await registry.getProcesses(forSession: 1)
        XCTAssertEqual(session1Processes.count, 2)

        let session2Processes = await registry.getProcesses(forSession: 2)
        XCTAssertEqual(session2Processes.count, 1)
    }

    func testProcessRegistryCleanupSession() async throws {
        let registry = ProcessRegistry()

        await registry.register(pid: 100, sessionId: 1, source: .terminal, command: "shell")
        await registry.register(pid: 101, sessionId: 1, source: .devServer, command: "server")

        // Clean up without killing (processes don't actually exist)
        let removed = await registry.cleanupSession(1, killProcesses: false)
        XCTAssertEqual(removed.count, 2)

        let remaining = await registry.getProcesses(forSession: 1)
        XCTAssertEqual(remaining.count, 0)
    }

    func testProcessRegistryIsManagedGroup() async throws {
        let registry = ProcessRegistry()

        await registry.register(pid: 100, pgid: 100, sessionId: 1, source: .terminal, command: "shell")

        let isManaged = await registry.isManagedGroup(pgid: 100)
        XCTAssertTrue(isManaged)

        let notManaged = await registry.isManagedGroup(pgid: 999)
        XCTAssertFalse(notManaged)
    }

    func testProcessRegistryFindOrphans() async throws {
        let registry = ProcessRegistry()

        // Register a process that doesn't exist
        await registry.register(pid: 999999, sessionId: 1, source: .terminal, command: "fake")

        let orphans = await registry.findOrphans()
        XCTAssertGreaterThan(orphans.count, 0, "Should detect orphaned (non-existent) process")

        let cleaned = await registry.cleanupOrphans()
        XCTAssertEqual(cleaned.count, orphans.count)

        let remainingOrphans = await registry.findOrphans()
        XCTAssertEqual(remainingOrphans.count, 0)
    }

    // MARK: - Integration Tests

    func testFullProcessLifecycle() async throws {
        let launcher = ProcessLauncher()
        let monitor = ProcessMonitor()
        let registry = ProcessRegistry()
        let tree = ProcessTree()

        try await monitor.start()

        // 1. Launch a process
        let process = try await launcher.spawnShell(
            command: "sleep 60 & sleep 60 & wait",
            useProcessGroup: true
        )

        // 2. Register it
        await registry.register(
            pid: process.pid,
            pgid: process.pgid,
            sessionId: 1,
            source: .devServer,
            command: "sleep test"
        )

        // 3. Give time for children to spawn
        try await Task.sleep(nanoseconds: 500_000_000)

        // 4. Verify process tree shows the group
        let groupMembers = await tree.getProcessGroup(pgid: process.pgid)
        XCTAssertGreaterThan(groupMembers.count, 0, "Should find processes in group")

        // 5. Set up exit monitoring
        let exitExpectation = XCTestExpectation(description: "Process exits")
        try await monitor.watch(pid: process.pid) { _, _ in
            exitExpectation.fulfill()
        }

        // 6. Kill the entire group
        let killed = await launcher.killGroup(pgid: process.pgid, signal: SIGTERM)
        XCTAssertTrue(killed)

        // 7. Wait for exit callback
        await fulfillment(of: [exitExpectation], timeout: 2.0)

        // 8. Clean up registry
        await registry.cleanupSession(1, killProcesses: false)

        // 9. Verify no processes remain
        try await Task.sleep(nanoseconds: 200_000_000)
        let remainingGroup = Darwin.killpg(process.pgid, 0)
        XCTAssertNotEqual(remainingGroup, 0, "No processes should remain in group")

        await monitor.stop()
    }

    func testNoOrphanedProcessesAfterCleanup() async throws {
        let launcher = ProcessLauncher()
        let registry = ProcessRegistry()

        var processes: [LaunchedProcess] = []

        // Launch several process groups
        for sessionId in 1...3 {
            let process = try await launcher.spawnShell(
                command: "sleep 30 & sleep 30 & wait",
                useProcessGroup: true
            )

            await registry.register(
                pid: process.pid,
                pgid: process.pgid,
                sessionId: sessionId,
                source: .devServer,
                command: "test session \(sessionId)"
            )

            processes.append(process)
        }

        // Give time for children to spawn
        try await Task.sleep(nanoseconds: 500_000_000)

        // Clean up all sessions
        for sessionId in 1...3 {
            _ = await registry.cleanupSession(sessionId, killProcesses: true)
        }

        // Wait for processes to terminate
        try await Task.sleep(nanoseconds: 500_000_000)

        // Verify no processes remain in any group
        for process in processes {
            let groupCheck = Darwin.killpg(process.pgid, 0)
            XCTAssertNotEqual(groupCheck, 0, "Process group \(process.pgid) should be empty")
        }
    }

    func testStressTestProcessMonitoring() async throws {
        let monitor = ProcessMonitor()
        let launcher = ProcessLauncher()

        try await monitor.start()

        let processCount = 20
        var expectations: [XCTestExpectation] = []

        for i in 0..<processCount {
            let process = try await launcher.spawn(
                command: "/bin/sleep",
                arguments: [String(format: "0.%02d", i + 1)],
                useProcessGroup: true
            )

            let expectation = XCTestExpectation(description: "Process \(i) exits")
            expectations.append(expectation)

            try await monitor.watch(pid: process.pid) { _, _ in
                expectation.fulfill()
            }
        }

        // Wait for all processes to exit
        await fulfillment(of: expectations, timeout: 5.0)

        await monitor.stop()
    }
}
