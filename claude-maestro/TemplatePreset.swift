//
//  TemplatePreset.swift
//  claude-maestro
//
//  Data models for saving and loading terminal configuration presets
//

import Foundation

// MARK: - Session Configuration

struct SessionConfiguration: Codable, Identifiable, Hashable {
    let id: UUID
    var mode: TerminalMode
    var branch: String?

    init(id: UUID = UUID(), mode: TerminalMode = .claudeCode, branch: String? = nil) {
        self.id = id
        self.mode = mode
        self.branch = branch
    }
}

// MARK: - Template Preset

struct TemplatePreset: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var sessionConfigurations: [SessionConfiguration]
    var createdAt: Date
    var lastUsed: Date?

    init(id: UUID = UUID(), name: String, sessionConfigurations: [SessionConfiguration], createdAt: Date = Date(), lastUsed: Date? = nil) {
        self.id = id
        self.name = name
        self.sessionConfigurations = sessionConfigurations
        self.createdAt = createdAt
        self.lastUsed = lastUsed
    }

    var summary: String {
        let grouped = Dictionary(grouping: sessionConfigurations, by: { $0.mode })
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

    var terminalCount: Int {
        sessionConfigurations.count
    }

    // MARK: - Factory Methods

    static func allSameMode(count: Int, mode: TerminalMode) -> TemplatePreset {
        let shortName: String
        switch mode {
        case .claudeCode: shortName = "Claude"
        case .geminiCli: shortName = "Gemini"
        case .openAiCodex: shortName = "Codex"
        case .plainTerminal: shortName = "Terminal"
        }

        return TemplatePreset(
            name: "\(count) \(shortName)",
            sessionConfigurations: (0..<count).map { _ in SessionConfiguration(mode: mode) }
        )
    }

    static func mixed(claude: Int = 0, gemini: Int = 0, codex: Int = 0, plain: Int = 0) -> TemplatePreset {
        var configs: [SessionConfiguration] = []
        configs += (0..<claude).map { _ in SessionConfiguration(mode: .claudeCode) }
        configs += (0..<gemini).map { _ in SessionConfiguration(mode: .geminiCli) }
        configs += (0..<codex).map { _ in SessionConfiguration(mode: .openAiCodex) }
        configs += (0..<plain).map { _ in SessionConfiguration(mode: .plainTerminal) }

        let nameParts = [
            claude > 0 ? "\(claude) Claude" : nil,
            gemini > 0 ? "\(gemini) Gemini" : nil,
            codex > 0 ? "\(codex) Codex" : nil,
            plain > 0 ? "\(plain) Terminal" : nil
        ].compactMap { $0 }

        return TemplatePreset(
            name: nameParts.joined(separator: " + "),
            sessionConfigurations: configs
        )
    }
}

// MARK: - Quick Presets

extension TemplatePreset {
    static let quickPresets: [TemplatePreset] = [
        .allSameMode(count: 4, mode: .claudeCode),
        .allSameMode(count: 6, mode: .claudeCode),
        .mixed(claude: 3, gemini: 2, plain: 1),
        .mixed(claude: 2, gemini: 2, codex: 2),
    ]
}
