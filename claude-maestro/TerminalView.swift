//
//  TerminalView.swift
//  claude-maestro
//
//  Created by Jack Wakem on 6/1/2026.
//

import SwiftUI
import AppKit
import SwiftTerm

// MARK: - Terminal Controller

class TerminalController {
    weak var coordinator: EmbeddedTerminalView.Coordinator?

    func sendCommand(_ command: String) {
        coordinator?.sendCommand(command)
    }
}

// MARK: - Embedded Terminal View

struct EmbeddedTerminalView: NSViewRepresentable {
    let sessionId: Int
    let workingDirectory: String
    @Binding var status: SessionStatus
    let shouldLaunch: Bool
    let assignedBranch: String?
    let mode: TerminalMode
    var onLaunched: () -> Void
    var onCLILaunched: () -> Void
    var controller: TerminalController?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.processDelegate = context.coordinator
        terminal.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        // Configure dark terminal color scheme
        terminal.nativeBackgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        terminal.nativeForegroundColor = NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)

        // Install a rich ANSI color palette (16 colors)
        let colors: [SwiftTerm.Color] = [
            // Standard colors (0-7)
            SwiftTerm.Color(red: 38, green: 38, blue: 43),      // Black
            SwiftTerm.Color(red: 242, green: 89, blue: 89),     // Red
            SwiftTerm.Color(red: 89, green: 217, blue: 115),    // Green
            SwiftTerm.Color(red: 242, green: 204, blue: 89),    // Yellow
            SwiftTerm.Color(red: 115, green: 153, blue: 242),   // Blue
            SwiftTerm.Color(red: 217, green: 127, blue: 217),   // Magenta
            SwiftTerm.Color(red: 115, green: 217, blue: 217),   // Cyan
            SwiftTerm.Color(red: 217, green: 217, blue: 217),   // White
            // Bright colors (8-15)
            SwiftTerm.Color(red: 115, green: 115, blue: 128),   // Bright Black
            SwiftTerm.Color(red: 255, green: 115, blue: 115),   // Bright Red
            SwiftTerm.Color(red: 115, green: 242, blue: 140),   // Bright Green
            SwiftTerm.Color(red: 255, green: 230, blue: 115),   // Bright Yellow
            SwiftTerm.Color(red: 140, green: 179, blue: 255),   // Bright Blue
            SwiftTerm.Color(red: 242, green: 153, blue: 242),   // Bright Magenta
            SwiftTerm.Color(red: 140, green: 242, blue: 242),   // Bright Cyan
            SwiftTerm.Color(red: 255, green: 255, blue: 255),   // Bright White
        ]
        terminal.installColors(colors)

        context.coordinator.terminal = terminal
        controller?.coordinator = context.coordinator
        return terminal
    }

    func updateNSView(_ terminal: LocalProcessTerminalView, context: Context) {
        if shouldLaunch && !context.coordinator.hasLaunched {
            context.coordinator.hasLaunched = true
            launchTerminal(in: terminal)
            onLaunched()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionId: sessionId, status: $status)
    }

    private func launchTerminal(in terminal: LocalProcessTerminalView) {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"

        // Build environment with user's PATH
        var env = ProcessInfo.processInfo.environment

        // Ensure common paths are included
        let additionalPaths = [
            "\(NSHomeDirectory())/.local/bin",
            "\(NSHomeDirectory())/.cargo/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin"
        ]

        if let existingPath = env["PATH"] {
            env["PATH"] = additionalPaths.joined(separator: ":") + ":" + existingPath
        } else {
            env["PATH"] = additionalPaths.joined(separator: ":") + ":/usr/bin:/bin"
        }

        // Build command - cd and optional branch checkout
        var command = "cd '\(workingDirectory)'"

        // Checkout branch if assigned
        if let branch = assignedBranch {
            command += " && git checkout '\(branch)' 2>/dev/null || git checkout -b '\(branch)'"
        }

        // Auto-launch CLI tool if in AI mode, otherwise just open shell
        if let cliCommand = mode.command {
            // Launch the CLI tool directly (it will take over the terminal)
            command += " && \(cliCommand)"
            // Mark CLI as launched
            DispatchQueue.main.async {
                self.onCLILaunched()
            }
        } else {
            // Plain terminal - just exec shell
            command += " && exec $SHELL"
        }

        terminal.startProcess(
            executable: shell,
            args: ["-l", "-i", "-c", command],
            environment: Array(env.map { "\($0.key)=\($0.value)" }),
            execName: nil
        )
    }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let sessionId: Int
        @Binding var status: SessionStatus
        var hasLaunched = false
        private var outputBuffer = ""
        weak var terminal: LocalProcessTerminalView?

        // Activity-based state tracking
        private var lastOutputTime: Date?
        private var idleCheckTimer: Timer?
        private var initializingTimer: Timer?

        // Configurable timeouts
        private let initializingTimeout: TimeInterval = 3.0  // Time after launch before assuming idle
        private let idleTimeout: TimeInterval = 2.0          // Time without output = idle

        init(sessionId: Int, status: Binding<SessionStatus>) {
            self.sessionId = sessionId
            self._status = status
            super.init()

            // Set initial state to initializing
            DispatchQueue.main.async {
                status.wrappedValue = .initializing
            }
            scheduleInitializingCheck()
        }

        func sendCommand(_ command: String) {
            guard let terminal = terminal else { return }
            let commandWithNewline = command + "\n"
            terminal.send(txt: commandWithNewline)
        }

        func terminateProcess() {
            // Clean up timers
            idleCheckTimer?.invalidate()
            initializingTimer?.invalidate()
            terminal = nil
        }

        func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
            // Clean up timers
            idleCheckTimer?.invalidate()
            initializingTimer?.invalidate()

            DispatchQueue.main.async {
                if exitCode == 0 {
                    self.status = .done
                } else {
                    self.status = .error
                }
            }
        }

        func dataReceived(slice: ArraySlice<UInt8>) {
            if let str = String(bytes: slice, encoding: .utf8) {
                outputBuffer += str
                lastOutputTime = Date()

                // Output received = we're working (unless in special state)
                DispatchQueue.main.async {
                    if self.status != .waiting && self.status != .error {
                        self.status = .working
                    }
                }

                // Check for special patterns (confirmation prompts, errors)
                checkSpecialPatterns(str)

                // Reset idle timer
                scheduleIdleCheck()

                // Keep buffer manageable
                if outputBuffer.count > 10000 {
                    outputBuffer = String(outputBuffer.suffix(5000))
                }
            }
        }

        private func checkSpecialPatterns(_ text: String) {
            let lowercased = text.lowercased()

            DispatchQueue.main.async {
                // Waiting patterns (confirmation prompts) - be more specific to avoid false positives
                let waitingPatterns = ["(y/n)", "[y/n]", "(yes/no)", "[yes/no]",
                                       "confirm?", "permission", "allow this", "approve"]
                if waitingPatterns.contains(where: { lowercased.contains($0) }) {
                    self.status = .waiting
                    return
                }

                // Error patterns - only match clear error indicators
                let errorPatterns = ["error:", "failed:", "exception:", "fatal:",
                                     "command not found", "permission denied", "not recognized"]
                if errorPatterns.contains(where: { lowercased.contains($0) }) {
                    self.status = .error
                }
            }
        }

        private func scheduleInitializingCheck() {
            initializingTimer?.invalidate()
            initializingTimer = Timer.scheduledTimer(withTimeInterval: initializingTimeout, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                DispatchQueue.main.async {
                    // If still initializing after timeout, assume we're now idle
                    if self.status == .initializing {
                        self.status = .idle
                    }
                }
            }
        }

        private func scheduleIdleCheck() {
            idleCheckTimer?.invalidate()
            idleCheckTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
                guard let self = self else { return }

                // If no new output since timer was set, transition to idle
                if let lastOutput = self.lastOutputTime,
                   Date().timeIntervalSince(lastOutput) >= self.idleTimeout {
                    DispatchQueue.main.async {
                        // Only transition to idle from working state
                        if self.status == .working {
                            self.status = .idle
                        }
                    }
                }
            }
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            // Handle terminal resize
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // Handle title changes
        }

        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
            // Handle directory changes
        }

        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String : String]) {
            if let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Terminal Session View

struct TerminalSessionView: View {
    let session: SessionInfo
    let workingDirectory: String
    let shouldLaunch: Bool
    @Binding var status: SessionStatus
    @Binding var mode: TerminalMode
    @Binding var assignedBranch: String?
    @ObservedObject var gitManager: GitManager
    let isTerminalLaunched: Bool
    let isClaudeRunning: Bool
    var onLaunchClaude: () -> Void
    var onClose: () -> Void
    var onTerminalLaunched: () -> Void
    var onLaunchTerminal: () -> Void

    @State private var terminalController = TerminalController()

    var body: some View {
        VStack(spacing: 0) {
            // Status bar with controls
            HStack(spacing: 6) {
                // Status indicator
                Image(systemName: status.icon)
                    .foregroundColor(status.color)
                    .symbolEffect(.pulse, isActive: status == .working)
                    .font(.caption)

                // Direct mode picker (replaces cycling toggle)
                CompactModePicker(selectedMode: $mode, isDisabled: shouldLaunch)

                // Session label
                Text("\(mode.rawValue) #\(session.id)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(mode.color)

                Spacer()

                // Branch selector (only when terminal not launched)
                if gitManager.isGitRepo && !shouldLaunch {
                    BranchSelector(
                        gitManager: gitManager,
                        selectedBranch: $assignedBranch
                    )
                }

                // Branch label (after terminal launched)
                if gitManager.isGitRepo && shouldLaunch {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.caption2)
                        Text(assignedBranch ?? "Current")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }

                // Launch Terminal button (before terminal launched)
                if !shouldLaunch {
                    Button(action: onLaunchTerminal) {
                        HStack(spacing: 2) {
                            Image(systemName: "play.fill")
                            Text("Launch")
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(mode.color)
                }

                // Status label
                Text(status.label)
                    .font(.caption2)
                    .foregroundColor(status.color)

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Close terminal")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.15))

            // Terminal content area
            if shouldLaunch {
                // Actual terminal
                EmbeddedTerminalView(
                    sessionId: session.id,
                    workingDirectory: workingDirectory,
                    status: $status,
                    shouldLaunch: shouldLaunch,
                    assignedBranch: assignedBranch,
                    mode: mode,
                    onLaunched: {
                        onTerminalLaunched()
                    },
                    onCLILaunched: {
                        onLaunchClaude()
                    },
                    controller: terminalController
                )
            } else {
                // Pending state placeholder
                VStack(spacing: 12) {
                    Spacer()

                    Image(systemName: mode.icon)
                        .font(.system(size: 32))
                        .foregroundColor(mode.color.opacity(0.5))

                    Text("Select branch and click Launch")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let branch = assignedBranch {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.branch")
                            Text(branch)
                        }
                        .font(.caption2)
                        .foregroundColor(.blue)
                    } else {
                        Text("Using current branch")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(shouldLaunch ? status.color : Color.gray.opacity(0.5), lineWidth: 2)
        )
    }
}
