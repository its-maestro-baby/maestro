Here is the comprehensive architectural breakdown of the Maestro application, designed to guide your rewrite to Tauri 2.x (Rust/React).

# Maestro (MacOS) Architectural Analysis

## 1. Application Architecture

**Bootstrap & Lifecycle**
*   **Entry Point:** `claude_maestroApp.swift` initializes the app. It performs one-time setup (`ClaudeDocManager.setupCLIContextFiles()`) to ensure the AI tools (Claude/Gemini) know how to behave.
*   **Delegate:** `AppDelegate` handles application termination, acting as the safety net to kill all managed processes and orphaned agent processes to prevent zombie processes on the host.
*   **Root View:** `ContentView` uses a `NavigationSplitView`.
    *   **Sidebar:** `SidebarView` handles configuration, process monitoring, and presets.
    *   **Detail:** `MainContentView` acts as the workspace. It conditionally renders either the `PreLaunchView` (setup) or the `DynamicTerminalGridView` (active session).

**View Hierarchy Strategy**
The app follows a standard SwiftUI MVVM (Model-View-ViewModel) pattern but relies on a "God Object" (`SessionManager`) injected into the environment to orchestrate communication between the sidebar configuration and the active terminal grid.

## 2. Session Management

**Core Logic (`SessionManager.swift`)**
Sessions are transient objects representing a coding task.
*   **Data Structure:** `SessionInfo` holds the state:
    *   `id`: Integer identity.
    *   `mode`: The AI tool (Claude, Gemini, Codex).
    *   `workingDirectory`: The path (usually a git worktree).
    *   `terminalPid`: The PID of the shell running the AI.
    *   `status`: Enum (Idle, Working, Error, Done).
*   **Grid Layout:** `GridConfiguration` statically calculates rows/columns based on the count (e.g., 6 sessions = 2x3 grid).
*   **Persistence:** `UserDefaults` stores simple session configurations (modes, branches), but *active* state (PIDs, running commands) is ephemeral and reset on restart.

## 3. Process Management (Critical Subsystem)

This is the most complex part of the app and must be ported carefully to Rust.

**Architecture**
*   **Terminal Emulation:** The UI uses `SwiftTerm` (`MaestroTerminalView`) for the frontend.
*   **Execution Strategy:**
    1.  **Shell Spawning:** It spawns a user shell (`/bin/zsh`) with flags `-l -i` (login, interactive). This ensures the user's `PATH`, `nvm`, and `conda` environments are loaded.
    2.  **Injection:** It programmatically sends text commands to the running shell's stdin to setup the environment, `cd` into the specific worktree, and run the AI command (e.g., `claude`).
*   **Isolation (`ProcessRegistry` & `ProcessLauncher`):**
    *   Uses low-level `posix_spawn` and `setsid` (process groups) to track processes.
    *   **Process Groups:** Crucial. Each session gets its own Process Group ID (PGID). This allows the app to send `SIGKILL` to the specific session's group, killing the Shell, the Node process, and any subprocesses started by the AI, without killing other sessions.

**Dev Server Detection**
*   `ManagedProcessCoordinator` parses terminal stdout streams using regex.
*   It looks for patterns like `localhost:3000` or `127.0.0.1:8080`.
*   When found, it updates the UI to show an "Open Browser" button.

## 4. Git Worktree System

Maestro's unique selling point is running multiple AI agents on the same repo without file lock conflicts.

**Workflow (`WorktreeManager.swift`)**
1.  **Storage:** Worktrees are created in `~/.claude-maestro/worktrees/<repo-hash>/<branch-name>`.
2.  **Creation Logic:**
    *   Checks if the desired branch is currently checked out in the *main* repo. If so, it forces the main repo to switch to `default` (main/master) to free up the branch.
    *   Runs `git worktree add <path> <branch>`.
3.  **Session Binding:** The Session's `workingDirectory` is set to this isolated path. The AI tool thinks it is in a standalone project.
4.  **Cleanup:** Aggressive. On session close or app exit, `git worktree remove` and directory deletion occur to prevent disk clutter.

## 5. State Management & Data Flow

**Primary Stores**
*   **`SessionManager` (ObservableObject):** Central hub. Modified by Sidebar, observed by Grid.
*   **`GitManager` (Actor-like ObservableObject):** Wraps shell calls to `git`. It does *not* use libgit2; it shells out to the system `git` binary to ensure compatibility with the user's git config/hooks.
*   **`ProcessRegistry` (Actor):** Thread-safe store for PIDs and mapping processes to sessions.

**Sidecar State Pattern (`MaestroMCPServer`)**
The app uses a file-system based "sidecar" pattern to get status updates from the CLI tools back to the UI.
1.  **The Server:** A local MCP (Model Context Protocol) server runs (or is emulated).
2.  **The Hook:** The AI CLI tools are configured to call an MCP tool `maestro_status`.
3.  **The IPC:** When the AI calls this tool, the server writes a JSON file to `/tmp/maestro/agents/<agent-id>.json`.
4.  **The Monitor:** `MaestroStateMonitor` polls this directory every 0.5s to update the UI status pills (Idle -> Working).

## 6. Key Abstractions for Rewrite

To rewrite this in Tauri, you will need to map these Swift components to Rust/React equivalents.

| Swift Component | Responsibility | Tauri/Rust Equivalent |
| :--- | :--- | :--- |
| `SwiftTerm` | Rendering terminal text | **Frontend:** `xterm.js` <br> **Backend:** `portable-pty` (Rust crate) |
| `ProcessLauncher` | Spawning shells with PTYs | **Rust:** `portable-pty` handles spawning and PTY master/slave pairs. |
| `ProcessRegistry` | Tracking PIDs/PGIDs | **Rust:** A generic `Mutex<HashMap<Session