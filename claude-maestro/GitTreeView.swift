//
//  GitTreeView.swift
//  claude-maestro
//
//  GitKraken-style commit graph visualization
//

import SwiftUI

struct GitTreeView: View {
    @ObservedObject var gitManager: GitManager
    @StateObject private var graphData = CommitGraphData()
    @State private var selectedCommit: Commit?
    @State private var hoveredCommit: Commit?

    let activeSessionBranches: [String: Int]
    let commitLimit: Int = 50

    // Layout constants
    static let rowHeight: CGFloat = 32
    static let columnWidth: CGFloat = 16
    static let graphPadding: CGFloat = 12
    static let commitCircleSize: CGFloat = 10

    var body: some View {
        HSplitView {
            // Main graph area
            VStack(spacing: 0) {
                // Header
                GitTreeHeader(
                    gitManager: gitManager,
                    commitCount: graphData.commits.count,
                    isLoading: graphData.isLoading,
                    onRefresh: { Task { await loadGraph() } }
                )

                Divider()

                // Graph content
                if graphData.isLoading {
                    loadingView
                } else if !gitManager.isGitRepo {
                    notGitRepoView
                } else if graphData.commits.isEmpty {
                    emptyView
                } else {
                    graphScrollView
                }
            }
            .frame(minWidth: 300)

            // Detail panel (when commit selected)
            if let commit = selectedCommit {
                CommitDetailPanel(
                    commit: commit,
                    gitManager: gitManager,
                    onClose: { selectedCommit = nil },
                    onRefresh: { Task { await loadGraph() } }
                )
                .frame(minWidth: 250, idealWidth: 280, maxWidth: 350)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .task {
            await loadGraph()
        }
        .onChange(of: gitManager.currentBranch) { _, _ in
            Task { await loadGraph() }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading commits...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var notGitRepoView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Not a git repository")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("No commits found")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var graphScrollView: some View {
        ScrollView([.vertical, .horizontal]) {
            ZStack(alignment: .topLeading) {
                // Connection lines layer (behind everything)
                GraphCanvas(
                    nodes: graphData.nodes,
                    rails: graphData.rails,
                    rowHeight: Self.rowHeight,
                    columnWidth: Self.columnWidth,
                    graphPadding: Self.graphPadding
                )

                // Commit rows
                VStack(spacing: 0) {
                    ForEach(graphData.nodes) { node in
                        CommitRowView(
                            node: node,
                            rails: graphData.rails,
                            isSelected: selectedCommit?.id == node.id,
                            isHovered: hoveredCommit?.id == node.id,
                            activeSession: findActiveSession(for: node.commit),
                            columnWidth: Self.columnWidth,
                            graphPadding: Self.graphPadding,
                            commitCircleSize: Self.commitCircleSize
                        )
                        .frame(height: Self.rowHeight)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedCommit = node.commit
                            }
                        }
                        .onHover { isHovered in
                            hoveredCommit = isHovered ? node.commit : nil
                        }
                    }
                }
            }
            .frame(
                minWidth: totalWidth,
                minHeight: CGFloat(graphData.nodes.count) * Self.rowHeight
            )
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helper Properties

    private var totalWidth: CGFloat {
        let graphWidth = CGFloat(max(graphData.rails.count, 1)) * Self.columnWidth + Self.graphPadding * 2
        let messageWidth: CGFloat = 400
        return graphWidth + messageWidth
    }

    // MARK: - Helper Methods

    private func findActiveSession(for commit: Commit) -> Int? {
        for ref in commit.refs {
            if let session = activeSessionBranches[ref.name] {
                return session
            }
        }
        return nil
    }

    private func loadGraph() async {
        graphData.isLoading = true
        defer { graphData.isLoading = false }

        do {
            let commits = try await gitManager.fetchCommitHistory(limit: commitLimit)
            let engine = GraphLayoutEngine()
            let (nodes, rails) = engine.layoutGraph(commits: commits)

            await MainActor.run {
                graphData.update(commits: commits, nodes: nodes, rails: rails)
            }
        } catch {
            await MainActor.run {
                graphData.error = error as? GitError ?? .commandFailed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Header View

struct GitTreeHeader: View {
    @ObservedObject var gitManager: GitManager
    let commitCount: Int
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "point.3.connected.trianglepath.dotted")
            Text("Commits")
                .font(.headline)

            if commitCount > 0 {
                Text("(\(commitCount))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Current branch badge
            if let branch = gitManager.currentBranch {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    Text(branch)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.yellow.opacity(0.15))
                .cornerRadius(6)
            }

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    GitTreeView(
        gitManager: GitManager(),
        activeSessionBranches: ["main": 1, "feature/test": 3]
    )
    .frame(width: 600, height: 400)
}
