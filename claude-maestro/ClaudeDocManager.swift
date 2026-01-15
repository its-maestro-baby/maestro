//
//  ClaudeDocManager.swift
//  claude-maestro
//
//  Created by Jack Wakem on 14/1/2026.
//

import Foundation

class ClaudeDocManager {

    /// Get the path to the bundled MCP server
    static func getMCPServerPath() -> String? {
        // Primary: Check app bundle Resources (dist folder is copied directly to Resources)
        if let bundlePath = Bundle.main.resourcePath {
            let bundledPath = URL(fileURLWithPath: bundlePath)
                .appendingPathComponent("dist/index.js")
            if FileManager.default.fileExists(atPath: bundledPath.path) {
                return bundledPath.path
            }
        }

        // Fallback for development: relative to Xcode build output
        if let bundlePath = Bundle.main.resourcePath {
            let devPath = URL(fileURLWithPath: bundlePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("maestro-mcp-server/dist/index.js")
            if FileManager.default.fileExists(atPath: devPath.path) {
                return devPath.path
            }
        }

        return nil
    }

    /// Detect run command based on common project configuration files
    static func detectRunCommand(for projectPath: String) -> String? {
        let fm = FileManager.default
        let baseURL = URL(fileURLWithPath: projectPath)

        // Check for package.json (Node.js)
        let packageJson = baseURL.appendingPathComponent("package.json")
        if fm.fileExists(atPath: packageJson.path),
           let data = try? Data(contentsOf: packageJson),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let scripts = json["scripts"] as? [String: String] {
            if scripts["dev"] != nil { return "npm run dev" }
            if scripts["start"] != nil { return "npm start" }
        }

        // Check for Cargo.toml (Rust)
        if fm.fileExists(atPath: baseURL.appendingPathComponent("Cargo.toml").path) {
            return "cargo run"
        }

        // Check for Package.swift (Swift)
        if fm.fileExists(atPath: baseURL.appendingPathComponent("Package.swift").path) {
            return "swift run"
        }

        // Check for pyproject.toml (Python)
        if fm.fileExists(atPath: baseURL.appendingPathComponent("pyproject.toml").path) {
            return "python -m pytest"
        }

        // Check for requirements.txt (Python)
        if fm.fileExists(atPath: baseURL.appendingPathComponent("requirements.txt").path) {
            return "python main.py"
        }

        // Check for Makefile
        if fm.fileExists(atPath: baseURL.appendingPathComponent("Makefile").path) {
            return "make run"
        }

        // Check for go.mod (Go)
        if fm.fileExists(atPath: baseURL.appendingPathComponent("go.mod").path) {
            return "go run ."
        }

        return nil
    }

    /// Generate claude.md content for a project
    static func generateContent(
        projectPath: String,
        runCommand: String?,
        branch: String?,
        sessionId: Int,
        port: Int?,
        mcpServerPath: String? = nil
    ) -> String {
        var content = """
        # Claude Code Session Context

        This file provides context for Claude Code running in this worktree.

        ## Project Information
        - **Path:** \(projectPath)
        """

        if let branch = branch {
            content += "\n- **Branch:** \(branch)"
        }

        content += "\n- **Session ID:** \(sessionId)"

        if let port = port {
            content += "\n- **Assigned Port:** \(port)"
        }

        // Add MCP Server Integration section
        if mcpServerPath != nil {
            content += """


            ## MCP Server Integration

            This session is connected to Claude Maestro's process management server.

            ### Available MCP Tools

            Use these tools to manage your development server:

            - `start_dev_server` - Start the dev server for this project
              - Required: session_id=\(sessionId), command (e.g., "npm run dev"), working_directory
              - Optional: port (will be auto-assigned from 3000-3099 range)
            - `stop_dev_server` - Stop the running dev server (session_id=\(sessionId))
            - `restart_dev_server` - Restart the dev server (session_id=\(sessionId))
            - `get_server_status` - Check if your server is running
            - `get_server_logs` - View recent server output
            - `list_available_ports` - See available ports
            - `detect_project_type` - Auto-detect project type and run command
            """
        }

        content += "\n\n## Running the Application\n"

        if let cmd = runCommand {
            content += """

            To run this application, use:
            ```bash
            \(cmd)
            ```
            """

            if mcpServerPath != nil {
                content += """


            Or use the MCP tool:
            ```
            Use the start_dev_server tool with session_id=\(sessionId), command="\(cmd)", working_directory="\(projectPath)"
            ```
            """
            }
        } else {
            content += """

            The run command has not been configured yet. Common commands:
            - `npm run dev` - Node.js projects
            - `swift run` - Swift packages
            - `cargo run` - Rust projects
            - `python main.py` - Python projects
            - `go run .` - Go projects
            """

            if mcpServerPath != nil {
                content += """


            Use the `detect_project_type` MCP tool to auto-detect the run command.
            """
            }
        }

        content += """


        ## Session Notes

        This worktree is managed by Claude Maestro. Changes made here are isolated
        from other sessions working on different branches.

        ---
        *Auto-generated by Claude Maestro*
        """

        return content
    }

    /// Generate .mcp.json content for Claude Code MCP configuration
    static func generateMCPConfig(mcpServerPath: String, sessionId: Int, portRangeStart: Int = 3000, portRangeEnd: Int = 3099) -> String {
        return """
        {
          "mcpServers": {
            "maestro": {
              "type": "stdio",
              "command": "node",
              "args": ["\(mcpServerPath)"],
              "env": {
                "MAESTRO_SESSION_ID": "\(sessionId)",
                "MAESTRO_PORT_RANGE_START": "\(portRangeStart)",
                "MAESTRO_PORT_RANGE_END": "\(portRangeEnd)"
              }
            }
          }
        }
        """
    }

    /// Write .mcp.json to the specified directory
    static func writeMCPConfig(
        to directory: String,
        mcpServerPath: String,
        sessionId: Int
    ) {
        let content = generateMCPConfig(mcpServerPath: mcpServerPath, sessionId: sessionId)
        let filePath = URL(fileURLWithPath: directory)
            .appendingPathComponent(".mcp.json")

        do {
            try content.write(to: filePath, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to generate .mcp.json: \(error)")
        }
    }

    /// Write claude.md to the specified directory
    static func writeClaudeMD(
        to directory: String,
        projectPath: String,
        runCommand: String?,
        branch: String?,
        sessionId: Int,
        port: Int?
    ) {
        let effectiveRunCommand = runCommand ?? detectRunCommand(for: directory)
        let mcpServerPath = getMCPServerPath()

        let content = generateContent(
            projectPath: projectPath,
            runCommand: effectiveRunCommand,
            branch: branch,
            sessionId: sessionId,
            port: port,
            mcpServerPath: mcpServerPath
        )

        let filePath = URL(fileURLWithPath: directory)
            .appendingPathComponent("claude.md")

        do {
            try content.write(to: filePath, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to generate claude.md: \(error)")
        }

        // Also write .mcp.json if MCP server is available
        if let mcpPath = mcpServerPath {
            writeMCPConfig(to: directory, mcpServerPath: mcpPath, sessionId: sessionId)
        }
    }
}
