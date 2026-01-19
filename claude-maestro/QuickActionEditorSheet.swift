//
//  QuickActionEditorSheet.swift
//  claude-maestro
//
//  Sheet modal for creating and editing quick actions
//

import SwiftUI

struct QuickActionEditorSheet: View {
    let action: QuickAction?  // nil for new action
    let onSave: (QuickAction) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var icon: String = "star.fill"
    @State private var selectedColor: Color = .blue
    @State private var prompt: String = ""

    // Common SF Symbols for quick actions
    private let commonIcons = [
        "star.fill", "bolt.fill", "wand.and.stars", "sparkles",
        "play.fill", "arrow.clockwise", "checkmark.circle.fill", "xmark.circle.fill",
        "doc.fill", "folder.fill", "trash.fill", "pencil",
        "gear", "wrench.fill", "hammer.fill", "scissors",
        "flag.fill", "bookmark.fill", "tag.fill", "heart.fill",
        "bell.fill", "envelope.fill", "paperplane.fill", "bubble.left.fill",
        "terminal.fill", "chevron.left.forwardslash.chevron.right", "curlybraces", "function",
        "arrow.up.circle.fill", "arrow.down.circle.fill", "arrow.triangle.branch", "git.branch"
    ]

    // Preset colors
    private let presetColors: [Color] = [
        .blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo, .mint, .gray
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(action == nil ? "New Quick Action" : "Edit Quick Action")
                    .font(.headline)
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Button label", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Icon picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Icon")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(36)), count: 8), spacing: 8) {
                            ForEach(commonIcons, id: \.self) { iconName in
                                Button {
                                    icon = iconName
                                } label: {
                                    Image(systemName: iconName)
                                        .font(.system(size: 16))
                                        .frame(width: 32, height: 32)
                                        .background(icon == iconName ? selectedColor.opacity(0.2) : Color.clear)
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(icon == iconName ? selectedColor : Color.clear, lineWidth: 2)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Color picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Color")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack(spacing: 8) {
                            ForEach(presetColors, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                } label: {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: selectedColor == color ? 2 : 0)
                                        )
                                        .shadow(color: selectedColor == color ? color.opacity(0.5) : .clear, radius: 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Prompt field
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Prompt")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextEditor(text: $prompt)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 100)
                            .padding(4)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        Text("This prompt will be sent to Claude when the button is clicked")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Live preview
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preview")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        HStack {
                            Button {
                                // Preview only - no action
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: icon)
                                    Text(name.isEmpty ? "Button" : name)
                                }
                                .font(.caption2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(selectedColor)

                            Spacer()
                        }
                        .padding(8)
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }

            Divider()

            // Footer with save button
            HStack {
                Spacer()
                Button("Save") {
                    saveAction()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || prompt.isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 420, height: 520)
        .onAppear {
            if let existing = action {
                name = existing.name
                icon = existing.icon
                selectedColor = existing.color
                prompt = existing.prompt
            }
        }
    }

    private func saveAction() {
        let newAction = QuickAction(
            id: action?.id ?? UUID(),
            name: name,
            icon: icon,
            colorHex: selectedColor.toHex(),
            prompt: prompt,
            isEnabled: action?.isEnabled ?? true,
            sortOrder: action?.sortOrder ?? 0,
            createdAt: action?.createdAt ?? Date()
        )
        onSave(newAction)
    }
}

#Preview {
    QuickActionEditorSheet(
        action: nil,
        onSave: { _ in },
        onCancel: { }
    )
}
