//
//  ModePicker.swift
//  claude-maestro
//
//  Direct mode selection component - replaces cycling through modes
//

import SwiftUI

// MARK: - Compact Mode Picker (Menu-based dropdown)

struct CompactModePicker: View {
    @Binding var selectedMode: TerminalMode
    var isDisabled: Bool = false

    var body: some View {
        Menu {
            ForEach(TerminalMode.allCases, id: \.self) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    Label(mode.rawValue, systemImage: mode.icon)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedMode.icon)
                    .foregroundColor(selectedMode.color)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(selectedMode.color.opacity(0.1))
            )
        }
        .menuStyle(.borderlessButton)
        .disabled(isDisabled)
        .help(isDisabled ? "Cannot change mode after launch" : "Select terminal mode")
    }
}

// MARK: - Full Mode Picker (Horizontal buttons)

struct FullModePicker: View {
    @Binding var selectedMode: TerminalMode
    var isDisabled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TerminalMode.allCases, id: \.self) { mode in
                ModeButton(
                    mode: mode,
                    isSelected: selectedMode == mode,
                    isDisabled: isDisabled
                ) {
                    selectedMode = mode
                }
            }
        }
    }
}

// MARK: - Mode Button

struct ModeButton: View {
    let mode: TerminalMode
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    private var shortLabel: String {
        switch mode {
        case .claudeCode: return "Claude"
        case .geminiCli: return "Gemini"
        case .openAiCodex: return "Codex"
        case .plainTerminal: return "Terminal"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: mode.icon)
                    .font(.caption)
                Text(shortLabel)
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? mode.color.opacity(0.3) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? mode.color : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .foregroundColor(isSelected ? mode.color : .secondary)
        .help(mode.rawValue)
    }
}

// MARK: - Mode Icon Button (Minimal - just icon with menu)

struct ModeIconButton: View {
    @Binding var selectedMode: TerminalMode
    var isDisabled: Bool = false
    var size: CGFloat = 20

    var body: some View {
        Menu {
            ForEach(TerminalMode.allCases, id: \.self) { mode in
                Button {
                    selectedMode = mode
                } label: {
                    HStack {
                        Image(systemName: mode.icon)
                        Text(mode.rawValue)
                        if selectedMode == mode {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: selectedMode.icon)
                .foregroundColor(selectedMode.color)
                .frame(width: size, height: size)
        }
        .menuStyle(.borderlessButton)
        .disabled(isDisabled)
        .help(selectedMode.rawValue)
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Compact Mode Picker")
        CompactModePicker(selectedMode: .constant(.claudeCode))

        Text("Full Mode Picker")
        FullModePicker(selectedMode: .constant(.geminiCli))

        Text("Mode Icon Button")
        ModeIconButton(selectedMode: .constant(.openAiCodex))
    }
    .padding()
}
