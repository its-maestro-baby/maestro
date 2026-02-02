# Maestro Linux (Tauri 2.x) — Master Architectural Plan

**Version:** 3.2.0
**Date:** 2026-01-30
**Target OS:** Linux (Debian/Ubuntu)
**Stack:** Tauri 2.0 (Rust) + React 18 (TypeScript) + TailwindCSS
**Package Output:** `.deb`
**Source Analysis:** 18,500 lines Swift across 50+ files (claude-maestro macOS)

---

## 1. Executive Summary

This document is the **definitive architectural blueprint** for rewriting the Maestro macOS application (Swift/SwiftUI) into a native Linux application using Tauri 2.x. It synthesizes three detailed source analysis reports validated against the actual Swift codebase.

**Core Philosophy:**
- **Backend (Rust):** Heavy lifting — PTY management, Git CLI orchestration, worktree lifecycle, plugin/skill/hook injection, MCP sidecar, dev server coordination, process group management.
- **Frontend (React):** Visualization — Xterm.js terminals, HTML5 Canvas git graph, Zustand state, TailwindCSS styling.
- **Communication:** Tauri Commands (IPC) for actions, Tauri Events for streams (PTY output, status updates), filesystem polling for agent status (decoupled sidecar pattern).
- **Workspace Model:** Multiple open projects in tabs (VS Code-style). Each project tab owns its own session grid, git state, worktree map, and plugin config.

---

## 2. Locked Decisions

The following decisions are **final** and form the basis of all implementation phases.

