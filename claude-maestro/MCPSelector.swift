//
//  MCPSelector.swift
//  claude-maestro
//
//  MCP server selection dropdown for session headers
//

import SwiftUI

struct MCPSelector: View {
    let sessionId: Int
    @ObservedObject var mcpManager: MCPServerManager
    var isDisabled: Bool = false

    private var sessionConfig: SessionMCPConfig {
        mcpManager.getMCPConfig(for: sessionId)
    }

    /// Count of enabled MCP servers for this session
    private var enabledCount: Int {
        var count = 0
        if sessionConfig.maestroEnabled {
            count += 1
        }
        // Count custom servers that are both globally enabled AND enabled for this session
        count += mcpManager.customServers.filter { server in
            server.isEnabled && sessionConfig.isServerEnabled(server.id)
        }.count
        return count
    }

    /// List of enabled server names for tooltip
    private var enabledServerNames: [String] {
        var names: [String] = []
        if sessionConfig.maestroEnabled {
            names.append("Maestro")
        }
        for server in mcpManager.customServers where server.isEnabled && sessionConfig.isServerEnabled(server.id) {
            names.append(server.name)
        }
        return names
    }

    /// Globally enabled custom servers (available for selection)
    private var availableCustomServers: [MCPServerConfig] {
        mcpManager.customServers.filter { $0.isEnabled }
    }

    var body: some View {
        Group {
            if isDisabled {
                // Post-launch: Read-only badge
                readOnlyBadge
            } else {
                // Pre-launch: Interactive dropdown
                interactiveDropdown
            }
        }
        .onAppear {
            // Initialize session config with defaults if needed
            mcpManager.initializeSessionConfig(for: sessionId)
        }
    }

    // MARK: - Read-Only Badge (Post-Launch)

    private var readOnlyBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "server.rack")
            Text("\(enabledCount) MCP")
        }
        .font(.caption2)
        .foregroundColor(.purple)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.purple.opacity(0.15))
        .cornerRadius(6)
        .help(enabledServerNames.isEmpty ? "No MCP servers" : enabledServerNames.joined(separator: ", "))
    }

    // MARK: - Interactive Dropdown (Pre-Launch)

    private var interactiveDropdown: some View {
        Menu {
            // Maestro MCP section
            Section("Maestro") {
                Toggle(isOn: Binding(
                    get: { sessionConfig.maestroEnabled },
                    set: { mcpManager.setMaestroEnabled($0, for: sessionId) }
                )) {
                    Label("Maestro MCP", systemImage: "cpu")
                }
            }

            // Custom servers section
            Section("Custom Servers") {
                if availableCustomServers.isEmpty {
                    Text("No custom servers")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(availableCustomServers) { server in
                        Toggle(isOn: Binding(
                            get: { sessionConfig.isServerEnabled(server.id) },
                            set: { mcpManager.setServerEnabled(server.id, enabled: $0, for: sessionId) }
                        )) {
                            Label(server.name, systemImage: "externaldrive.connected.to.line.below")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "server.rack")
                Text("\(enabledCount)")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.purple.opacity(0.15))
            .cornerRadius(6)
        }
    }
}

#Preview {
    HStack {
        MCPSelector(
            sessionId: 1,
            mcpManager: MCPServerManager.shared,
            isDisabled: false
        )
        MCPSelector(
            sessionId: 1,
            mcpManager: MCPServerManager.shared,
            isDisabled: true
        )
    }
    .padding()
}
