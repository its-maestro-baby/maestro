Here is a comprehensive breakdown of the systems within `maestro-macos`, analyzed for the purpose of a Linux Debian Tauri rewrite.

# Maestro System Architecture Report

## 1. MCP Server Architecture (Native Swift)
The `MaestroMCPServer` is a native Swift executable that implements the Model Context Protocol (MCP) over `stdio`. It serves as a bridge between the AI Agent (Claude Code) and the local system, specifically for managing development processes.

*   **Transport Protocol:** JSON-RPC 2.0 over Standard Input/Output (`stdio`).
    *   **Input:** Reads newline-delimited JSON-RPC requests from `stdin`.
    *   **Output:** Writes JSON-RPC responses to `stdout`.
    *   **Logging:** Writes logs to `stderr` (to avoid corrupting the JSON-RPC stream).
*   **Core Components:**
    *   `MCPStdioServer`: The main actor managing the run loop.
    *   `MCPToolHandler`: Dispatches tool calls to specific implementations.
    *   `ManagedProcessCoordinator`: Manages the lifecycle of child processes (dev servers).
*   **Exposed Tools:**
    *   `start_dev_server`: Spawns a background process (e.g., `npm run dev`) for a specific session.
    *   `stop_dev_server`: Kills a specific session's process.
    *   `restart_dev_server`: Restarts a process with the same configuration.
    *   `get_server_status`: Returns metadata (PID, port, status, URL) for a session.
    *   `get_server_logs`: streaming access to the process's stdout/stderr.
    *   `list_available_ports`: Scans for open ports in the 3000-3099 range.
    *   `detect_project_type`: Heuristic analysis (checking `package.json`, `Cargo.toml`) to suggest run commands.
    *   `list_system_processes`: Lists external processes listening on ports (likely using `lsof` or native APIs).

## 2. Agent Status System
This system allows the UI to visualize what the AI agent is doing without direct socket communication, relying instead on a shared filesystem contract.

*   **Mechanism:** File-based Polling.
*   **Location:** `/tmp/maestro/agents/` (Linux/macOS temp directory).
*   **Data Flow:**
    1.  The Agent (via a `maestro_status` tool/MCP) writes state to `<temp_dir>/agent-<sessionId>.json`.
    2.  `MaestroStateMonitor` polls this directory every **0.5 seconds**.
*   **State Model (`AgentState`):**
    *   `state`: Enum (`idle`, `working`, `needs_input`, `finished`, `error`).
    *   `message`: Human-readable status description.
    *   `needsInputPrompt`: Specific question if state is `needs_input`.
    *   `timestamp`: ISO 8601 timestamp (used to detect stale states > 5 mins).
*   **UI Integration:** The monitor publishes an `agents` dictionary. Transitions to `finished` trigger a sound effect.

## 3. Plugin Marketplace
A decentralized system for extending capabilities via Git repositories.

*   **Source Types:**
    *   **Official:** Anthropic's curated list.
    *   **Marketplace:** 3rd-party Git repositories containing a `.claude-plugin/marketplace.json` or `plugins.json`.
    *   **Local:** Manual paths.
*   **Plugin Structure:**
    A valid plugin directory contains:
    *   `commands/`: Directory of `.md` command definitions.
    *   `skills/`: Directory of Skill definitions (or a root `SKILL.md`).
    *   `hooks/`: `hooks.json` defining lifecycle events.
    *   `.mcp.json`: Configuration for custom MCP servers included in the plugin.
*   **Installation Workflow:**
    1.  **Fetch:** `MarketplaceManager` parses remote manifests.
    2.  **Install:** Clones the repository to `~/.claude/plugins/<plugin-id>`.
    3.  **Discovery:** Scans the directory to register contained Skills, Commands, and Hooks.
    4.  **Symlinking:** Creates a symlink in `~/.claude/plugins/` to allow variable resolution (see Commands).

## 4. Skills System
Skills are reusable prompt definitions that the Agent can invoke.

*   **Discovery Locations:**
    1.  `~/.claude/skills/` (Legacy/User personal).
    2.  Inside installed Plugins (`~/.claude/plugins/*/skills`).
    3.  Project-local `.claude/skills/`.
*   **Definition:** `SKILL.md` files with YAML frontmatter:
    *   `name`, `description`
    *   `allowed-tools` (e.g., "Read, Grep")
    *   `argument-hint`
*   **Session Injection (Key Architecture):**
    Skills are **not** global. They are injected per-session.
    *   **Logic:** `syncWorktreeSkills(worktreePath, sessionId)`
    *   **Action:** Creates symbolic links in the target project's `.claude/skills/` directory pointing to the installed skill location.
    *   **Benefit:** Allows toggling skills on/off for specific chat sessions without modifying the global environment.

