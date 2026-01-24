//
//  CommitGraph.swift
//  claude-maestro
//
//  Data models for git commit graph visualization
//

import SwiftUI
import Combine

// MARK: - Commit Model

struct Commit: Identifiable, Hashable {
    let id: String              // Full SHA
    let shortHash: String       // First 7 characters
    let message: String         // Commit message (first line)
    let author: String
    let authorEmail: String
    let date: Date
    let parentHashes: [String]  // Parent commit SHAs
    let isHead: Bool            // Is this HEAD?
    let refs: [GitRef]          // Branch/tag refs pointing to this commit
    let insertions: Int?        // Lines added (nil if not available)
    let deletions: Int?         // Lines removed (nil if not available)

    var isMergeCommit: Bool {
        parentHashes.count > 1
    }

    var isRootCommit: Bool {
        parentHashes.isEmpty
    }
}

// MARK: - Commit File Model

struct CommitFile: Identifiable {
    var id: String { path }
    let path: String
    let status: FileChangeStatus

    enum FileChangeStatus: String {
        case added = "A"
        case modified = "M"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case unknown = "?"

        var icon: String {
            switch self {
            case .added: return "plus.circle.fill"
            case .modified: return "pencil.circle.fill"
            case .deleted: return "minus.circle.fill"
            case .renamed: return "arrow.right.circle.fill"
            case .copied: return "doc.on.doc.fill"
            case .unknown: return "questionmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .added: return .green
            case .modified: return .orange
            case .deleted: return .red
            case .renamed: return .blue
            case .copied: return .purple
            case .unknown: return .gray
            }
        }
    }
}

// MARK: - Git Reference Model

struct GitRef: Identifiable, Hashable {
    let id: String
    let name: String
    let type: RefType
    let isHead: Bool            // Is this the current HEAD branch?

    enum RefType: String, Codable, Hashable {
        case localBranch
        case remoteBranch
        case tag
    }

    var displayName: String {
        switch type {
        case .remoteBranch:
            // Remove "origin/" prefix for display
            if name.hasPrefix("origin/") {
                return String(name.dropFirst(7))
            }
            return name
        default:
            return name
        }
    }
}

// MARK: - Graph Node Model

struct GraphNode: Identifiable {
    let id: String              // Same as commit hash
    let commit: Commit
    let column: Int             // Which rail/column (0-indexed from left)
    let row: Int                // Vertical position (0 = most recent)
    let parentConnections: [ParentConnection]

    var railColor: Color {
        GraphLayoutEngine.railColors[column % GraphLayoutEngine.railColors.count]
    }
}

// MARK: - Parent Connection Model

struct ParentConnection: Hashable {
    let parentHash: String
    let parentColumn: Int
    let parentRow: Int
    let connectionType: ConnectionType
    let isOffScreen: Bool   // Parent exists but is outside loaded commit range

    enum ConnectionType: Hashable {
        case straight       // Same column, direct line down
        case mergeLeft      // Merge line curving left
        case mergeRight     // Merge line curving right
    }
}

// MARK: - Rail Model

struct Rail: Identifiable {
    let id: Int                 // Column index
    let color: Color            // Assigned color for this rail
}

// MARK: - Commit Graph Data (Observable)

@MainActor
class CommitGraphData: ObservableObject {
    @Published var nodes: [GraphNode] = []
    @Published var rails: [Rail] = []
    @Published var commits: [Commit] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var hasMoreCommits: Bool = true
    @Published var error: GitError?

    // Quick lookup dictionaries
    var nodesByHash: [String: GraphNode] = [:]
    var commitsByHash: [String: Commit] = [:]

    func update(commits: [Commit], nodes: [GraphNode], rails: [Rail]) {
        self.commits = commits
        self.nodes = nodes
        self.rails = rails
        self.nodesByHash = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        self.commitsByHash = Dictionary(uniqueKeysWithValues: commits.map { ($0.id, $0) })
    }

    func appendCommits(_ newCommits: [Commit], nodes: [GraphNode], rails: [Rail]) {
        // Only append commits that don't already exist
        let existingHashes = Set(commits.map { $0.id })
        let uniqueNewCommits = newCommits.filter { !existingHashes.contains($0.id) }
        self.commits.append(contentsOf: uniqueNewCommits)
        self.nodes = nodes
        self.rails = rails
        self.nodesByHash = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        self.commitsByHash = Dictionary(uniqueKeysWithValues: commits.map { ($0.id, $0) })
    }

    func clear() {
        commits = []
        nodes = []
        rails = []
        nodesByHash = [:]
        commitsByHash = [:]
        error = nil
        hasMoreCommits = true
    }
}

// MARK: - Date Extension

extension Date {
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Array Safe Subscript

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
