//
//  MCPServerManager.swift
//  claude-maestro
//
//  Created by Claude Maestro on 15/1/2026.
//

import Foundation
import Combine

/// Manages the MCP (Model Context Protocol) server lifecycle.
///
/// Note: With stdio transport, each Claude Code session spawns its own MCP server
/// instance via the `.mcp.json` configuration. This manager is for optional shared
/// server scenarios (e.g., HTTP transport) or for verifying the MCP server is available.
@MainActor
class MCPServerManager: ObservableObject {
    static let shared = MCPServerManager()

    @Published var isServerAvailable: Bool = false
    @Published var serverPath: String?
    @Published var lastError: String?

    private var healthCheckTimer: Timer?

    private init() {
        checkServerAvailability()
    }

    /// Check if the MCP server is available (built and ready)
    func checkServerAvailability() {
        if let path = ClaudeDocManager.getMCPServerPath() {
            serverPath = path
            isServerAvailable = FileManager.default.fileExists(atPath: path)

            if !isServerAvailable {
                lastError = "MCP server not built. Run 'npm run build' in maestro-mcp-server/"
            } else {
                lastError = nil
            }
        } else {
            serverPath = nil
            isServerAvailable = false
            lastError = "MCP server not found"
        }
    }

    /// Get the MCP server path for configuration
    func getServerPath() -> String? {
        return serverPath
    }

    /// Verify Node.js is available for running the MCP server
    func verifyNodeAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", "--version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Get the full command for Claude Code to spawn the MCP server
    func getMCPCommand() -> (command: String, args: [String])? {
        guard let path = serverPath else { return nil }
        return ("node", [path])
    }

    /// Build the MCP server if needed
    func buildServerIfNeeded() async throws {
        // Find the maestro-mcp-server directory
        guard let bundlePath = Bundle.main.resourcePath else {
            throw MCPError.serverNotFound
        }

        let devPath = URL(fileURLWithPath: bundlePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("maestro-mcp-server")

        guard FileManager.default.fileExists(atPath: devPath.path) else {
            throw MCPError.serverNotFound
        }

        // Check if already built
        let distPath = devPath.appendingPathComponent("dist/index.js")
        if FileManager.default.fileExists(atPath: distPath.path) {
            return // Already built
        }

        // Run npm install and build
        let process = Process()
        process.currentDirectoryURL = devPath
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["npm", "run", "build"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MCPError.buildFailed(output)
        }

        // Refresh availability
        checkServerAvailability()
    }
}

/// Errors related to MCP server management
enum MCPError: LocalizedError {
    case serverNotFound
    case nodeNotAvailable
    case buildFailed(String)
    case serverStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .serverNotFound:
            return "MCP server not found. Ensure maestro-mcp-server is in the project."
        case .nodeNotAvailable:
            return "Node.js is not available. Install Node.js to use MCP features."
        case .buildFailed(let output):
            return "Failed to build MCP server: \(output)"
        case .serverStartFailed(let reason):
            return "Failed to start MCP server: \(reason)"
        }
    }
}
