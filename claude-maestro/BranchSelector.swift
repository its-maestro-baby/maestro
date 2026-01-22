//
//  BranchSelector.swift
//  claude-maestro
//
//  Branch selection dropdown component
//

import SwiftUI

struct BranchSelector: View {
    @ObservedObject var gitManager: GitManager
    @Binding var selectedBranch: String?
    @State private var showCreateBranch = false
    @State private var newBranchName = ""
    @State private var baseBranch: String?

    var body: some View {
        Menu {
            // Current selection indicator
            if let selected = selectedBranch {
                Section {
                    Label("Selected: \(selected)", systemImage: "checkmark.circle.fill")
                }
            }

            // Option to use current branch (no assignment)
            Section("Options") {
                Button {
                    selectedBranch = nil
                } label: {
                    Label("Use Current Branch", systemImage: "arrow.uturn.backward")
                }
            }

            // Local branches
            if !gitManager.localBranches.isEmpty {
                Section("Local Branches") {
                    ForEach(gitManager.localBranches) { branch in
                        Button {
                            selectedBranch = branch.name
                        } label: {
                            HStack {
                                if branch.isHead {
                                    Image(systemName: "star.fill")
                                }
                                Text(branch.name)
                                if selectedBranch == branch.name {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            // Remote branches (for checkout -b)
            if !gitManager.remoteBranches.isEmpty {
                Section("Remote Branches") {
                    ForEach(gitManager.remoteBranches) { branch in
                        Button {
                            selectedBranch = branch.displayName
                        } label: {
                            Text(branch.displayName)
                        }
                    }
                }
            }

            Divider()

            // Create new branch
            Button {
                showCreateBranch = true
            } label: {
                Label("Create New Branch...", systemImage: "plus.circle")
            }

        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.branch")
                Text(selectedBranch ?? "Current")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(6)
        }
        .sheet(isPresented: $showCreateBranch) {
            CreateBranchSheet(
                gitManager: gitManager,
                newBranchName: $newBranchName,
                baseBranch: $baseBranch,
                onComplete: { branch in
                    selectedBranch = branch
                    showCreateBranch = false
                }
            )
        }
    }
}

// MARK: - Create Branch Sheet

struct CreateBranchSheet: View {
    @ObservedObject var gitManager: GitManager
    @Binding var newBranchName: String
    @Binding var baseBranch: String?
    var onComplete: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("Create New Branch")
                .font(.headline)

            TextField("Branch name (e.g., feature/claude-1)", text: $newBranchName)
                .textFieldStyle(.roundedBorder)

            Picker("Base branch:", selection: $baseBranch) {
                Text("Current HEAD").tag(nil as String?)
                ForEach(gitManager.localBranches) { branch in
                    Text(branch.name).tag(branch.name as String?)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Create") {
                    createBranch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newBranchName.isEmpty || isCreating)
            }
        }
        .padding()
        .frame(width: 350)
    }

    private func createBranch() {
        isCreating = true
        errorMessage = nil

        Task {
            do {
                try await gitManager.createBranch(name: newBranchName, from: baseBranch)
                await MainActor.run {
                    onComplete(newBranchName)
                    newBranchName = ""
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}

#Preview {
    BranchSelector(gitManager: GitManager(), selectedBranch: .constant(nil))
}
