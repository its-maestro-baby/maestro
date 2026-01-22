import Foundation

/// Swift MCP server using stdio transport
/// Replaces the Node.js MCP server with native Swift implementation
public actor MCPStdioServer {

    private let toolHandler: MCPToolHandler
    private var isRunning = false

    private static let serverInfo = MCPServerInfo(
        name: "maestro-native",
        version: "2.0.0"
    )

    private static let serverCapabilities = MCPServerCapabilities(
        tools: .init(listChanged: false)
    )

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(coordinator: ManagedProcessCoordinator) {
        self.toolHandler = MCPToolHandler(coordinator: coordinator)
        encoder.outputFormatting = [.sortedKeys]
    }

    // MARK: - Server Lifecycle

    /// Start the MCP server (blocks on stdin read loop)
    public func start() async {
        guard !isRunning else { return }
        isRunning = true

        log("Maestro MCP Server starting...")

        // Read lines from stdin
        while isRunning {
            guard let line = readLine() else {
                // EOF - stdin closed
                break
            }

            if line.isEmpty { continue }

            await processLine(line)
        }

        log("Maestro MCP Server stopped")
    }

    /// Stop the server
    public func stop() {
        isRunning = false
    }

    // MARK: - Request Processing

    private func processLine(_ line: String) async {
        guard let data = line.data(using: .utf8) else {
            await sendError(id: nil, code: MCPError.parseError, message: "Invalid UTF-8")
            return
        }

        // Parse JSON-RPC request
        let request: MCPRequest
        do {
            request = try decoder.decode(MCPRequest.self, from: data)
        } catch {
            await sendError(id: nil, code: MCPError.parseError, message: "Parse error: \(error.localizedDescription)")
            return
        }

        // Handle the request
        let response = await handleRequest(request)

        // Send response
        await sendResponse(response)
    }

    private func handleRequest(_ request: MCPRequest) async -> MCPResponse {
        log("Received: \(request.method)")

        switch request.method {
        case "initialize":
            return handleInitialize(request)

        case "initialized":
            // Notification - no response needed
            return MCPResponse(id: nil)

        case "tools/list":
            return handleToolsList(request)

        case "tools/call":
            return await handleToolsCall(request)

        case "ping":
            return MCPResponse.success(id: request.id, result: [:])

        default:
            return MCPResponse.error(
                id: request.id,
                code: MCPError.methodNotFound,
                message: "Method not found: \(request.method)"
            )
        }
    }

    // MARK: - Protocol Handlers

    private func handleInitialize(_ request: MCPRequest) -> MCPResponse {
        let result = MCPInitializeResult(
            protocolVersion: "2024-11-05",
            capabilities: Self.serverCapabilities,
            serverInfo: Self.serverInfo
        )

        // Encode result to dictionary
        if let data = try? encoder.encode(result),
           let dict = try? JSONSerialization.jsonObject(with: data) {
            return MCPResponse.success(id: request.id, result: dict)
        }

        return MCPResponse.error(id: request.id, code: MCPError.internalError, message: "Failed to encode result")
    }

    private func handleToolsList(_ request: MCPRequest) -> MCPResponse {
        let tools = MCPToolHandler.toolDefinitions

        // Encode tools to array of dictionaries
        if let data = try? encoder.encode(tools),
           let array = try? JSONSerialization.jsonObject(with: data) {
            return MCPResponse.success(id: request.id, result: ["tools": array])
        }

        return MCPResponse.error(id: request.id, code: MCPError.internalError, message: "Failed to encode tools")
    }

    private func handleToolsCall(_ request: MCPRequest) async -> MCPResponse {
        // Parse tool call params
        guard let paramsValue = request.params?.value as? [String: Any],
              let name = paramsValue["name"] as? String else {
            return MCPResponse.error(
                id: request.id,
                code: MCPError.invalidParams,
                message: "Missing tool name"
            )
        }

        // Parse arguments
        var arguments: [String: AnyCodable]?
        if let args = paramsValue["arguments"] as? [String: Any] {
            arguments = args.mapValues { AnyCodable($0) }
        }

        log("Tool call: \(name)")

        // Execute tool
        let result = await toolHandler.handleToolCall(name: name, arguments: arguments)

        // Encode result
        if let data = try? encoder.encode(result),
           let dict = try? JSONSerialization.jsonObject(with: data) {
            return MCPResponse.success(id: request.id, result: dict)
        }

        return MCPResponse.error(id: request.id, code: MCPError.internalError, message: "Failed to encode result")
    }

    // MARK: - Response Writing

    private func sendResponse(_ response: MCPResponse) async {
        // Don't send response for notifications (id is nil and no result/error)
        if response.id == nil && response.result == nil && response.error == nil {
            return
        }

        guard let data = try? encoder.encode(response),
              let json = String(data: data, encoding: .utf8) else {
            log("Failed to encode response")
            return
        }

        // Write to stdout
        print(json)
        fflush(stdout)
    }

    private func sendError(id: RequestId?, code: Int, message: String) async {
        let response = MCPResponse.error(id: id, code: code, message: message)
        await sendResponse(response)
    }

    // MARK: - Logging

    private func log(_ message: String) {
        // Log to stderr so it doesn't interfere with JSON-RPC on stdout
        FileHandle.standardError.write("[\(Date())] \(message)\n".data(using: .utf8)!)
    }
}

// MARK: - Main Entry Point for CLI

/// Main entry point for the Maestro MCP Server CLI
@main
struct MaestroMCPServerMain {
    static func main() async {
        // Create coordinator (this would normally be injected)
        // For the CLI tool, we create a fresh one
        let coordinator = await ManagedProcessCoordinator()

        // Wait for coordinator to be ready
        while await !coordinator.isReady {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Create and start server
        let server = MCPStdioServer(coordinator: coordinator)
        await server.start()
    }
}
