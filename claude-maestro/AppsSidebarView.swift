//
//  AppsSidebarView.swift
//  claude-maestro
//
//  Right sidebar view displaying saved apps
//

import SwiftUI

/// Right sidebar showing saved app configurations
struct AppsSidebarView: View {
    @ObservedObject var appManager: AppManager
    @ObservedObject var sessionManager: SessionManager
    let onLaunchApp: (AppConfig, Int) -> Void

    @State private var showingAppEditor = false
    @State private var showingLaunchSheet = false
    @State private var editingApp: AppConfig?
    @State private var appToLaunch: AppConfig?
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Apps")
                    .font(.headline)

                Spacer()

                Button {
                    editingApp = nil
                    showingAppEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Create new app")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Search field (only show if there are apps)
            if !appManager.apps.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search apps...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // Apps list or empty state
            if appManager.apps.isEmpty {
                EmptyAppsView(onCreateApp: {
                    editingApp = nil
                    showingAppEditor = true
                })
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredApps) { app in
                            AppRow(
                                app: app,
                                onLaunch: {
                                    appToLaunch = app
                                    showingLaunchSheet = true
                                },
                                onEdit: {
                                    editingApp = app
                                    showingAppEditor = true
                                },
                                onDelete: {
                                    appManager.deleteApp(id: app.id)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingAppEditor) {
            AppEditorSheet(
                app: editingApp,
                onSave: { app in
                    if editingApp != nil {
                        appManager.updateApp(app)
                    } else {
                        appManager.addApp(app)
                    }
                    showingAppEditor = false
                },
                onCancel: {
                    showingAppEditor = false
                }
            )
        }
        .sheet(isPresented: $showingLaunchSheet) {
            if let app = appToLaunch {
                AppLaunchSheet(
                    app: app,
                    sessions: sessionManager.sessions,
                    onLaunch: { sessionId in
                        onLaunchApp(app, sessionId)
                        showingLaunchSheet = false
                    },
                    onCancel: {
                        showingLaunchSheet = false
                    }
                )
            }
        }
    }

    private var filteredApps: [AppConfig] {
        if searchText.isEmpty {
            return appManager.sortedApps
        }
        return appManager.sortedApps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }
}

/// Empty state view when no apps exist
private struct EmptyAppsView: View {
    let onCreateApp: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No Apps Yet")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Create an app to save a bundle of MCP servers, skills, and commands for quick launching.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onCreateApp) {
                Label("Create App", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AppsSidebarView(
        appManager: AppManager.shared,
        sessionManager: SessionManager(),
        onLaunchApp: { _, _ in }
    )
}
