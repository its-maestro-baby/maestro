//
//  AppEditorSheet.swift
//  claude-maestro
//
//  Create/edit app form with sections for basic info and toggle lists
//

import SwiftUI

/// Sheet for creating or editing an app configuration
struct AppEditorSheet: View {
    let app: AppConfig?
    let onSave: (AppConfig) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var icon: String = "app.fill"
    @State private var description: String = ""
    @State private var defaultMode: TerminalMode = .claudeCode
    @State private var defaultProjectPath: String = ""
    @State private var maestroMCPEnabled: Bool = true

    @State private var enabledMCPServerIds: Set<UUID> = []
    @State private var enabledSkillIds: Set<UUID> = []
    @State private var enabledCommandIds: Set<UUID> = []
    @State private var enabledPluginIds: Set<UUID> = []

    @StateObject private var mcpManager = MCPServerManager.shared
    @StateObject private var skillManager = SkillManager.shared
    @StateObject private var commandManager = CommandManager.shared
    @StateObject private var marketplaceManager = MarketplaceManager.shared

    @State private var selectedTab = 0

    private var isEditing: Bool { app != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit App" : "Create App")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Content with tabs
            TabView(selection: $selectedTab) {
                // Basic Info Tab
                basicInfoTab
                    .tabItem {
                        Label("Basic Info", systemImage: "info.circle")
                    }
                    .tag(0)

                // MCP Servers Tab
                mcpServersTab
                    .tabItem {
                        Label("MCP Servers", systemImage: "server.rack")
                    }
                    .tag(1)

                // Skills Tab
                skillsTab
                    .tabItem {
                        Label("Skills", systemImage: "wand.and.stars")
                    }
                    .tag(2)

                // Commands Tab
                commandsTab
                    .tabItem {
                        Label("Commands", systemImage: "terminal")
                    }
                    .tag(3)

                // Plugins Tab
                pluginsTab
                    .tabItem {
                        Label("Plugins", systemImage: "puzzlepiece.extension")
                    }
                    .tag(4)
            }
            .padding()

            Divider()

            // Footer with save button
            HStack {
                Spacer()
                Button(isEditing ? "Save Changes" : "Create App") {
                    saveApp()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .onAppear {
            if let app = app {
                name = app.name
                icon = app.icon
                description = app.description
                defaultMode = app.defaultMode
                defaultProjectPath = app.defaultProjectPath ?? ""
                maestroMCPEnabled = app.maestroMCPEnabled
                enabledMCPServerIds = app.enabledMCPServerIds
                enabledSkillIds = app.enabledSkillIds
                enabledCommandIds = app.enabledCommandIds
                enabledPluginIds = app.enabledPluginIds
            }
        }
    }

    // MARK: - Basic Info Tab

    private var basicInfoTab: some View {
        Form {
            Section("App Details") {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)

                TextField("Description", text: $description)
                    .textFieldStyle(.roundedBorder)

                // Icon picker
                HStack {
                    Text("Icon")
                    Spacer()
                    Menu {
                        ForEach(AppIconOptions.icons, id: \.self) { iconName in
                            Button {
                                icon = iconName
                            } label: {
                                Label(iconName, systemImage: iconName)
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: icon)
                                .font(.title2)
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    }
                }
            }

            Section("Default Settings") {
                Picker("Default Mode", selection: $defaultMode) {
                    ForEach(TerminalMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }

                Toggle("Enable Maestro MCP", isOn: $maestroMCPEnabled)

                HStack {
                    TextField("Default Project Path (optional)", text: $defaultProjectPath)
                        .textFieldStyle(.roundedBorder)
                    Button("Browse...") {
                        selectProjectPath()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - MCP Servers Tab

    private var mcpServersTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select MCP servers to enable with this app")
                .font(.caption)
                .foregroundColor(.secondary)

            if mcpManager.customServers.isEmpty {
                emptyStateView(
                    icon: "server.rack",
                    title: "No MCP Servers",
                    message: "Add MCP servers in the sidebar to include them in apps."
                )
            } else {
                List {
                    ForEach(mcpManager.customServers) { server in
                        Toggle(isOn: Binding(
                            get: { enabledMCPServerIds.contains(server.id) },
                            set: { enabled in
                                if enabled {
                                    enabledMCPServerIds.insert(server.id)
                                } else {
                                    enabledMCPServerIds.remove(server.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text(server.name)
                                    .font(.body)
                                Text(server.command)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Skills Tab

    private var skillsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select skills to enable with this app")
                .font(.caption)
                .foregroundColor(.secondary)

            if skillManager.installedSkills.isEmpty {
                emptyStateView(
                    icon: "wand.and.stars",
                    title: "No Skills",
                    message: "Install skills from the marketplace or create personal skills."
                )
            } else {
                List {
                    ForEach(skillManager.installedSkills) { skill in
                        Toggle(isOn: Binding(
                            get: { enabledSkillIds.contains(skill.id) },
                            set: { enabled in
                                if enabled {
                                    enabledSkillIds.insert(skill.id)
                                } else {
                                    enabledSkillIds.remove(skill.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text(skill.name)
                                    .font(.body)
                                Text(skill.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Commands Tab

    private var commandsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select commands to enable with this app")
                .font(.caption)
                .foregroundColor(.secondary)

            if commandManager.installedCommands.isEmpty {
                emptyStateView(
                    icon: "terminal",
                    title: "No Commands",
                    message: "Create commands in ~/.claude/commands/ or install from plugins."
                )
            } else {
                List {
                    ForEach(commandManager.installedCommands) { command in
                        Toggle(isOn: Binding(
                            get: { enabledCommandIds.contains(command.id) },
                            set: { enabled in
                                if enabled {
                                    enabledCommandIds.insert(command.id)
                                } else {
                                    enabledCommandIds.remove(command.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text("/\(command.commandName)")
                                    .font(.body)
                                Text(command.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Plugins Tab

    private var pluginsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select plugins to enable with this app")
                .font(.caption)
                .foregroundColor(.secondary)

            if marketplaceManager.installedPlugins.isEmpty {
                emptyStateView(
                    icon: "puzzlepiece.extension",
                    title: "No Plugins",
                    message: "Install plugins from the Skills Marketplace."
                )
            } else {
                List {
                    ForEach(marketplaceManager.installedPlugins) { plugin in
                        Toggle(isOn: Binding(
                            get: { enabledPluginIds.contains(plugin.id) },
                            set: { enabled in
                                if enabled {
                                    enabledPluginIds.insert(plugin.id)
                                } else {
                                    enabledPluginIds.remove(plugin.id)
                                }
                            }
                        )) {
                            VStack(alignment: .leading) {
                                Text(plugin.name)
                                    .font(.body)
                                Text(plugin.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helper Views

    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func selectProjectPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select default project directory"

        if panel.runModal() == .OK {
            defaultProjectPath = panel.url?.path ?? ""
        }
    }

    private func saveApp() {
        let trimmedPath = defaultProjectPath.trimmingCharacters(in: .whitespaces)

        let savedApp = AppConfig(
            id: app?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            icon: icon,
            description: description.trimmingCharacters(in: .whitespaces),
            enabledMCPServerIds: enabledMCPServerIds,
            enabledSkillIds: enabledSkillIds,
            enabledCommandIds: enabledCommandIds,
            enabledPluginIds: enabledPluginIds,
            defaultMode: defaultMode,
            defaultProjectPath: trimmedPath.isEmpty ? nil : trimmedPath,
            maestroMCPEnabled: maestroMCPEnabled,
            createdAt: app?.createdAt ?? Date(),
            lastUsed: app?.lastUsed
        )

        onSave(savedApp)
    }
}

#Preview {
    AppEditorSheet(
        app: nil,
        onSave: { _ in },
        onCancel: {}
    )
}
