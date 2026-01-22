import Foundation

/// Handles MCP tool calls using native Swift process management
public actor MCPToolHandler {

    private let coordinator: ManagedProcessCoordinator
    private let processTree: ProcessTree
    private let portManager: NativePortManager

    public init(coordinator: ManagedProcessCoordinator) {
        self.coordinator = coordinator
        self.processTree = ProcessTree()
        self.portManager = NativePortManager()
    }

    // MARK: - Tool Definitions

    public static let toolDefinitions: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "start_dev_server",
            description: "Start a development server for a project",
            inputSchema: JSONSchema(
                properties: [
                    "session_id": .init(type: "number", description: "Maestro session ID"),
                    "command": .init(type: "string", description: "Command to run (e.g., 'npm run dev')"),
                    "working_directory": .init(type: "string", description: "Directory to run in"),
                    "port": .init(type: "number", description: "Preferred port (optional, auto-assigned if not provided)")
                ],
                required: ["session_id", "command", "working_directory"]
            )
        ),
        MCPToolDefinition(
            name: "stop_dev_server",
            description: "Stop a running development server",
            inputSchema: JSONSchema(
                properties: [
                    "session_id": .init(type: "number", description: "Session ID of server to stop")
                ],
                required: ["session_id"]
            )
        ),
        MCPToolDefinition(
            name: "restart_dev_server",
            description: "Restart a development server (stop + start with same config)",
            inputSchema: JSONSchema(
                properties: [
                    "session_id": .init(type: "number", description: "Session ID to restart")
                ],
                required: ["session_id"]
            )
        ),
        MCPToolDefinition(
            name: "get_server_status",
            description: "Get status of a dev server (running, stopped, error, port, URL)",
            inputSchema: JSONSchema(
                properties: [
                    "session_id": .init(type: "number", description: "Session ID to check (optional, lists all if omitted)")
                ]
            )
        ),
        MCPToolDefinition(
            name: "get_server_logs",
            description: "Get recent output logs from a dev server",
            inputSchema: JSONSchema(
                properties: [
                    "session_id": .init(type: "number", description: "Session ID"),
                    "lines": .init(type: "number", description: "Number of recent lines (default 50)"),
                    "stream": .init(type: "string", description: "Which stream", enum: ["stdout", "stderr", "all"])
                ],
                required: ["session_id"]
            )
        ),
        MCPToolDefinition(
            name: "list_available_ports",
            description: "Get available ports in the Maestro-managed range (3000-3099)",
            inputSchema: JSONSchema(
                properties: [
                    "count": .init(type: "number", description: "Number of ports to return (default 5)")
                ]
            )
        ),
        MCPToolDefinition(
            name: "detect_project_type",
            description: "Detect project type and suggest run command based on config files",
            inputSchema: JSONSchema(
                properties: [
                    "directory": .init(type: "string", description: "Project directory to analyze")
                ],
                required: ["directory"]
            )
        ),
        MCPToolDefinition(
            name: "list_system_processes",
            description: "List all system processes listening on TCP ports. Shows both MCP-managed and external processes.",
            inputSchema: JSONSchema(
                properties: [
                    "include_all_ports": .init(type: "boolean", description: "Include all ports (not just dev range 3000-3099)")
                ]
            )
        )
    ]

    // MARK: - Tool Dispatch

    public func handleToolCall(name: String, arguments: [String: AnyCodable]?) async -> MCPToolResult {
        do {
            switch name {
            case "start_dev_server":
                return try await handleStartDevServer(arguments)
            case "stop_dev_server":
                return try await handleStopDevServer(arguments)
            case "restart_dev_server":
                return try await handleRestartDevServer(arguments)
            case "get_server_status":
                return try await handleGetServerStatus(arguments)
            case "get_server_logs":
                return try await handleGetServerLogs(arguments)
            case "list_available_ports":
                return try await handleListAvailablePorts(arguments)
            case "detect_project_type":
                return try await handleDetectProjectType(arguments)
            case "list_system_processes":
                return try await handleListSystemProcesses(arguments)
            default:
                return .error("Unknown tool: \(name)")
            }
        } catch {
            return .error("Error: \(error.localizedDescription)")
        }
    }

    // MARK: - Tool Implementations

    private func handleStartDevServer(_ args: [String: AnyCodable]?) async throws -> MCPToolResult {
        guard let args = args,
              let sessionId = args["session_id"]?.int,
              let command = args["command"]?.string,
              let workingDirectory = args["working_directory"]?.string else {
            return .error("Missing required parameters: session_id, command, working_directory")
        }

        let preferredPort = args["port"]?.int.map { UInt16($0) }

        let process = try await coordinator.startDevServer(
            sessionId: sessionId,
            command: command,
            workingDirectory: workingDirectory,
            preferredPort: preferredPort
        )

        let result: [String: Any] = [
            "success": true,
            "session_id": sessionId,
            "pid": Int(process.pid),
            "port": process.port.map { Int($0) } as Any,
            "status": process.status.rawValue,
            "message": "Server started successfully"
        ]

        return .text(formatJSON(result))
    }

    private func handleStopDevServer(_ args: [String: AnyCodable]?) async throws -> MCPToolResult {
        guard let sessionId = args?["session_id"]?.int else {
            return .error("Missing required parameter: session_id")
        }

        try await coordinator.stopDevServer(sessionId: sessionId)

        let result: [String: Any] = [
            "success": true,
            "session_id": sessionId,
            "message": "Server stopped successfully"
        ]

        return .text(formatJSON(result))
    }

    private func handleRestartDevServer(_ args: [String: AnyCodable]?) async throws -> MCPToolResult {
        guard let sessionId = args?["session_id"]?.int else {
            return .error("Missing required parameter: session_id")
        }

        try await coordinator.restartDevServer(sessionId: sessionId)

        let result: [String: Any] = [
            "success": true,
            "session_id": sessionId,
            "message": "Server restarted successfully"
        ]

        return .text(formatJSON(result))
    }

    private func handleGetServerStatus(_ args: [String: AnyCodable]?) async throws -> MCPToolResult {
        if let sessionId = args?["session_id"]?.int {
            // Single session status
            guard let process = await coordinator.getStatus(sessionId: sessionId) else {
                return .text(formatJSON(["status": "not_found", "session_id": sessionId]))
            }

            return .text(formatJSON(processToDict(process)))
        } else {
            // All statuses
            let all = await coordinator.getAllStatuses()
            let statuses = all.map { processToDict($0) }
            return .text(formatJSON(["servers": statuses, "count": statuses.count]))
        }
    }

    private func handleGetServerLogs(_ args: [String: AnyCodable]?) async throws -> MCPToolResult {
        guard let sessionId = args?["session_id"]?.int else {
            return .error("Missing required parameter: session_id")
        }

        let lines = args?["lines"]?.int ?? 50
        let logs = await coordinator.getLogsAsString(sessionId: sessionId, count: lines)

        return .text(logs.isEmpty ? "No logs available" : logs)
    }

    private func handleListAvailablePorts(_ args: [String: AnyCodable]?) async throws -> MCPToolResult {
        let count = args?["count"]?.int ?? 5
        let ports = await portManager.findAvailablePorts(count: count)

        let result: [String: Any] = [
            "available_ports": ports.map { Int($0) },
            "range": "3000-3099",
            "count": ports.count
        ]

        return .text(formatJSON(result))
    }

    private func handleDetectProjectType(_ args: [String: AnyCodable]?) async throws -> MCPToolResult {
        guard let directory = args?["directory"]?.string else {
            return .error("Missing required parameter: directory")
        }

        let detection = await detectProjectType(in: directory)
        return .text(formatJSON(detection))
    }

    private func handleListSystemProcesses(_ args: [String: AnyCodable]?) async throws -> MCPToolResult {
        let includeAll = args?["include_all_ports"]?.bool ?? false

        let listening = await portManager.scanListeningPorts(processTree: processTree)

        let filtered: [ListeningPort]
        if includeAll {
            filtered = listening
        } else {
            filtered = listening.filter { NativePortManager.isDevPort($0.port) }
        }

        let processes = filtered.map { port -> [String: Any] in
            var dict: [String: Any] = [
                "port": Int(port.port),
                "address": port.address,
                "managed": port.isManaged
            ]
            if let pid = port.pid {
                dict["pid"] = Int(pid)
            }
            if let name = port.processName {
                dict["process_name"] = name
            }
            return dict
        }

        return .text(formatJSON(["processes": processes, "count": processes.count]))
    }

    // MARK: - Helpers

    private func processToDict(_ process: ManagedProcess) -> [String: Any] {
        var dict: [String: Any] = [
            "session_id": process.sessionId,
            "pid": Int(process.pid),
            "status": process.status.rawValue,
            "command": process.command,
            "working_directory": process.workingDirectory,
            "uptime": Int(process.uptime)
        ]

        if let port = process.port {
            dict["port"] = Int(port)
        }
        if let url = process.serverURL {
            dict["url"] = url
        }
        if let exitCode = process.exitCode {
            dict["exit_code"] = Int(exitCode)
        }
        if let error = process.errorMessage {
            dict["error"] = error
        }

        return dict
    }

    private func formatJSON(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    // MARK: - Project Type Detection

    private func detectProjectType(in directory: String) async -> [String: Any] {
        let fm = FileManager.default
        let dirURL = URL(fileURLWithPath: directory)

        // Check for various config files
        let checks: [(String, String, String)] = [
            ("package.json", "node", "npm run dev"),
            ("Cargo.toml", "rust", "cargo run"),
            ("go.mod", "go", "go run ."),
            ("requirements.txt", "python", "python main.py"),
            ("Pipfile", "python", "pipenv run python main.py"),
            ("pyproject.toml", "python", "python -m pytest"),
            ("Gemfile", "ruby", "bundle exec rails server"),
            ("Package.swift", "swift", "swift run"),
            ("pom.xml", "java", "mvn spring-boot:run"),
            ("build.gradle", "java", "gradle bootRun"),
            ("composer.json", "php", "php artisan serve"),
        ]

        for (file, projectType, defaultCommand) in checks {
            let filePath = dirURL.appendingPathComponent(file)
            if fm.fileExists(atPath: filePath.path) {
                var suggestedCommand = defaultCommand

                // Special handling for package.json
                if file == "package.json" {
                    suggestedCommand = await detectNodeCommand(at: filePath) ?? defaultCommand
                }

                return [
                    "detected": true,
                    "project_type": projectType,
                    "config_file": file,
                    "suggested_command": suggestedCommand
                ]
            }
        }

        return [
            "detected": false,
            "message": "Could not detect project type",
            "suggested_command": nil as String? as Any
        ]
    }

    private func detectNodeCommand(at packageJsonPath: URL) async -> String? {
        guard let data = try? Data(contentsOf: packageJsonPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = json["scripts"] as? [String: String] else {
            return nil
        }

        // Priority order for dev commands
        let devCommands = ["dev", "start", "serve", "develop", "watch"]

        for cmd in devCommands {
            if scripts[cmd] != nil {
                return "npm run \(cmd)"
            }
        }

        // Check for specific frameworks
        if let deps = json["dependencies"] as? [String: Any] {
            if deps["next"] != nil {
                return "npm run dev"
            }
            if deps["vite"] != nil {
                return "npm run dev"
            }
            if deps["react-scripts"] != nil {
                return "npm start"
            }
        }

        return nil
    }
}
