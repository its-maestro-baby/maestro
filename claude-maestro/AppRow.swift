//
//  AppRow.swift
//  claude-maestro
//
//  Individual app row component for the Apps sidebar
//

import SwiftUI

/// A row displaying an app configuration with launch and action buttons
struct AppRow: View {
    let app: AppConfig
    let onLaunch: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 12) {
            // App icon
            Image(systemName: app.icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)

            // Name and description
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.headline)
                    .lineLimit(1)

                if !app.description.isEmpty {
                    Text(app.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Stats row
                HStack(spacing: 8) {
                    if !app.enabledSkillIds.isEmpty {
                        StatBadge(count: app.enabledSkillIds.count, icon: "wand.and.stars", label: "skills")
                    }
                    if !app.enabledCommandIds.isEmpty {
                        StatBadge(count: app.enabledCommandIds.count, icon: "terminal", label: "commands")
                    }
                    if !app.enabledMCPServerIds.isEmpty {
                        StatBadge(count: app.enabledMCPServerIds.count, icon: "server.rack", label: "MCP")
                    }
                    if !app.enabledPluginIds.isEmpty {
                        StatBadge(count: app.enabledPluginIds.count, icon: "puzzlepiece.extension", label: "plugins")
                    }
                }
            }

            Spacer()

            // Launch button (visible on hover or always on touch devices)
            if isHovering {
                Button(action: onLaunch) {
                    Image(systemName: "play.fill")
                        .font(.body)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Launch app")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isHovering ? Color(NSColor.selectedContentBackgroundColor).opacity(0.3) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            Button(action: onLaunch) {
                Label("Launch", systemImage: "play.fill")
            }

            Divider()

            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Small badge showing a count with icon
private struct StatBadge: View {
    let count: Int
    let icon: String
    let label: String

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text("\(count)")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.secondary)
        .help("\(count) \(label)")
    }
}

#Preview {
    VStack(spacing: 0) {
        AppRow(
            app: AppConfig(
                name: "Full Stack Dev",
                icon: "hammer.fill",
                description: "Complete development environment",
                enabledMCPServerIds: [UUID()],
                enabledSkillIds: [UUID(), UUID()],
                enabledCommandIds: [UUID()],
                enabledPluginIds: []
            ),
            onLaunch: {},
            onEdit: {},
            onDelete: {}
        )
        AppRow(
            app: AppConfig(
                name: "API Testing",
                icon: "network",
                description: "Test REST APIs"
            ),
            onLaunch: {},
            onEdit: {},
            onDelete: {}
        )
    }
    .frame(width: 300)
    .padding()
}
