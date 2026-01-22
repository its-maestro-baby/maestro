//
//  PresetSelector.swift
//  claude-maestro
//
//  UI for selecting and managing terminal configuration presets
//

import SwiftUI

// MARK: - Preset Selector

struct PresetSelector: View {
    @ObservedObject var manager: SessionManager
    @State private var showSaveSheet = false
    @State private var newPresetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Presets")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Quick presets grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                ForEach(TemplatePreset.quickPresets) { preset in
                    QuickPresetButton(
                        preset: preset,
                        isSelected: manager.currentPresetId == preset.id
                    ) {
                        manager.applyPreset(preset)
                    }
                }
            }

            // Saved presets (if any)
            if !manager.savedPresets.isEmpty {
                Divider()
                    .padding(.vertical, 4)

                Text("Saved")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(manager.savedPresets) { preset in
                    SavedPresetRow(preset: preset, manager: manager)
                }
            }

            Divider()
                .padding(.vertical, 4)

            // Save current button
            Button {
                newPresetName = generateDefaultName()
                showSaveSheet = true
            } label: {
                Label("Save Current...", systemImage: "square.and.arrow.down")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(manager.isRunning)
        }
        .padding(.horizontal)
        .sheet(isPresented: $showSaveSheet) {
            SavePresetSheet(
                manager: manager,
                presetName: $newPresetName,
                onSave: { name in
                    _ = manager.saveCurrentAsPreset(name: name)
                    showSaveSheet = false
                    newPresetName = ""
                },
                onCancel: {
                    showSaveSheet = false
                    newPresetName = ""
                }
            )
        }
    }

    private func generateDefaultName() -> String {
        let grouped = Dictionary(grouping: manager.sessions, by: { $0.mode })
        let parts = TerminalMode.allCases.compactMap { mode -> String? in
            guard let sessions = grouped[mode], !sessions.isEmpty else { return nil }
            let shortName: String
            switch mode {
            case .claudeCode: shortName = "Claude"
            case .geminiCli: shortName = "Gemini"
            case .openAiCodex: shortName = "Codex"
            case .plainTerminal: shortName = "Terminal"
            }
            return "\(sessions.count) \(shortName)"
        }
        return parts.joined(separator: " + ")
    }
}

// MARK: - Quick Preset Button

struct QuickPresetButton: View {
    let preset: TemplatePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(preset.terminalCount) sessions")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(NSColor.windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(preset.summary)
    }
}

// MARK: - Saved Preset Row

struct SavedPresetRow: View {
    let preset: TemplatePreset
    @ObservedObject var manager: SessionManager
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                manager.applyPreset(preset)
            } label: {
                HStack {
                    Text(preset.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text("\(preset.terminalCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.gray.opacity(0.2)))
                }
            }
            .buttonStyle(.plain)

            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help("Delete preset")
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(manager.currentPresetId == preset.id ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .confirmationDialog("Delete preset '\(preset.name)'?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                manager.deletePreset(preset)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Save Preset Sheet

struct SavePresetSheet: View {
    @ObservedObject var manager: SessionManager
    @Binding var presetName: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Save Configuration")
                .font(.headline)

            TextField("Preset name", text: $presetName)
                .textFieldStyle(.roundedBorder)

            // Preview
            VStack(alignment: .leading, spacing: 4) {
                Text("Configuration:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                let grouped = Dictionary(grouping: manager.sessions, by: { $0.mode })
                ForEach(TerminalMode.allCases, id: \.self) { mode in
                    if let sessions = grouped[mode], !sessions.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .foregroundColor(mode.color)
                                .frame(width: 16)
                            Text("\(sessions.count) \(mode.rawValue)")
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(6)

            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])

                Button("Save") {
                    onSave(presetName)
                }
                .buttonStyle(.borderedProminent)
                .disabled(presetName.isEmpty)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding()
        .frame(width: 280)
    }
}

#Preview {
    PresetSelector(manager: SessionManager())
        .frame(width: 220)
        .padding()
}
