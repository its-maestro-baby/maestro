//
//  AppManager.swift
//  claude-maestro
//
//  Manages app configurations - CRUD operations, persistence, and session associations
//

import Foundation
import Combine

/// Manages saved app configurations and their association with sessions
@MainActor
class AppManager: ObservableObject {
    static let shared = AppManager()

    // Saved apps
    @Published var apps: [AppConfig] = []

    // Session-app associations (sessionId -> appId)
    @Published var sessionAppAssociations: [Int: UUID] = [:]

    private let appsKey = "claude-maestro-apps"
    private let sessionAssociationsKey = "claude-maestro-session-app-associations"

    private init() {
        loadApps()
        loadSessionAssociations()
    }

    // MARK: - App CRUD Operations

    /// Add a new app configuration
    func addApp(_ app: AppConfig) {
        apps.append(app)
        persistApps()
    }

    /// Update an existing app configuration
    func updateApp(_ app: AppConfig) {
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index] = app
            persistApps()
        }
    }

    /// Delete an app configuration
    func deleteApp(id: UUID) {
        apps.removeAll { $0.id == id }
        // Remove from session associations
        sessionAppAssociations = sessionAppAssociations.filter { $0.value != id }
        persistApps()
        persistSessionAssociations()
    }

    /// Get an app by ID
    func getApp(id: UUID) -> AppConfig? {
        apps.first { $0.id == id }
    }

    /// Mark an app as recently used
    func markAppUsed(_ appId: UUID) {
        if let index = apps.firstIndex(where: { $0.id == appId }) {
            apps[index].lastUsed = Date()
            persistApps()
        }
    }

    // MARK: - Session Association

    /// Associate an app with a session
    func associateApp(_ appId: UUID, with sessionId: Int) {
        sessionAppAssociations[sessionId] = appId
        markAppUsed(appId)
        persistSessionAssociations()
    }

    /// Remove app association from a session
    func removeAppAssociation(for sessionId: Int) {
        sessionAppAssociations.removeValue(forKey: sessionId)
        persistSessionAssociations()
    }

    /// Get the app associated with a session
    func getAssociatedApp(for sessionId: Int) -> AppConfig? {
        guard let appId = sessionAppAssociations[sessionId] else { return nil }
        return getApp(id: appId)
    }

    /// Check if a session has an associated app
    func hasAssociatedApp(for sessionId: Int) -> Bool {
        sessionAppAssociations[sessionId] != nil
    }

    // MARK: - Sorting

    /// Get apps sorted by last used (most recent first), then by name
    var sortedApps: [AppConfig] {
        apps.sorted { app1, app2 in
            // Compare by last used date (most recent first)
            if let date1 = app1.lastUsed, let date2 = app2.lastUsed {
                return date1 > date2
            }
            // Apps with lastUsed come before those without
            if app1.lastUsed != nil && app2.lastUsed == nil {
                return true
            }
            if app1.lastUsed == nil && app2.lastUsed != nil {
                return false
            }
            // Fall back to name comparison
            return app1.name.localizedCaseInsensitiveCompare(app2.name) == .orderedAscending
        }
    }

    // MARK: - Persistence

    private func persistApps() {
        if let encoded = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(encoded, forKey: appsKey)
        }
    }

    private func loadApps() {
        if let data = UserDefaults.standard.data(forKey: appsKey),
           let decoded = try? JSONDecoder().decode([AppConfig].self, from: data) {
            apps = decoded
        }
    }

    private func persistSessionAssociations() {
        if let encoded = try? JSONEncoder().encode(sessionAppAssociations) {
            UserDefaults.standard.set(encoded, forKey: sessionAssociationsKey)
        }
    }

    private func loadSessionAssociations() {
        if let data = UserDefaults.standard.data(forKey: sessionAssociationsKey),
           let decoded = try? JSONDecoder().decode([Int: UUID].self, from: data) {
            sessionAppAssociations = decoded
        }
    }
}
