//
//  Branch.swift
//  claude-maestro
//
//  Git branch and status models
//

import Foundation

// MARK: - Branch Model

struct Branch: Identifiable, Hashable {
    let id: String
    let name: String
    let isRemote: Bool
    let isHead: Bool
    let commitHash: String
    let commitMessage: String
    let aheadCount: Int
    let behindCount: Int

    var displayName: String {
        isRemote ? name.replacingOccurrences(of: "origin/", with: "") : name
    }

    var shortCommitHash: String {
        String(commitHash.prefix(7))
    }

    init(id: String? = nil, name: String, isRemote: Bool = false, isHead: Bool = false,
         commitHash: String = "", commitMessage: String = "",
         aheadCount: Int = 0, behindCount: Int = 0) {
        self.id = id ?? name
        self.name = name
        self.isRemote = isRemote
        self.isHead = isHead
        self.commitHash = commitHash
        self.commitMessage = commitMessage
        self.aheadCount = aheadCount
        self.behindCount = behindCount
    }
}

// MARK: - Git Status

struct GitStatus {
    let isGitRepo: Bool
    let currentBranch: String?
    let hasUncommittedChanges: Bool
    let untrackedFiles: Int
    let stagedChanges: Int
    let unstagedChanges: Int

    static let notARepo = GitStatus(
        isGitRepo: false,
        currentBranch: nil,
        hasUncommittedChanges: false,
        untrackedFiles: 0,
        stagedChanges: 0,
        unstagedChanges: 0
    )

    var changesSummary: String {
        var parts: [String] = []
        if stagedChanges > 0 { parts.append("\(stagedChanges) staged") }
        if unstagedChanges > 0 { parts.append("\(unstagedChanges) modified") }
        if untrackedFiles > 0 { parts.append("\(untrackedFiles) untracked") }
        return parts.isEmpty ? "Clean" : parts.joined(separator: ", ")
    }
}

// MARK: - Git Error

enum GitError: Error, LocalizedError {
    case notAGitRepository
    case commandFailed(String)
    case branchNotFound(String)
    case branchAlreadyExists(String)
    case checkoutFailed(String)
    case worktreeAlreadyExists(String)
    case worktreeCreationFailed(String)
    case worktreeRemovalFailed(String)
    case worktreePathInvalid(String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepository:
            return "Not a git repository"
        case .commandFailed(let message):
            return "Git command failed: \(message)"
        case .branchNotFound(let name):
            return "Branch not found: \(name)"
        case .branchAlreadyExists(let name):
            return "Branch already exists: \(name)"
        case .checkoutFailed(let message):
            return "Checkout failed: \(message)"
        case .worktreeAlreadyExists(let branch):
            return "Worktree for branch '\(branch)' already exists"
        case .worktreeCreationFailed(let message):
            return "Failed to create worktree: \(message)"
        case .worktreeRemovalFailed(let message):
            return "Failed to remove worktree: \(message)"
        case .worktreePathInvalid(let path):
            return "Invalid worktree path: \(path)"
        }
    }
}