### 2.1 Paths & Storage (XDG Compliant)
- **Worktrees:** `~/.local/share/maestro/worktrees/<repo-hash>/<sanitized-branch>`
  - Hash: Deterministic SHA256 of the canonical repo path (stable across runs, unlike Swift's non-deterministic `Hasher`)
  - Prune on session close AND app launch (mirror macOS orphan cleanup)
- **App Config:** `~/.config/maestro/store.json` (via `tauri-plugin-store`)
- **App Data:** `~/.local/share/maestro/` (logs, worktrees)
- **Logs:** `~/.local/share/maestro/logs/session-<id>.log`
- **Agent Status:** `/tmp/maestro/agents/agent-<id>.json`
- **Plugins:** `~/.claude/plugins/` (symlinks to installed plugins)
- **Marketplaces:** `~/.claude/plugins/marketplaces/` (cloned source repos)

### 2.2 MCP Status Interface
Compatible with macOS implementation:
- **Path:** `/tmp/maestro/agents/agent-<id>.json`
- **Schema:**
  ```json
  {
    "agentId": "agent-<session_id>",
    "state": "idle|working|needs_input|finished|error",
    "message": "Human-readable status",
    "needsInputPrompt": "Optional question text",
    "timestamp": "2026-01-30T20:14:15.123Z"
  }
  ```
- **Polling:** Every 500ms. Prune stale files > 5 min.
- **Sound:** Transition to `finished` triggers notification sound.

### 2.3 Multi-AI Modes
Direct mapping from UI label to CLI binary:
- `Claude` -> `claude`
- `Gemini` -> `gemini`
- `Codex` -> `codex`
- `Plain` -> launches shell only (no AI command)

Detection: Run `which <binary>` before launch. Disable mode if binary not found.

### 2.4 Persistence Scope
`tauri-plugin-store` persists to `~/.config/maestro/store.json`:
- Session configurations (modes, branches — NOT PIDs/active state)
- Template presets
- Quick actions
- Plugin enablement flags per session
- Marketplace source URLs
- Last-used project path

### 2.5 Multi-Project Tabs (Workspace Model)
- Maestro supports **multiple open projects/repos** in a single window, each in its own tab.
- Each tab owns: `projectPath`, session grid (1–12), git state, worktree map, and per-project plugin configs.
- Session IDs remain numeric, but all session state is scoped to a specific project tab.
- Open project tabs persist in store.json (list of projects + last active tab).

---

## 3. Project Structure

```text
maestro-linux/
├── src-tauri/                      # RUST BACKEND
│   ├── Cargo.toml
│   ├── tauri.conf.json
│   ├── src/
│   │   ├── main.rs                 # Entry point, plugin registration
│   │   ├── lib.rs                  # Tauri builder setup
│   │   ├── commands/               # Tauri IPC Commands (exposed to frontend)
│   │   │   ├── mod.rs
│   │   │   ├── terminal.rs         # spawn_shell, resize_pty, write_stdin, kill_session
│   │   │   ├── git.rs              # git_log, git_branches, checkout, worktree_add, diff_tree
│   │   │   ├── session.rs          # create_session, close_session, batch_assign
│   │   │   ├── plugins.rs          # scan_plugins, install_plugin, toggle_skill
│   │   │   └── config.rs           # get_store, set_store, quick_actions CRUD
│   │   ├── core/                   # Internal Business Logic
│   │   │   ├── mod.rs
│   │   │   ├── process_manager.rs  # PTY lifecycle, process groups (setsid), PGID kill
│   │   │   ├── git_wrapper.rs      # std::process::Command wrappers for git CLI
│   │   │   ├── worktree_manager.rs # Worktree create/remove/prune, conflict resolution
│   │   │   ├── mcp_monitor.rs      # Poll /tmp/maestro/agents/ every 500ms
│   │   │   ├── config_pipeline.rs  # CLAUDE.md generation, .mcp.json, .gemini/settings.json
│   │   │   ├── skill_manager.rs    # Scan, discover, per-worktree symlink injection
│   │   │   ├── command_manager.rs  # Command discovery, ${CLAUDE_PLUGIN_ROOT} substitution
│   │   │   ├── hook_manager.rs     # Hook aggregation, settings.local.json merging
│   │   │   ├── marketplace.rs      # Clone repos, parse manifests, install plugins
│   │   │   ├── dev_server.rs       # Dev server detection (regex stdout), port tracking
│   │   │   ├── port_allocator.rs   # Port range 3000-3099, /proc/net/tcp scanning
│   │   │   ├── log_manager.rs      # Per-session ring buffer + file logging
│   │   │   └── orphan_detector.rs  # Find/kill orphaned AI agents (PPID=1)
│   │   └── models/                 # Shared Structs (Serde)
│   │       ├── mod.rs
│   │       ├── session.rs          # SessionInfo, SessionConfig, GridConfiguration
│   │       ├── workspace.rs        # WorkspaceState, ProjectTab, ActiveTab
│   │       ├── git_types.rs        # Commit, Branch, GraphNode, GraphEdge
│   │       ├── agent_state.rs      # AgentState enum + struct
│   │       ├── plugin.rs           # MarketplacePlugin, InstalledPlugin, SkillConfig
│   │       ├── quick_action.rs     # QuickAction, TemplatePreset
│   │       └── dev_server.rs       # ManagedProcess, ServerStatus
│   └── bin/                        # Auxiliary Binaries
│       └── maestro-mcp.rs          # Standalone MCP Server (sidecar, spawned by agents)
├── src/                            # REACT FRONTEND
│   ├── App.tsx                     # Root layout: Sidebar + Main content area
│   ├── main.tsx                    # React entry point
│   ├── components/
│   │   ├── terminal/
│   │   │   ├── TerminalGrid.tsx    # Dynamic grid layout (1-12 sessions)
│   │   │   └── TerminalView.tsx    # Single xterm.js instance + status pill
│   │   ├── git/
│   │   │   ├── GitGraph.tsx        # Canvas rail renderer
│   │   │   ├── CommitRow.tsx       # DOM commit node + metadata
│   │   │   ├── CommitDetail.tsx    # Diff-tree panel overlay
│   │   │   └── BranchList.tsx      # Local/Remote branch list with ahead/behind
│   │   ├── sidebar/
│   │   │   ├── Sidebar.tsx         # Main sidebar container (Config + Processes tabs)
│   │   │   ├── SessionConfig.tsx   # Mode/branch assignment per cell
│   │   │   ├── PresetSelector.tsx  # Save/load terminal layouts
│   │   │   ├── QuickActions.tsx    # Quick action buttons + CRUD
│   │   │   ├── PluginBrowser.tsx   # Marketplace UI
│   │   │   ├── SkillSelector.tsx   # Toggle skills/commands per session
│   │   │   ├── ClaudeDocEditor.tsx # CLAUDE.md viewer/editor
│   │   │   ├── McpStatusPanel.tsx  # MCP server status display
│   │   │   ├── ThemeSwitcher.tsx   # Terminal theme picker
│   │   │   ├── ProcessesTab.tsx    # Agent status cards + dev servers
│   │   │   └── OrphanCleanup.tsx   # Orphaned process management UI
│   │   └── shared/
│   │       ├── StatusPill.tsx      # Agent status indicator
│   │       ├── ProjectTabs.tsx     # Project/workspace tab bar
│   │       └── PreLaunchView.tsx   # Project path selection + setup
│   ├── lib/
│   │   ├── git-layout.ts          # PORTED: GraphLayoutEngine.swift (TypeScript)
│   │   ├── pty-client.ts          # Xterm <-> Tauri IPC bridge
│   │   └── tauri-api.ts           # Typed wrappers around invoke() calls
│   ├── stores/
│   │   ├── useSessionStore.ts     # Session state (Zustand)
│   │   ├── useGitStore.ts         # Git data + graph state (Zustand)
│   │   └── usePluginStore.ts      # Plugins, skills, commands (Zustand)
│   └── styles/
│       └── globals.css            # Tailwind directives + terminal themes
├── package.json
├── tsconfig.json
├── tailwind.config.ts
└── vite.config.ts
```

---

## 4. Rust Backend Architecture

### 4.1 Process Manager (`core/process_manager.rs`)

**Replaces:** Swift `ProcessRegistry` + `ProcessLauncher`

```rust
pub struct ProcessManager {
    ptys: DashMap<String, Box<dyn portable_pty::MasterPty + Send>>,
    children: DashMap<String, ProcessInfo>,  // SessionID -> ProcessInfo
}

pub struct ProcessInfo {
    pid: u32,
    pgid: u32,                    // Process Group ID for tree kill
    port: Option<u16>,            // Detected dev server port
    dev_server_url: Option<String>, // Detected localhost URL
    source: String,               // "shell", "claude", "dev-server", etc.
    command: String,              // Original command that spawned this
    working_dir: PathBuf,         // CWD at spawn time
}
```

**Critical — Process Groups (Linux):**
```rust
fn spawn_session(shell: &str, cwd: &Path) -> Result<ProcessInfo> {
    let pair = portable_pty::native_pty_system().openpty(PtySize { rows: 24, cols: 80, .. })?;
    let mut cmd = CommandBuilder::new(shell);
    cmd.args(&["-l", "-i"]);
    cmd.cwd(cwd);
    // setsid() creates new process group — crucial for clean tree kill
    unsafe {
        cmd.pre_exec(|| { libc::setsid(); Ok(()) });
    }
    let child = pair.slave.spawn_command(cmd)?;
    // Store PID and PGID (== PID after setsid)
    Ok(ProcessInfo { pid: child.process_id(), pgid: child.process_id(), .. })
}
```

**Kill session:** `kill(-pgid, SIGTERM)` — negative PID kills entire process group.

**Dev Server Detection:**
- Spawn a background task per session reading PTY output.
- Regex scan for `localhost:\d+`, `127.0.0.1:\d+`, `0.0.0.0:\d+`.
- On match: update `ProcessInfo.dev_server_url`, emit event to frontend.
- Frontend shows "Open in Browser" button.

### 4.2 Git Wrapper (`core/git_wrapper.rs`)

**Replaces:** Swift `GitManager`

**Philosophy:** Use `std::process::Command` wrapping the system `git` binary. Do NOT use `git2-rs`. This ensures compatibility with user's git config, hooks, credentials, and SSH keys.

**Commands:**
- `get_log_graph(repo: &str, offset: usize, limit: usize)` — Runs `git log --all --topo-order --format="%H|%h|%s|%an|%ae|%aI|%P|%D" -n {limit} --skip={offset}`. Returns parsed `Vec<Commit>`.
- `get_branches(repo: &str)` — Runs `git for-each-ref --format="%(refname:short)|%(objectname:short)|%(upstream:track)|%(upstream:short)" refs/heads refs/remotes`. Parses ahead/behind counts.
- `checkout_branch(repo: &str, branch: &str)` — `git checkout {branch}`.
- `create_branch(repo: &str, name: &str)` — `git branch {name}`.
- `diff_tree(repo: &str, hash: &str)` — `git diff-tree --name-status -r {hash}`. Returns file list + status for the detail panel.
- `get_current_branch(repo: &str)` — `git rev-parse --abbrev-ref HEAD`.

All commands run via `tokio::process::Command` on Tauri's async thread pool.

### 4.3 Worktree Manager (`core/worktree_manager.rs`)

**Replaces:** Swift `WorktreeManager`

**State:** `Mutex<HashMap<String, WorktreeInfo>>` (SessionID -> WorktreeInfo)

**Branch Sanitization:** Replace `/\:*?"<>|` with `-` in branch names for filesystem paths.

**Creation Flow:**
1. Compute path: `~/.local/share/maestro/worktrees/{sha256(repo_path)}/{sanitized_branch}`
2. Check if worktree already exists for this branch (reuse if so)
3. Check if main repo has this branch checked out:
   - **Yes (conflict):** Run `git -C {main_repo} checkout {default_branch}` to release the lock
4. Run `git worktree add {path} {branch}`
5. Return worktree path as the session's working directory

**Cleanup Flow:**
- Session close: `git worktree remove --force {path}` + `rm -rf {path}`
- App launch: `git worktree prune` on all known repos + scan and remove orphan directories

### 4.4 Config Pipeline (`core/config_pipeline.rs`)

**Replaces:** Swift `ClaudeDocManager` + session setup logic

Before launching the AI in a worktree, Maestro must configure the environment:

1. **CLAUDE.md Generation:**
   - Generate a `CLAUDE.md` in the worktree root with session-specific context:
     - Project path (worktree directory)
     - Branch name
     - Session ID
     - Detected run command (see below)
     - Assigned port
     - Path to maestro-mcp sidecar binary
     - List of enabled skills for this session
   - If the main repo has a different `CLAUDE.md`, append its content below (inheritance).
   - **Run-Command Detection:** Heuristic scanning of the worktree root to auto-detect the project's run command:
     - `package.json` -> `npm run dev` / `npm start`
     - `Cargo.toml` -> `cargo run`
     - `Package.swift` -> `swift run`
     - `pyproject.toml` -> `python -m pytest`
     - `requirements.txt` -> `python main.py`
     - `Makefile` -> `make run`
     - `go.mod` -> `go run .`

2. **.mcp.json Configuration:**
   - Write `.mcp.json` to the worktree root pointing to the maestro-mcp sidecar binary.
   - Include session-specific configuration (session ID, port range).

3. **Gemini/Codex Config:**
   - `.gemini/settings.json` — Configure Gemini behavior if mode is Gemini.
   - `~/.codex/config.toml` — Configure Codex behavior if mode is Codex.
   - On startup: configure context files (CLAUDE.md/AGENTS.md) for Codex/Gemini modes.
   - Clean orphaned Codex MCP sections from previous sessions.

### 4.5 Skill Manager (`core/skill_manager.rs`)

**Replaces:** Swift `SkillManager`

**Discovery Locations (scanned in order):**
1. `~/.claude/skills/` — User's personal skills
2. Installed marketplace plugins (from persisted `installedPlugins`, regardless of path)
3. `~/.claude/plugins/*/skills/` — Skills from installed plugins
4. `{project}/.claude/skills/` — Project-local skills

**Skill Definition:** `SKILL.md` files with YAML frontmatter:
```yaml
---
name: "Run Tests"
description: "Execute the project test suite"
allowed-tools: "Bash, Read"
argument-hint: "test file path"
---
[Markdown prompt body]
```

**Per-Worktree Injection (NOT global):**
- `sync_worktree_skills(worktree: &Path, session_id: u32, enabled_skills: &[String])`
- Creates symlinks in `{worktree}/.claude/skills/` pointing to enabled skill files.
- Allows per-session skill toggling without modifying the global environment.

### 4.6 Command Manager (`core/command_manager.rs`)

**Replaces:** Swift `CommandManager`

**Discovery:** Same 3-tier scan as skills (`~/.claude/commands`, plugins, project).

**Session Injection:**
- If command file contains `${CLAUDE_PLUGIN_ROOT}`:
  - Read file content
  - Substitute variable with absolute path of the source plugin
  - **Write a copy** (not symlink) to `{worktree}/.claude/commands/`
- Otherwise: Create a **symbolic link**

### 4.7 Hook Manager (`core/hook_manager.rs`)

**Replaces:** Swift `HookManager`

**Discovery:** Scans `hooks/hooks.json` in each installed plugin.

**Event Types:** `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreCompact`, `Notification`

**Session Injection:**
- `sync_worktree_hooks(worktree: &Path, session_id: u32, enabled_plugins: &[String])`
- Reads/creates `{worktree}/.claude/settings.local.json`
- **Merges** hooks from all enabled plugins for that session
- Resolves `${CLAUDE_PLUGIN_ROOT}` in command/prompt strings before writing

### 4.8 Marketplace Manager (`core/marketplace.rs`)

**Replaces:** Swift `MarketplaceManager`

**Source Types:**
- **Official:** Anthropic's curated list (hardcoded URL)
- **Marketplace:** 3rd-party Git repos containing `.claude-plugin/marketplace.json` or `plugins.json`
- **Local:** User-specified filesystem paths

**Plugin Structure (expected in cloned repos):**
```text
plugin-name/
├── commands/         # .md command definitions
├── skills/           # SKILL.md files (or root SKILL.md)
├── hooks/
│   └── hooks.json    # Lifecycle event handlers
└── .mcp.json         # Custom MCP server config (optional)
```

**Manifest Parsing:** Support both object and array forms of `.claude-plugin/marketplace.json` or `plugins.json`. Build plugin catalog with types, tags, and metadata.

**Install Scopes:**
- **User:** `~/.claude/plugins/{plugin-id}` — available to all projects
- **Project:** `{project}/.claude/plugins/{plugin-id}` — scoped to one project
- **Local:** `{project}/.claude.local/plugins/{plugin-id}` — local-only, not committed to git

**Installation Flow:**
1. Fetch and parse remote manifest (object or array form)
2. Clone repo to `~/.claude/plugins/marketplaces/{repo-name}/`
3. Record install scope (user/project/local) and ensure scope directory exists
4. Use marketplace clone (or external clone) as the **source path** for the installed plugin
5. Create command discovery symlink under `~/.claude/plugins/{pluginName}` when commands exist
6. Discover skills/commands/hooks/MCP servers from source path
7. Persist installed plugin records in store.json; rescan skills/commands on load

### 4.9 MCP Sidecar (`bin/maestro-mcp.rs`)

**Replaces:** Swift `MaestroMCPServer`

**Nature:** Separate binary compiled alongside the main app. Spawned by AI agents as an MCP tool.

**Transport:** JSON-RPC 2.0 over stdio (stdin/stdout). Logs to stderr.

**Exposed Tools:**
1. `maestro_status` — Report agent status to Maestro (canonical, cross-platform)

**Status Writing:** Each `maestro_status` call writes to `/tmp/maestro/agents/agent-{session_id}.json`.

### 4.10 MCP Monitor (`core/mcp_monitor.rs`)

**Replaces:** Swift `MaestroStateMonitor`

**Triple-Source Status Detection:**
The macOS app uses 3 detection methods, prioritized:

1. **MCP File (Primary):** Poll `/tmp/maestro/agents/` every 500ms. Parse JSON for canonical state.
2. **Terminal Output Heuristics (Fallback):** If no MCP file or file is stale:
   - Regex scan PTY output for patterns: `(y/n)`, `Error:`, `✓`, `Compiling...`
   - Map to states: `needs_input`, `error`, `finished`, `working`
3. **Process Activity Monitor:** If state appears idle:
   - Check CPU/IO deltas via `sysinfo` crate
   - Prevent false idle detection when process is actually computing

**Emit:** Tauri event `agent-status-update` with `{ sessionId, state, message }`.

### 4.11 Log Manager (`core/log_manager.rs`)

**Per-Session Logging:**
- In-memory ring buffer per session (max 1000 lines) for fast UI access
- File-based persistent log at `~/.local/share/maestro/logs/session-{id}.log`
- Frontend: auto-scroll, log-level filters, search within session output
- Logs captured from both PTY output and dev server stdout/stderr

### 4.12 Orphan Detector (`core/orphan_detector.rs`)

**Runs on app startup and periodically:**
- Scan processes with PPID=1 (orphaned) matching AI agent path patterns:
  - `~/.local/share/claude/versions/*`
  - Binary names: `claude`, `gemini`, `codex`
- Present list in UI with "Kill All" and per-process "Kill" actions
- Also detects orphaned worktree directories and stale agent status files

### 4.13 Port Allocator (`core/port_allocator.rs`)

**Replaces:** Swift `NativePortManager`

- Allocates ports in range 3000-3099 per session (plus awareness of common dev ports: 5173, 8000, 8080, 4200)
- Tracks which ports are assigned to which sessions
- On Linux: read `/proc/net/tcp` to check port availability (replaces macOS `lsof`)
- Provides "Run App" hints based on detected project type + allocated port

---

## 5. React Frontend Architecture

### 5.1 Application Layout

```
┌──────────────────────────────────────────────────────┐
│  App.tsx                                             │
│  ┌──────────────┬───────────────────────────────────┐│
│  │ Sidebar      │  Main Content Area                ││
│  │ [Config|Proc]│  ┌────────────────────────────────┐││
│  │              │  │  ProjectTabs (workspace)       │││
│  │ Config Tab:  │  │  PreLaunchView (setup)         │││
│  │  Presets     │  │  OR                            │││
│  │  Sessions    │  │  TerminalGrid (active)         │││
│  │  Sessions    │  │  ┌──────┬──────┬──────┐       │││
│  │  Git Info    │  │  │ T1   │ T2   │ T3   │       │││
│  │  CLAUDE.md   │  │  ├──────┼──────┼──────┤       │││
│  │  MCP Status  │  │  │ T4   │ T5   │ T6   │       │││
│  │  Marketplace │  │  └──────┴──────┴──────┘       │││
│  │  Quick Acts  │  │  Session headers:              │││
│  │  Theme       │  │  [status] [mode] [branch] [x] │││
│  │              │  └────────────────────────────────┘││
│  │ Processes:   │                                    ││
│  │  Agent Cards │                                    ││
│  │  Dev Servers │                                    ││
│  │  Output Logs │                                    ││
│  │  Orphans     │                                    ││
│  └──────────────┴───────────────────────────────────┘│
└──────────────────────────────────────────────────────┘
```

**Sidebar Tabs:**
- **Config Tab:** Presets, terminal count, sessions list, status overview, Git info, CLAUDE.md editor, MCP status panel, marketplace browser, quick actions, theme switcher
- **Processes Tab:** Agent status cards, dev server list with start/stop/restart, output streams with filters, orphaned process cleanup UI

**Main Grid Session Headers:** Each terminal cell has a header bar with: status indicator, mode picker, branch picker, quick action buttons, close button. Multi-select mode for batch operations (disabled while running).

### 5.2 Git Graph Layout Engine (`lib/git-layout.ts`)

**Direct port of:** `GraphLayoutEngine.swift`

**Input:** `Commit[]` (hash, parents[], refs[])
**Output:** `GraphNode[]` with `columnIndex` + `GraphEdge[]` with Bezier control points

**Algorithm:**
1. Process commits newest-to-oldest (topological order)
2. Track "Active Rails" — column indices occupied by branch lines
3. **Placement rules:**
   - If commit is expected parent in Column X -> place in Column X
   - If merge (multiple parents) -> first parent stays, others get new columns
   - If no active rail waiting -> take first free column index
4. **Connection types:** `straight`, `mergeLeft`, `mergeRight`, `offScreen` (dashed)
5. **Coloring:** 8-color palette: `railColors[columnIndex % 8]`
   - Cyan, Red, Green, Orange, Purple, Pink, Olive, Lavender

**Node Rendering (DOM, not Canvas):**
- Filled circle: Normal commit
- Hollow center: Merge commit
- Double ring: HEAD commit
- Thick border: Selected commit

**Virtualization:** `@tanstack/react-virtual` for infinite scroll (batches of 50 commits).

### 5.3 Terminal Component (`components/terminal/TerminalView.tsx`)

**Props:** `sessionId`, `fontFamily`, `theme`

**Data Flow:**
- **In (PTY -> Terminal):** Listen to Tauri event `pty-output://{sessionId}`. Call `term.write(data)`.
- **Out (Terminal -> PTY):** `term.onData(data => invoke('write_stdin', { sessionId, data }))`.
- **Resize:** `term.onResize(({ rows, cols }) => invoke('resize_pty', { sessionId, rows, cols }))`.
- **Status Pill:** Subscribe to `agent-status-update` events. Display colored indicator.

**Addons:** `xterm-addon-fit` (auto-resize), `xterm-addon-web-links` (clickable URLs).

### 5.4 Grid Layout (`components/terminal/TerminalGrid.tsx`)

**Static calculation** based on session count:
- 1 session: 1x1
- 2 sessions: 1x2
- 3 sessions: 1x3
- 4 sessions: 2x2
- 5-6 sessions: 2x3
- 7-9 sessions: 3x3
- 10-12 sessions: 3x4

### 5.5 State Management (Zustand)

**`useWorkspaceStore`:**
- `projects: ProjectTab[]` (each has projectPath, sessions[], gitState, plugins)
- `activeProjectId: string`
- Actions: `openProject`, `closeProject`, `setActiveProject`

**`useSessionStore`:**
- `sessions: SessionInfo[]` (scoped to active project tab)
- `gridConfig: { rows, cols }`
- Actions: `createSession`, `closeSession`, `batchAssign`, `resetAll` (within active project)

**`useGitStore`:**
- `commits: Commit[]`
- `branches: Branch[]`
- `currentBranch: string`
- `selectedCommit: Commit | null`
- Actions: `loadCommits`, `loadMore`, `checkout`, `createBranch`

**`usePluginStore`:**
- `installedPlugins: InstalledPlugin[]`
- `availableSkills: SkillConfig[]`
- `sessionSkills: Map<string, string[]>` (per-session enabled skills)
- Actions: `installPlugin`, `toggleSkill`, `syncSession`

---

## 6. Critical Workflows

### 6.0 Project Tabs (Workspace)
1. **User:** Opens a new project folder (File → Open / "+" tab)
2. **Frontend:** `invoke('open_project', { path })`
3. **Rust:** Validate repo, load git state, initialize project tab, persist to store.json
4. **Frontend:** Add new tab, switch active project, render grid for that project only

### 6.1 Session Creation (Full Pipeline)

1. **User:** Clicks "New Session" in active project tab — selects Mode (Claude) and Branch (feature/login)
2. **Frontend:** `invoke('create_session', { projectId, mode: 'claude', branch: 'feature/login' })`
3. **Rust — Worktree:**
   - Check if branch is checked out in main repo → conflict resolution
   - `git worktree add ~/.local/share/maestro/worktrees/{hash}/{branch} feature/login`
4. **Rust — Config Pipeline:**
   - Generate `CLAUDE.md` in worktree (inherit from main repo if different)
   - Write `.mcp.json` pointing to maestro-mcp sidecar binary
   - If Gemini mode: write `.gemini/settings.json`
   - If Codex mode: update `~/.codex/config.toml` with session MCP section
5. **Rust — Skill/Command/Hook Injection:**
   - Symlink enabled skills to `{worktree}/.claude/skills/`
   - Copy/symlink enabled commands to `{worktree}/.claude/commands/`
   - Merge hooks into `{worktree}/.claude/settings.local.json`
6. **Rust — Process:**
   - Spawn `/bin/zsh -l -i` (or user's shell) with `setsid()` in worktree directory
   - Store PID/PGID in ProcessManager
   - Inject commands via stdin with `\r` (carriage return): `cd {worktree}\r`, then `claude\r` (or gemini/codex)
   - Shell stays alive after CLI exits (user can re-launch or use terminal manually)
7. **Rust -> Frontend:** Return `SessionInfo` with ID, emit PTY output stream
8. **Frontend:** Mount `TerminalView`, subscribe to events

### 6.2 Agent Status Monitoring

1. **Agent (in PTY):** AI tool configured with maestro-mcp as MCP server
2. **MCP Sidecar:** Writes `{ "state": "working", "message": "Compiling..." }` to `/tmp/maestro/agents/agent-{id}.json`
3. **Rust Monitor:** Background tokio task polls every 500ms
4. **Fallback:** If no MCP file, scan terminal output for heuristic patterns
5. **Activity Check:** If idle, verify via CPU/IO delta (sysinfo crate)
6. **Emit:** `agent-status-update` event -> Frontend updates status pill

### 6.3 Session Teardown

1. **User:** Closes session (or closes app)
2. **Rust:** Send `SIGTERM` to process group (`kill(-pgid, SIGTERM)`)
3. **Rust:** Wait brief grace period, then `SIGKILL` if still alive
4. **Rust:** `git worktree remove --force {path}` + `rm -rf {path}`
5. **Rust:** Remove agent status file from `/tmp/maestro/agents/`
6. **Rust:** Release allocated port
7. **Frontend:** Remove terminal component, update grid layout

### 6.4 App Startup (Orphan Cleanup)

1. Run `git worktree prune` on all known repos
2. Scan `/tmp/maestro/agents/` — remove stale files (> 5 min)
3. Scan for orphaned processes (PIDs from previous session that are still running)
4. Kill orphaned processes
5. Remove orphaned worktree directories

---

## 7. Data Models (Serde Structs)

### Rust Models

```rust
// session.rs
pub struct SessionInfo {
    pub id: u32,                 // 1..N session ID (matches agent-<id>)
    pub mode: TerminalMode,      // Claude, Gemini, Codex, Shell
    pub branch: Option<String>,
    pub working_dir: PathBuf,    // Worktree path
    pub pid: Option<u32>,
    pub pgid: Option<u32>,
    pub port: Option<u16>,
    pub status: SessionStatus,   // Idle, Working, Error, Done
    pub is_terminal_launched: bool, // Shell spawned?
    pub is_cli_launched: bool,      // AI command injected?
    pub visible: bool,
    pub theme: Option<String>,      // Per-session terminal theme
    pub font_family: Option<String>, // Per-session font override
}

pub struct SessionConfig {
    pub mode: TerminalMode,
    pub branch: Option<String>,
    pub enabled_skills: Vec<String>,
    pub enabled_commands: Vec<String>,
}

pub struct SessionConfiguration {
    pub mode: TerminalMode,
    pub branch: Option<String>,
}

pub struct ProjectTab {
    pub id: String,              // stable ID for the project tab
    pub project_path: PathBuf,
    pub sessions: Vec<SessionInfo>,
    pub active: bool,
}

pub struct WorkspaceState {
    pub projects: Vec<ProjectTab>,
    pub active_project_id: Option<String>,
}

pub enum TerminalMode { Claude, Gemini, Codex, Shell }
pub enum SessionStatus { Idle, Working, NeedsInput, Error, Finished }

// git_types.rs
pub struct Commit {
    pub hash: String,
    pub short_hash: String,
    pub subject: String,
    pub author_name: String,
    pub author_email: String,
    pub date: String,            // ISO 8601
    pub parents: Vec<String>,
    pub refs: Vec<String>,       // Branch/tag decorations
}

pub struct Branch {
    pub name: String,
    pub is_remote: bool,
    pub commit_hash: String,
    pub ahead: u32,
    pub behind: u32,
    pub upstream: Option<String>,
}

// agent_state.rs
pub struct AgentState {
    pub agent_id: String,
    pub state: AgentStatus,
    pub message: String,
    pub needs_input_prompt: Option<String>,
    pub timestamp: String,       // ISO 8601 (with optional fractional seconds)
}

pub enum AgentStatus { Idle, Working, NeedsInput, Finished, Error }

// plugin.rs
pub struct MarketplacePlugin {
    pub id: String,
    pub name: String,
    pub description: String,
    pub repo_url: String,
    pub author: String,
    pub version: String,
    pub source_type: SourceType,  // Official, Marketplace, Local
}

pub struct InstalledPlugin {
    pub id: String,
    pub name: String,
    pub install_path: PathBuf,
    pub skills: Vec<SkillConfig>,
    pub commands: Vec<CommandConfig>,
    pub has_hooks: bool,
    pub has_mcp: bool,
}

pub struct SkillConfig {
    pub name: String,
    pub description: String,
    pub allowed_tools: Vec<String>,
    pub argument_hint: Option<String>,
    pub file_path: PathBuf,
    pub source: SkillSource,        // Attribution: where this skill came from
}

pub enum SkillSource {
    Personal,                       // ~/.claude/skills/
    Plugin(String),                 // Plugin ID that provided it
    Project,                        // {project}/.claude/skills/
}

pub struct CommandConfig {
    pub name: String,
    pub description: String,
    pub file_path: PathBuf,
    pub has_plugin_root_var: bool,  // Contains ${CLAUDE_PLUGIN_ROOT}?
    pub source: SkillSource,        // Same attribution enum
}

// quick_action.rs
pub struct QuickAction {
    pub id: String,
    pub name: String,
    pub icon: String,            // SF Symbol name from macOS (map to Linux icon set)
    pub color_hex: String,
    pub prompt: String,
    pub is_enabled: bool,
    pub sort_order: u32,
    pub created_at: String,      // ISO 8601
}

pub struct TemplatePreset {
    pub id: String,
    pub name: String,
    pub configs: Vec<SessionConfiguration>,
    pub created_at: String,      // ISO 8601
    pub last_used: Option<String>, // ISO 8601, for sorting recents
}

// dev_server.rs
pub struct ManagedProcess {
    pub session_id: u32,
    pub pid: u32,
    pub port: u16,
    pub command: String,
    pub status: DevServerStatus,
    pub url: String,
}

pub enum DevServerStatus { Starting, Running, Stopped, Error }
```

---

## 8. Linux Parity Checklist

Verified, gap-free checklist based on macOS source analysis + validation.

### Paths & Storage
- [ ] Worktrees at `~/.local/share/maestro/worktrees/<sha256>/<sanitized-branch>`
- [ ] App persistence at `~/.config/maestro/store.json`
- [ ] Agent status at `/tmp/maestro/agents/`
- [ ] Logs at `~/.local/share/maestro/logs/session-<id>.log`
- [ ] Plugins at `~/.claude/plugins/` (symlinks)
- [ ] Marketplaces at `~/.claude/plugins/marketplaces/`

### Session & Grid Lifecycle
- [ ] Session model: ID, Status, Mode, Branch, WorkingDir, Port, PID, PGID, Visibility
- [ ] Grid: 1-12 sessions, static row/col calculation
- [ ] Workspace tabs: multiple open projects with per-tab session grids
- [ ] Project path change triggers full reset (stop monitors, kill processes, clean worktrees)
- [ ] Batch operations: multi-select mode/branch assignment (when not running)

### Terminal & CLI Launch
- [ ] PTY via `portable-pty` + `xterm.js` frontend
- [ ] Copy/paste, text selection, and context menu
- [ ] Per-session theme and font family support
- [ ] Shell: Spawn `/bin/zsh -l -i` (or user shell) then inject `cd worktree\r` + AI command `\r`
- [ ] Shell stays alive after CLI exits (user can re-launch or use terminal manually)
- [ ] AI Modes: `claude`, `gemini`, `codex`, `shell`
- [ ] Binary detection via login shell `which` before launch; surface warning if missing
- [ ] Track `is_terminal_launched` and `is_cli_launched` as separate flags

### Config Pipeline (Per-Worktree)
- [ ] Generate `CLAUDE.md` per worktree with: project path, branch, session ID, run command, port, MCP path, skills list
- [ ] Auto-detect run command (package.json, Cargo.toml, pyproject.toml, Makefile, go.mod, etc.)
- [ ] Inherit/append main repo `CLAUDE.md` if different
- [ ] Write `.mcp.json` with maestro-mcp sidecar config
- [ ] Write `.gemini/settings.json` for Gemini mode
- [ ] Write `~/.codex/config.toml` for Codex mode
- [ ] Configure CLAUDE.md/AGENTS.md context files for Codex/Gemini modes on startup
- [ ] Clean orphaned Codex MCP sections from previous sessions

### Agent Status & Activity (Triple-Source)
- [ ] Primary: MCP file polling (`/tmp/maestro/agents/`, 500ms)
- [ ] Fallback: Terminal output heuristics (regex patterns)
- [ ] Guard: CPU/IO activity monitor (prevent false idle)
- [ ] Sound notification on `finished` state transition
- [ ] Stale file pruning (> 5 min)

### Worktree & Branching
- [ ] Branch name sanitization (`/\:*?"<>|` -> `-`)
- [ ] Conflict resolution (force main repo to default branch)
- [ ] `git worktree remove --force` on session close
- [ ] `git worktree prune` on app launch
- [ ] Orphan directory cleanup

### Git Operations & Graph
- [ ] System `git` CLI (no libgit2); repo detection via `git rev-parse --git-dir`
- [ ] `git log --all --topo-order --format="%H|%h|%s|%an|%ae|%aI|%P|%D"`
- [ ] `git for-each-ref` with `%(upstream:track)` for ahead/behind
- [ ] `git diff-tree --name-status` for commit detail panel
- [ ] Commit actions: checkout commit, create branch from commit
- [ ] Remote branch selection and branch creation with base branch choice
- [ ] Remote connectivity check via `git ls-remote --heads`
- [ ] Status via `git status --porcelain`; user name/email via `git config`
- [ ] Topological sort + rail-based layout engine (TypeScript)
- [ ] HTML5 Canvas for rails + DOM for nodes
- [ ] Infinite scroll with `@tanstack/react-virtual` (batches of 50)

### Plugins, Skills, Commands, Hooks
- [ ] 3-tier discovery: user global, plugins, project-local (retain source attribution per item)
- [ ] Per-session enablement: skills/commands opt-in per session; resync on toggle
- [ ] Per-session skill injection via symlinks to worktree
- [ ] Command injection with `${CLAUDE_PLUGIN_ROOT}` substitution
- [ ] Hook aggregation into `.claude/settings.local.json`
- [ ] Hook event types: PreToolUse, PostToolUse, Stop, SubagentStop, SessionStart, SessionEnd, UserPromptSubmit, PreCompact, Notification

### Marketplace
- [ ] Source types: Official, Marketplace (3rd-party git), Local
- [ ] Parse remote manifests in both object and array form
- [ ] Build plugin catalog with types, tags, metadata
- [ ] Clone to `~/.claude/plugins/marketplaces/`
- [ ] Install scopes: user (`~/.claude/plugins/`), project (`.claude/plugins/`), local (`.claude.local/plugins/`)
- [ ] On install: discover skills/commands/MCP servers; create symlink
- [ ] Persist installed plugin records; rescan on load
- [ ] Plugin CRUD in UI

### Quick Actions & Presets
- [ ] QuickAction: id, name, icon (SF Symbol name), colorHex, prompt, isEnabled, sortOrder, createdAt
- [ ] Default seeds: "Run App", "Commit & Push", "Fix Errors", "Lint & Format" (keep default prompts intact)
- [ ] Execute by injecting prompt into terminal; keep shell alive for follow-ups
- [ ] TemplatePreset: id, name, sessionConfigurations (mode + branch), createdAt, lastUsed
- [ ] Applying a preset resets sessions to its config and updates terminal count
- [ ] Persist in `store.json`

### Dev Server Management
- [ ] Dev server lifecycle controlled by app (Tauri commands), not via MCP sidecar
- [ ] Port allocation: 3000-3099 range
- [ ] Port scanning via `/proc/net/tcp`
- [ ] Dev server URL detection via terminal output regex
- [ ] "Open in Browser" button on URL detection
- [ ] Project type detection (package.json, Cargo.toml heuristics)

### Process & Orphan Management
- [ ] Track PID, PGID, source, command, working_dir per session
- [ ] `setsid()` on spawn for process group isolation
- [ ] `kill(-pgid, SIGTERM)` for clean session teardown
- [ ] Grace period -> `SIGKILL` escalation
- [ ] Orphan detection: find AI agents by PPID=1 and path patterns (claude, gemini, codex binaries)
- [ ] UI for "Kill All" orphans and per-process "Kill" actions

### Logging
- [ ] Per-session in-memory ring buffer (max 1000 lines)
- [ ] Per-session file log at `~/.local/share/maestro/logs/session-{id}.log`
- [ ] UI: auto-scroll, log-level filters, search
- [ ] Capture from PTY output and dev server stdout/stderr

### UI Surface
- [ ] Sidebar: two tabs (Config + Processes)
- [ ] Config tab: presets, terminal count, sessions, status, git info, CLAUDE.md editor, MCP status, marketplace, quick actions, theme switcher
- [ ] Processes tab: agent status cards, dev server list, output streams with filters, orphan cleanup
- [ ] Project tab bar (VS Code-style) to switch between open repos
- [ ] Session headers: status indicator, mode picker, branch picker, quick actions, close button
- [ ] Multi-select batch actions for mode/branch (disabled while running)

---

## 9. Dependencies

### Cargo.toml
```toml
[dependencies]
tauri = { version = "2.0", features = ["process-command-api", "shell-open"] }
tauri-plugin-store = "2.0"
serde = { version = "1.0", features = ["derive"] }
serde_json = "1.0"
tokio = { version = "1", features = ["full"] }
portable-pty = "0.8"
dashmap = "5.5"
notify = "6.1"              # Filesystem watching (optional, for /tmp/maestro/agents)
libc = "0.2"                # setsid(), kill() with negative PID
regex = "1.10"              # Terminal output heuristics
uuid = { version = "1.6", features = ["v4"] }
sysinfo = "0.30"            # CPU/IO monitoring for activity detection
sha2 = "0.10"               # SHA256 for repo path hashing
dirs = "5.0"                # XDG base directory paths

[build-dependencies]
tauri-build = "2.0"

[[bin]]
name = "maestro-mcp"
path = "bin/maestro-mcp.rs"
```

### package.json
```json
{
  "dependencies": {
    "@tauri-apps/api": "^2.0.0",
    "@tauri-apps/plugin-store": "^2.0.0",
    "react": "^18.3.0",
    "react-dom": "^18.3.0",
    "@xterm/xterm": "^5.5.0",
    "@xterm/addon-fit": "^0.10.0",
    "@xterm/addon-web-links": "^0.11.0",
    "zustand": "^4.5.0",
    "@tanstack/react-virtual": "^3.8.0",
    "lucide-react": "^0.300.0",
    "framer-motion": "^11.0.0",
    "clsx": "^2.1.0",
    "tailwind-merge": "^2.2.0"
  },
  "devDependencies": {
    "@types/react": "^18.3.0",
    "@types/react-dom": "^18.3.0",
    "@tauri-apps/cli": "^2.0.0",
    "typescript": "^5.5.0",
    "vite": "^5.4.0",
    "@vitejs/plugin-react": "^4.3.0",
    "tailwindcss": "^3.4.0",
    "postcss": "^8.4.0",
    "autoprefixer": "^10.4.0"
  }
}
```

---

## 10. Implementation Phases

**Collaboration Note:** Documentation updates should be pushed to the `feature/tauri-cross-platform` branch.

### Phase 1: Foundation (Complete — 2026-01-31)
- Scaffold Tauri 2.0 project with React + TypeScript + TailwindCSS
- Implement ProcessManager (PTY spawn, setsid, basic I/O)
- Build TerminalView (single xterm.js instance)
- Establish Tauri Command + Event IPC pattern
- Result: One working terminal in a Tauri window

#### Phase 1.1 Implementation Status (Complete)
- Repo: https://github.com/lliWcWill/maestro-linux
- Branch: `phase-1.1-pty-ipc`
- PTY spawn/kill with PGID capture, bounded output channel, cwd validation, resize bounds
- xterm.js TerminalView + TerminalGrid with cleanup and error state
- Accessible ProjectTabs skeleton with open/close/select and PreLaunch flow
- CSP baseline for dev, plus general hardening fixes

#### Phase 1.2 (Complete — 2026-01-31)
- Added zustand workspace store with Tauri LazyStore persistence
- Implemented native folder picker via tauri-plugin-dialog
- Wired PreLaunch “Open Project” into store + ProjectTabs
- TerminalGrid now spawns shell with cwd=projectPath and remounts per active tab
- Dedup + close-tab behavior fixed and hardened

#### Phase 1.3 (Complete — 2026-01-31)
- Full UI restructure matching macOS Maestro layout parity
- Sidebar.tsx: 623-line Config tab (9 sections) + Processes tab (4 sections)
- TopBar.tsx: sidebar toggle, branch selector, StatusLegend, git fork, settings, window controls
- BottomBar.tsx: Select Directory + Launch/Stop All buttons
- SessionPodGrid.tsx: idle pod grid with breathing animations
- Theme system: dark/light toggle, CSS variables with RGB triplets, `.content-dark` override
- Auto-respawn logic in TerminalGrid when session dies
- 12 files changed, 1,054 insertions, 118 deletions
- CodeRabbit review completed (37 findings, 1 security, 11 potential issues, 25 nitpicks)

#### Phase 1.4 (Complete — 2026-01-31)
- **Phase 1.4A:** Terminal cell 3D styling (rounded, box-shadow, curved edges), TerminalHeader.tsx
  (rich per-session header), QuickActionPills.tsx, FloatingAddButton.tsx, IdleLandingView.tsx,
  GitGraphPanel.tsx placeholder, 4-state machine (no-project/project-idle/sessions-active),
  orange glow animation, status-dependent terminal borders
- **Phase 1.4B:** Sidebar drag-to-resize (180-320px), BottomBar state logic, TopBar icon reorder,
  window controls scaled down, Needs Input yellow fix, git panel width w-72
- **Phase 1.4C:** Terminal bg follows theme (removed .content-dark), blue+ capped at 6,
  git panel z-index fix, git panel full theme support
- **Phase 1.4D:** Seamless TopBar (no separator bar), 3D sidebar collapse button, GitMerge icon,
  BranchDropdown.tsx with keyboard nav and mock branches, BrainCircuit enriched to vibrant
  violet-500 with glow, StatusLegend boosted to Tailwind palette colors, TerminalHeader expanded
  with macOS anatomy placeholders (terminal count badge, blue checkmark, git arrows, gear icon)
- **Phase 1.4E:** CodeRabbit review fixes — addSession race condition (sessionsRef guard),
  auto-respawn cancellation guard, liveSessionCount reset on tab clear, explicit activeTab guard
  (removed non-null assertions), BranchDropdown keyboard scoping, Done status distinct green color,
  useOpenProject await fix
- 15 files changed, 840 insertions (Phase 1.4), 5 files changed, 37 insertions (Phase 1.4E)
- CodeRabbit review: 47 findings (1 security, 12 potential issues, 34 nitpicks)
- 7 high-priority issues fixed in 1.4E, 34 nitpicks deferred
- Sprint docs: `research/06` through `research/10`
- Commits: `64b333b` (Phase 1.4), `9a7a134` (Phase 1.4E)

### Phase 2: Session Grid & Worktrees (Complete — 2026-01-31, commit e7fcf51)
- Implemented SessionManager (AiMode, SessionStatus, SessionConfig) and session commands
- Implemented WorktreeManager (SHA256 repo hash, XDG worktree paths, prune/cleanup)
- Implemented Git CLI wrapper + ops (branches, current branch, uncommitted count, worktree CRUD, commit log)
- Wired BranchDropdown to real git branch data (replaced MOCK_BRANCHES)
- Wired TerminalHeader + StatusLegend to live session state
- Result: Session grid + worktree plumbing integrated with real git data

### Phase 3: Git Visualization
- Port GraphLayoutEngine.swift -> TypeScript
- Build GitGraph (Canvas rails + DOM nodes)
- Build CommitRow, CommitDetail, BranchList
- Implement infinite scroll with @tanstack/react-virtual
- Wire git log/diff-tree commands
- Result: Full git graph view with branch management

### Phase 4: Agent Intelligence
- Implement MCP Monitor (file polling)
- Implement terminal output heuristics (regex fallback)
- Implement activity monitor (CPU/IO guard)
- Build StatusPill component
- Build MCP Sidecar binary (maestro-mcp.rs)
- Implement config pipeline (CLAUDE.md, .mcp.json generation)
- Result: Real-time agent status monitoring

### Phase 5: Plugins & Marketplace
- Implement SkillManager, CommandManager, HookManager
- Per-worktree injection logic (symlinks, copies, ${CLAUDE_PLUGIN_ROOT})
- Implement MarketplaceManager (clone, parse, install)
- Build PluginBrowser, SkillSelector UI
- Result: Full plugin ecosystem

### Phase 6: Polish & Package
- Quick Actions (CRUD, default seeds, terminal injection)
- Template Presets (save/load layouts)
- Dev server detection + "Open Browser" button
- Port allocator
- Orphan cleanup on startup
- Sound notifications
- `.deb` package build via `tauri build`
- Result: Production-ready .deb package

---

## 11. Risk Register

- **PTY edge cases:** `portable-pty` on Linux may have edge cases with specific shells or terminal modes. Mitigation: test with bash, zsh, fish early.
- **WebKitGTK rendering:** Tauri on Linux uses WebKitGTK. xterm.js and Canvas rendering should work but need verification for performance with 12 simultaneous terminals. Mitigation: benchmark early in Phase 1.
- **Process group cleanup:** Zombie processes are the biggest operational risk. Mitigation: implement thorough startup cleanup, `SIGKILL` escalation, `/proc` scanning.
- **Git worktree limits:** Some Git versions have worktree bugs. Mitigation: document minimum git version requirement.
- **Plugin security:** Arbitrary plugin code execution via hooks is a security concern. Mitigation: sandbox hook commands, require user confirmation.

---

## 12. Packaging & Distribution

- **Build:** `tauri build` produces `.deb` package targeting Debian/Ubuntu
- **MCP Sidecar:** Bundled as a separate binary alongside the main app executable. The absolute path to the sidecar is used when generating `.mcp.json`, `.gemini/settings.json`, and `~/.codex/config.toml` per worktree.
- **Desktop Entry:** Include `.desktop` file with icon, categories, and exec path
- **Permissions:** Sidecar binary must have executable permissions in the package
- **MCP Contract:** Keep JSON-RPC contract identical to macOS (same `maestro_status` tool, same 5 states) for cross-platform compatibility of the sidecar binary
- **Migration Notes:** Document any path differences from macOS (`~/Library/Application Support/` -> `~/.config/maestro/`, `~/.claude-maestro/worktrees/` -> `~/.local/share/maestro/worktrees/`) for users running both platforms

---

*v3.2 — Final synthesis incorporating complete Linux parity checklist from Agent 2. Adds: marketplace install scopes (user, project, local), manifest object+array parsing, enriched QuickAction/TemplatePreset models (isEnabled, createdAt, lastUsed), ProcessInfo tracking (source, command, working_dir), log manager (ring buffer + file), orphan detector (PPID=1 + path patterns), detailed sidebar UI structure (Config + Processes tabs), session header spec, .deb packaging with desktop entry and sidecar permissions, MCP cross-platform contract. Synthesized from 3 source analysis reports + 2 cross-validation passes + complete parity checklist against the actual Swift codebase (18,500 lines, 50+ files).*
