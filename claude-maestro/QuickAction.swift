//
//  QuickAction.swift
//  claude-maestro
//
//  Data model for custom quick action buttons
//

import Foundation
import SwiftUI

/// A custom quick action that appears in the terminal footer bar
struct QuickAction: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String          // Button label
    var icon: String          // SF Symbol name
    var colorHex: String      // Color as hex for Codable
    var prompt: String        // Prompt sent to Claude
    var isEnabled: Bool
    var sortOrder: Int
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "star.fill",
        colorHex: String = "#007AFF",
        prompt: String,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.prompt = prompt
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    /// Get the SwiftUI Color from the hex string
    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: QuickAction, rhs: QuickAction) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Color Hex Extension

extension Color {
    /// Initialize a Color from a hex string (e.g., "#FF5733" or "FF5733")
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let length = hexSanitized.count
        switch length {
        case 6: // RGB (24-bit)
            self.init(
                red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x0000FF) / 255.0
            )
        case 8: // ARGB (32-bit)
            self.init(
                red: Double((rgb & 0x00FF0000) >> 16) / 255.0,
                green: Double((rgb & 0x0000FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x000000FF) / 255.0,
                opacity: Double((rgb & 0xFF000000) >> 24) / 255.0
            )
        default:
            return nil
        }
    }

    /// Convert the Color to a hex string
    func toHex() -> String {
        guard let components = NSColor(self).cgColor.components else {
            return "#007AFF"
        }

        let r = Int((components[0] * 255).rounded())
        let g = Int(((components.count > 1 ? components[1] : components[0]) * 255).rounded())
        let b = Int(((components.count > 2 ? components[2] : components[0]) * 255).rounded())

        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
