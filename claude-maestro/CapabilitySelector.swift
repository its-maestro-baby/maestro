//
//  CapabilitySelector.swift
//  claude-maestro
//
//  Combined skills and commands selector with popover UI
//

import SwiftUI

struct CapabilitySelector: View {
    let sessionId: Int
    @ObservedObject var skillManager: SkillManager
    @ObservedObject var commandManager: CommandManager
    var isDisabled: Bool = false

    @State private var showPopover = false
    @State private var searchText = ""

    private var sessionSkillConfig: SessionSkillConfig {
        skillManager.getSkillConfig(for: sessionId)
    }

    private var sessionCommandConfig: SessionCommandConfig {
        commandManager.getCommandConfig(for: sessionId)
    }

    /// Count of enabled skills for this session
    private var enabledSkillCount: Int {
        skillManager.installedSkills.filter { skill in
            sessionSkillConfig.isSkillEnabled(skill.id)
        }.count
    }

    /// Count of enabled commands for this session
    private var enabledCommandCount: Int {
        commandManager.installedCommands.filter { command in
            sessionCommandConfig.isCommandEnabled(command.id)
        }.count
    }

    /// Total enabled count
    private var totalEnabledCount: Int {
        enabledSkillCount + enabledCommandCount
    }

    /// Filtered skills based on search
    private var filteredSkills: [SkillConfig] {
        if searchText.isEmpty {
            return skillManager.installedSkills
        }
        let lowercased = searchText.lowercased()
        return skillManager.installedSkills.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.description.lowercased().contains(lowercased) ||
            $0.commandName.lowercased().contains(lowercased)
        }
    }

    /// Filtered commands based on search
    private var filteredCommands: [CommandConfig] {
        if searchText.isEmpty {
            return commandManager.installedCommands
        }
        let lowercased = searchText.lowercased()
        return commandManager.installedCommands.filter {
            $0.name.lowercased().contains(lowercased) ||
            $0.description.lowercased().contains(lowercased) ||
            $0.commandName.lowercased().contains(lowercased)
        }
    }

    /// Unified plugin bundles containing both skills and commands
    private var pluginBundles: [(pluginName: String, skills: [SkillConfig], commands: [CommandConfig])] {
        var plugins = Set<String>()
        for skill in filteredSkills {
            if let name = skill.source.pluginName { plugins.insert(name) }
        }
        for command in filteredCommands {
            if let name = command.source.pluginName { plugins.insert(name) }
        }

        return plugins.sorted().map { pluginName in
            let skills = filteredSkills.filter { $0.source.pluginName == pluginName }
            let commands = filteredCommands.filter { $0.source.pluginName == pluginName }
            return (pluginName: pluginName, skills: skills, commands: commands)
        }
    }

    /// Non-plugin skills (shown individually)
    private var nonPluginSkills: [SkillConfig] {
        filteredSkills.filter { $0.source.pluginName == nil }
    }

    /// Non-plugin commands (shown individually)
    private var nonPluginCommands: [CommandConfig] {
        filteredCommands.filter { $0.source.pluginName == nil }
    }

    /// List of enabled skill names for tooltip
    private var enabledSkillNames: [String] {
        skillManager.installedSkills
            .filter { sessionSkillConfig.isSkillEnabled($0.id) }
            .map { "/\($0.commandName)" }
    }

    /// List of enabled command names for tooltip
    private var enabledCommandNames: [String] {
        commandManager.installedCommands
            .filter { sessionCommandConfig.isCommandEnabled($0.id) }
            .map { "/\($0.commandName)" }
    }

    var body: some View {
        Group {
            if isDisabled {
                // Post-launch: Read-only badge
                readOnlyBadge
            } else {
                // Pre-launch: Interactive popover
                interactiveButton
            }
        }
        .onAppear {
            // Initialize session configs with defaults if needed
            skillManager.initializeSessionConfig(for: sessionId)
            commandManager.initializeSessionConfig(for: sessionId)
        }
    }

    // MARK: - Read-Only Badge (Post-Launch)

    private var readOnlyBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
            Text("\(totalEnabledCount) Active")
        }
        .font(.caption2)
        .foregroundColor(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(6)
        .help(tooltipText)
    }

    private var tooltipText: String {
        let all = enabledSkillNames + enabledCommandNames
        if all.isEmpty {
            return "No skills or commands enabled"
        }
        return all.joined(separator: ", ")
    }

    // MARK: - Interactive Button with Popover (Pre-Launch)

    private var interactiveButton: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("\(totalEnabledCount)")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            popoverContent
        }
    }

    // MARK: - Popover Content

    private var popoverContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search skills & commands...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Plugins section
                    if !pluginBundles.isEmpty {
                        SectionHeader(title: "Plugins", count: pluginBundles.count, total: pluginBundles.count)
                        ForEach(pluginBundles, id: \.pluginName) { bundle in
                            PluginToggleRow(
                                pluginName: bundle.pluginName,
                                skills: bundle.skills,
                                commands: bundle.commands,
                                enabledSkillIds: sessionSkillConfig.enabledSkillIds,
                                enabledCommandIds: sessionCommandConfig.enabledCommandIds,
                                onToggleAll: { enabled in
                                    for skill in bundle.skills {
                                        skillManager.setSkillEnabled(skill.id, enabled: enabled, for: sessionId)
                                    }
                                    for command in bundle.commands {
                                        commandManager.setCommandEnabled(command.id, enabled: enabled, for: sessionId)
                                    }
                                }
                            )
                        }
                    }

                    // Skills section (non-plugin only)
                    if !nonPluginSkills.isEmpty {
                        if !pluginBundles.isEmpty {
                            Divider()
                                .padding(.vertical, 4)
                        }
                        SectionHeader(title: "Skills", count: nonPluginSkills.filter { sessionSkillConfig.isSkillEnabled($0.id) }.count, total: nonPluginSkills.count)
                        ForEach(nonPluginSkills) { skill in
                            SkillToggleRow(
                                skill: skill,
                                isEnabled: sessionSkillConfig.isSkillEnabled(skill.id),
                                onToggle: { enabled in
                                    skillManager.setSkillEnabled(skill.id, enabled: enabled, for: sessionId)
                                }
                            )
                        }
                    }

                    // Commands section (non-plugin only)
                    if !nonPluginCommands.isEmpty {
                        if !pluginBundles.isEmpty || !nonPluginSkills.isEmpty {
                            Divider()
                                .padding(.vertical, 4)
                        }
                        SectionHeader(title: "Commands", count: nonPluginCommands.filter { sessionCommandConfig.isCommandEnabled($0.id) }.count, total: nonPluginCommands.count)
                        ForEach(nonPluginCommands) { command in
                            CommandToggleRow(
                                command: command,
                                isEnabled: sessionCommandConfig.isCommandEnabled(command.id),
                                onToggle: { enabled in
                                    commandManager.setCommandEnabled(command.id, enabled: enabled, for: sessionId)
                                }
                            )
                        }
                    }

                    // Empty state
                    if filteredSkills.isEmpty && filteredCommands.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundColor(.secondary)
                            Text(searchText.isEmpty ? "No skills or commands installed" : "No matches found")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 350)

            Divider()

            // Footer with rescan button
            HStack {
                Button {
                    skillManager.scanForSkills()
                    commandManager.scanForCommands()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Text("\(skillManager.installedSkills.count) skills, \(commandManager.installedCommands.count) commands")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
        .frame(width: 300)
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let title: String
    let count: Int
    let total: Int

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Spacer()
            Text("\(count)/\(total)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Skill Toggle Row

private struct SkillToggleRow: View {
    let skill: SkillConfig
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isEnabled)
        } label: {
            HStack(spacing: 8) {
                // Checkbox
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isEnabled ? .orange : .secondary)

                // Icon
                Image(systemName: skill.source.icon)
                    .foregroundColor(.orange)
                    .font(.caption)
                    .frame(width: 16)

                // Info
                VStack(alignment: .leading, spacing: 1) {
                    Text("/\(skill.commandName)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Source badge
                Text(skill.source.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isEnabled ? Color.orange.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plugin Toggle Row

private struct PluginToggleRow: View {
    let pluginName: String
    let skills: [SkillConfig]
    let commands: [CommandConfig]
    let enabledSkillIds: Set<UUID>
    let enabledCommandIds: Set<UUID>
    let onToggleAll: (Bool) -> Void

    private var totalCount: Int {
        skills.count + commands.count
    }

    private var enabledCount: Int {
        let enabledSkills = skills.filter { enabledSkillIds.contains($0.id) }.count
        let enabledCommands = commands.filter { enabledCommandIds.contains($0.id) }.count
        return enabledSkills + enabledCommands
    }

    private var checkboxState: CheckboxState {
        if enabledCount == 0 {
            return .none
        } else if enabledCount == totalCount {
            return .all
        } else {
            return .partial
        }
    }

    private enum CheckboxState {
        case none, partial, all

        var icon: String {
            switch self {
            case .none: return "circle"
            case .partial: return "minus.circle.fill"
            case .all: return "checkmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .none: return .secondary
            case .partial, .all: return .purple
            }
        }
    }

    private var countBadgeText: String {
        var parts: [String] = []
        if !skills.isEmpty {
            parts.append("\(skills.count) skill\(skills.count == 1 ? "" : "s")")
        }
        if !commands.isEmpty {
            parts.append("\(commands.count) command\(commands.count == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button {
            let shouldEnable = checkboxState != .all
            onToggleAll(shouldEnable)
        } label: {
            HStack(spacing: 8) {
                // Checkbox
                Image(systemName: checkboxState.icon)
                    .foregroundColor(checkboxState.color)

                // Plugin icon
                Image(systemName: "puzzlepiece.extension")
                    .foregroundColor(.purple)
                    .font(.caption)
                    .frame(width: 16)

                // Plugin name
                Text(pluginName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Spacer()

                // Count badge
                Text(countBadgeText)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(enabledCount > 0 ? Color.purple.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Command Toggle Row

private struct CommandToggleRow: View {
    let command: CommandConfig
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isEnabled)
        } label: {
            HStack(spacing: 8) {
                // Checkbox
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isEnabled ? .blue : .secondary)

                // Icon
                Image(systemName: command.source.icon)
                    .foregroundColor(.blue)
                    .font(.caption)
                    .frame(width: 16)

                // Info
                VStack(alignment: .leading, spacing: 1) {
                    Text("/\(command.commandName)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    if !command.description.isEmpty {
                        Text(command.description)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Source badge
                Text(command.source.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(3)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isEnabled ? Color.blue.opacity(0.05) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HStack {
        CapabilitySelector(
            sessionId: 1,
            skillManager: SkillManager.shared,
            commandManager: CommandManager.shared,
            isDisabled: false
        )
        CapabilitySelector(
            sessionId: 1,
            skillManager: SkillManager.shared,
            commandManager: CommandManager.shared,
            isDisabled: true
        )
    }
    .padding()
}
