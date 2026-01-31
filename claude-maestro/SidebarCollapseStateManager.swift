//
//  SidebarCollapseStateManager.swift
//  claude-maestro
//
//  Manages collapsed/expanded state persistence for sidebar sections
//

import SwiftUI
import Combine

enum SidebarSection: String, CaseIterable {
    case sessions = "sessions"
    case mcpServers = "mcpServers"
    case pluginsAndSkills = "pluginsAndSkills"
    case quickActions = "quickActions"
}

class SidebarCollapseStateManager: ObservableObject {
    static let shared = SidebarCollapseStateManager()

    private static let preferenceKeyPrefix = "claude-maestro-sidebar-collapsed-"

    @Published private var collapsedStates: [SidebarSection: Bool] = [:]

    private init() {
        // Load saved states from UserDefaults
        for section in SidebarSection.allCases {
            let key = Self.preferenceKeyPrefix + section.rawValue
            // Default to expanded (false = not collapsed)
            let isCollapsed = UserDefaults.standard.bool(forKey: key)
            collapsedStates[section] = isCollapsed
        }
    }

    /// Check if a section is expanded (not collapsed)
    func isExpanded(_ section: SidebarSection) -> Bool {
        !(collapsedStates[section] ?? false)
    }

    /// Set the expanded state for a section
    func setExpanded(_ section: SidebarSection, expanded: Bool) {
        let isCollapsed = !expanded
        collapsedStates[section] = isCollapsed

        let key = Self.preferenceKeyPrefix + section.rawValue
        UserDefaults.standard.set(isCollapsed, forKey: key)

        objectWillChange.send()
    }

    /// Get a binding for a section's expanded state
    func binding(for section: SidebarSection) -> Binding<Bool> {
        Binding(
            get: { self.isExpanded(section) },
            set: { self.setExpanded(section, expanded: $0) }
        )
    }
}