## 5. Commands System
Slash commands (e.g., `/test`, `/deploy`) that provide shortcuts or specialized workflows.

*   **Discovery:** Similar to Skills (`~/.claude/commands`, Plugins, Project).
*   **Definition:** Markdown files with frontmatter.
*   **Variable Substitution:**
    *   Plugins often need to reference their own directory (e.g., to run a script included in the plugin).
    *   The variable `${CLAUDE_PLUGIN_ROOT}` is supported in command definitions.
*   **Session Injection:**
    *   **Logic:** `syncWorktreeCommands(worktreePath, sessionId)`
    *   **Action:**
        *   If the command contains `${CLAUDE_PLUGIN_ROOT}`: Reads the file, substitutes the variable with the absolute path of the plugin, and **writes a copy** to the project's `.claude/commands/`.
        *   Otherwise: Creates a **symbolic link**.

## 6. Hooks System
Allows plugins to intercept Agent lifecycle events.

*   **Discovery:** Scans `hooks/hooks.json` in installed plugins.
*   **Event Types:** `PreToolUse`, `PostToolUse`, `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `Stop`.
*   **Configuration (`hooks.json`):**
    *   Maps event types to "Matchers" (filters by `tool` or `path`).
    *   Defines actions: `command` (run shell cmd) or `prompt` (inject text).
*   **Session Injection:**
    *   **Logic:** `syncWorktreeHooks(worktreePath, sessionId)`
    *   **Action:** Reads/Creates `.claude/settings.local.json` in the project root.
    *   **Merging:** Aggregates hooks from all enabled plugins for that session.
    *   **Substitution:** Resolves `${CLAUDE_PLUGIN_ROOT}` in command/prompt strings before writing to JSON.

## 7. Key Data Models (Swift -> Rust Mapping)

| Swift Model | Description | Rust/Tauri Equivalent |
| :--- | :--- | :--- |
| `AgentState` | Status of the running agent | `struct AgentState` (Serde compatible) |
| `MarketplacePlugin` | Metadata from remote JSON | `struct MarketplacePlugin` |
| `InstalledPlugin` | Local installation record | `struct InstalledPlugin` (Stored in generic `app_data` JSON) |
| `SkillConfig` | Parsed `SKILL.md` data | `struct SkillConfig` |
| `CommandConfig` | Parsed Command `.md` | `struct CommandConfig` |
| `SessionConfig` | IDs of enabled items per session | `HashMap<SessionId, SessionConfig>` |

## 8. Conversion Strategy: Linux Debian (Tauri + Rust + React)

### Backend (Rust)
1.  **MCP Server:**
    *   Use `tokio` for async runtime.
    *   Implement the `stdio` loop handling JSON-RPC.
    *   Use `tokio::process::Command` to manage the lifecycle of dev servers (start/stop/restart).
    *   Implement `lsof` or read `/proc/net/tcp` for `list_system_processes`.
2.  **Managers (Marketplace/Skills/Commands):**
    *   Implement as Tauri `State` managed structures (`Mutex<SkillManager>`, etc.).
    *   Use `std::fs` and `std::os::unix::fs::symlink` for the "Sync" logic (creating symlinks in worktrees).
    *   **Critical:** Replicate the `${CLAUDE_PLUGIN_ROOT}` substitution logic in Rust for Commands and Hooks.
3.  **State Monitor:**
    *   Spawn a background `tokio::task` that polls `/tmp/maestro/agents/`.
    *   Use `app_handle.emit()` to push state changes to the React frontend in real-time.

### Frontend (React + TypeScript)
1.  **UI Components:**
    *   Port SwiftUI `MarketplaceBrowserView` to a React Component (e.g., utilizing Shadcn UI or Tailwind).
    *   Port `SkillSelector` and `MCPSelector` to Dropdown/Combobox components.
2.  **State Management:**
    *   Use `TanStack Query` (React Query) to fetch lists of Skills/Plugins/Commands from Rust.
    *   Use `Tauri Events` (`listen()`) to update the Agent Status indicator live.
3.  **Persistence:**
    *   Instead of `UserDefaults`, use `tauri-plugin-store` (persists to `.dat` or `.json` in `~/.config/maestro/`).

### Specific Linux Considerations
*   **Process Management:** Swift uses `ProcessInfo` and specific macOS APIs. Rust will need to rely on standard Linux process signaling (`kill`, `SIGTERM`).
*   **Paths:**
    *   macOS: `~/Library/Application Support/...`
    *   Linux: `~/.config/...` or `~/.local/share/...` (Follow XDG Base Directory Spec).
    *   Project Config: Stays as `.claude/` inside the project root (cross-platform standard).
