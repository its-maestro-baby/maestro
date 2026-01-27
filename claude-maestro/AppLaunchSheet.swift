//
//  AppLaunchSheet.swift
//  claude-maestro
//
//  Session selection dialog when launching an app
//

import SwiftUI

/// Sheet for selecting which session to launch an app in
struct AppLaunchSheet: View {
    let app: AppConfig
    let sessions: [SessionInfo]
    let onLaunch: (Int) -> Void
    let onCancel: () -> Void

    @State private var selectedSessionId: Int?
    @State private var createNewSession = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: app.icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)

                Text("Launch \(app.name)")
                    .font(.headline)

                Spacer()

                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
            }
            .padding()

            Divider()

            // Session selection
            VStack(alignment: .leading, spacing: 16) {
                Text("Select a session to apply this app configuration:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // New session option
                SessionSelectionRow(
                    icon: "plus.circle.fill",
                    title: "New Session",
                    subtitle: "Create a new session with this app's configuration",
                    isSelected: createNewSession,
                    onSelect: {
                        createNewSession = true
                        selectedSessionId = nil
                    }
                )

                if !sessions.isEmpty {
                    Divider()

                    Text("Or apply to an existing session:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(sessions, id: \.id) { session in
                                SessionSelectionRow(
                                    icon: session.mode.icon,
                                    iconColor: session.mode.color,
                                    title: "Session #\(session.id)",
                                    subtitle: sessionSubtitle(for: session),
                                    isSelected: selectedSessionId == session.id && !createNewSession,
                                    onSelect: {
                                        selectedSessionId = session.id
                                        createNewSession = false
                                    }
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                }
            }
            .padding()

            Divider()

            // Footer
            HStack {
                // App info summary
                VStack(alignment: .leading, spacing: 4) {
                    Text("This will configure:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 12) {
                        if !app.enabledSkillIds.isEmpty {
                            Label("\(app.enabledSkillIds.count) skills", systemImage: "wand.and.stars")
                        }
                        if !app.enabledCommandIds.isEmpty {
                            Label("\(app.enabledCommandIds.count) commands", systemImage: "terminal")
                        }
                        if !app.enabledMCPServerIds.isEmpty {
                            Label("\(app.enabledMCPServerIds.count) MCP", systemImage: "server.rack")
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }

                Spacer()

                Button("Launch") {
                    if createNewSession {
                        // Signal to create new session (using -1 as indicator)
                        onLaunch(-1)
                    } else if let sessionId = selectedSessionId {
                        onLaunch(sessionId)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!createNewSession && selectedSessionId == nil)
            }
            .padding()
        }
        .frame(width: 450, height: 420)
        .onAppear {
            // Default to new session if no sessions exist
            if sessions.isEmpty {
                createNewSession = true
            }
        }
    }

    private func sessionSubtitle(for session: SessionInfo) -> String {
        var parts: [String] = []

        parts.append(session.mode.rawValue)

        if let branch = session.assignedBranch {
            parts.append("on \(branch)")
        }

        if session.isTerminalLaunched {
            parts.append("(\(session.status.label))")
        } else {
            parts.append("(not started)")
        }

        return parts.joined(separator: " ")
    }
}

/// Individual session row for selection
private struct SessionSelectionRow: View {
    let icon: String
    var iconColor: Color = .accentColor
    let title: String
    let subtitle: String
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovering ? Color(NSColor.selectedContentBackgroundColor).opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    AppLaunchSheet(
        app: AppConfig(
            name: "Full Stack Dev",
            icon: "hammer.fill",
            description: "Complete development environment",
            enabledMCPServerIds: [UUID()],
            enabledSkillIds: [UUID(), UUID()],
            enabledCommandIds: [UUID()]
        ),
        sessions: [
            SessionInfo(id: 1, mode: .claudeCode),
            SessionInfo(id: 2, mode: .geminiCli)
        ],
        onLaunch: { _ in },
        onCancel: {}
    )
}
