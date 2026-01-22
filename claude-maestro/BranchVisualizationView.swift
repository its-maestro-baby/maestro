//
//  BranchVisualizationView.swift
//  claude-maestro
//
//  Visual representation of git branches
//

import SwiftUI
import AppKit

struct BranchVisualizationView: View {
    @ObservedObject var gitManager: GitManager
    let activeSessionBranches: [String: Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "arrow.triangle.branch")
                Text("Branches")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await gitManager.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(gitManager.isLoading)
            }

            Divider()

            if gitManager.isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding()
            } else if !gitManager.isGitRepo {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Not a git repository")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                // Current branch highlight
                if let current = gitManager.currentBranch {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                            .font(.caption)
                        Text("Current: \(current)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(6)
                }

                // Git status summary
                if gitManager.gitStatus.hasUncommittedChanges {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(gitManager.gitStatus.changesSummary)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }

                Divider()

                // Branch list
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        // Local branches section
                        if !gitManager.localBranches.isEmpty {
                            Text("Local")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)

                            ForEach(gitManager.localBranches) { branch in
                                BranchRowView(
                                    branch: branch,
                                    isCurrentBranch: branch.isHead,
                                    activeSession: activeSessionBranches[branch.name]
                                )
                            }
                        }

                        // Remote branches section
                        if !gitManager.remoteBranches.isEmpty {
                            Text("Remote")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)

                            ForEach(gitManager.remoteBranches) { branch in
                                BranchRowView(
                                    branch: branch,
                                    isCurrentBranch: false,
                                    activeSession: activeSessionBranches[branch.displayName]
                                )
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
        .frame(width: 250)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Branch Row View

struct BranchRowView: View {
    let branch: Branch
    let isCurrentBranch: Bool
    let activeSession: Int?

    var body: some View {
        HStack(spacing: 8) {
            // Branch indicator dot
            Circle()
                .fill(isCurrentBranch ? Color.green : (branch.isRemote ? Color.blue : Color.gray))
                .frame(width: 8, height: 8)

            // Connector line
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 12, height: 2)

            // Branch name
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isCurrentBranch {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                    Text(branch.isRemote ? branch.displayName : branch.name)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(isCurrentBranch ? .bold : .regular)
                        .lineLimit(1)
                }

                // Commit info
                if !branch.commitHash.isEmpty {
                    Text(branch.shortCommitHash)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Active session indicator
            if let sessionId = activeSession {
                HStack(spacing: 2) {
                    Image(systemName: "terminal")
                        .font(.caption2)
                    Text("#\(sessionId)")
                        .font(.caption2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(4)
            }

            // Ahead/behind indicators
            if branch.aheadCount > 0 || branch.behindCount > 0 {
                HStack(spacing: 4) {
                    if branch.aheadCount > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.up")
                            Text("\(branch.aheadCount)")
                        }
                        .font(.caption2)
                        .foregroundColor(.green)
                    }
                    if branch.behindCount > 0 {
                        HStack(spacing: 1) {
                            Image(systemName: "arrow.down")
                            Text("\(branch.behindCount)")
                        }
                        .font(.caption2)
                        .foregroundColor(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrentBranch ? Color.green.opacity(0.1) : Color.clear)
        )
    }
}

#Preview {
    BranchVisualizationView(
        gitManager: GitManager(),
        activeSessionBranches: ["main": 1, "feature/test": 3]
    )
}
