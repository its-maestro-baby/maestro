This report breaks down the architecture of the Git visualization, worktree management, and user configuration subsystems within the `claude-maestro` macOS application. It analyzes the Swift implementation to provide a blueprint for a Tauri 2.x Linux port.

---

# 1. Git Graph Visualization

The application implements a custom "GitKraken-style" commit graph rather than using an off-the-shelf library. This visualization is split into data processing (`GitManager`), layout calculation (`GraphLayoutEngine`), and rendering (`GraphCanvas` + `CommitRowView`).

### How the Graph Layout is Computed
**Source:** `GraphLayoutEngine.swift`

The layout engine transforms a flat list of commits (fetched via `git log --topo-order`) into a set of nodes and "rails" (vertical columns).

1.  **Topological Sort:** Commits are processed newest to oldest.
2.  **Column Assignment (The "Rails"):**
    *   The engine tracks **Active Columns**—indices that are currently "occupied" by a branch line waiting to connect to a parent.
    *   **Placement Strategy:**
        *   If a commit is the expected parent of a previous node in Column X, it is placed in Column X.
        *   If a commit is a merge (has multiple parents), it forks. The first parent continues in the current column; subsequent parents are assigned new, free columns to the right.
        *   If a commit has no active column waiting for it (e.g., a new branch tip), it takes the first available free column index.
3.  **Connection Types:**
    *   `straight`: Vertical line (same column).
    *   `mergeLeft` / `mergeRight`: Bezier curves connecting a node in one column to a parent in another.
    *   `offScreen`: If a parent commit is not in the current batch of loaded commits, a dashed line is drawn to the bottom of the viewport.

### Rails and Colors
**Source:** `GraphLayoutEngine.swift`, `CommitGraph.swift`

*   **Rails:** A `Rail` is simply a visual abstraction for a column index (0, 1, 2...).
*   **Color Palette:** A hardcoded array of 8 pastel colors (Cyan, Red, Green, Orange, Purple, Pink, Olive, Lavender) is used.
*   **Assignment:** Colors are assigned deterministically based on the column index: `railColors[column_index % 8]`.

### Rendering
**Source:** `GraphCanvas.swift`, `CommitRowView.swift`

*   **Layered Approach:**
    1.  **Canvas Layer (Background):** `GraphCanvas` uses Swift's `Canvas` API to draw the lines (rails) and Bezier curves. This is separated from the text for performance.
    2.  **Row Layer (Foreground):** `CommitRowView` renders the commit node (circle) and text metadata.
*   **Nodes:** Circles are drawn with the specific `Rail` color.
    *   **Hollow Center:** Indicates a Merge Commit.
    *   **Double Ring:** Indicates the `HEAD` commit.
    *   **Thick Border:** Indicates the currently selected commit.

---

# 2. Git Tree View

**Source:** `GitTreeView.swift`, `GitManager.swift`

This is the orchestration layer that connects the data service to the visualization.

*   **Data Source (`GitManager`):**
    *   Runs `git log --all --topo-order --format="..." -n 50`.
    *   Parses a custom delimiter-separated format: `%H|%h|%s|%an|%ae|%aI|%P|%D`.
    *   Crucially, it parses `%D` (refs) to determine which branches/tags point to a specific commit.
*   **Pagination:** Implements "Infinite Scroll". It loads batches of 50 commits. When the user scrolls near the bottom, it triggers `loadMoreCommits()` with an offset.
*   **State Management:**
    *   Observes `GitManager.currentBranch` to auto-refresh when external changes occur.
    *   Manages `selectedCommit` to show the `CommitDetailPanel` overlay.

---

# 3. Branch Management

**Source:** `BranchVisualizationView.swift`, `Branch.swift`, `GitManager.swift`

### Branch Model
A `Branch` struct holds:
*   `name`: e.g., "main" or "feature/login".
*   `isRemote`: Boolean (detected by `origin/` prefix).
*   `aheadCount` / `behindCount`: Integers indicating sync status with upstream.
*   `commitHash`: The tip of the branch.

### Creation & Tracking
*   **Fetching:** `GitManager` runs `git for-each-ref` to get local and remote branches in one pass. It utilizes the `%(upstream:track)` format specifier to get "ahead 1, behind 2" strings automatically, which it parses into integers.
*   **Selection:**
    *   **Checkout:** `GitManager.checkoutBranch(name)` runs `git checkout`.
    *   **Creation:** `GitManager.createBranch` runs `git branch <name>`.
*   **UI:** Branches are split into "Local" and "Remote" lists. The current branch is highlighted with a green dot; others use gray (local) or blue (remote).

---

# 4. Worktree Management

**Source:** `WorktreeManager.swift`

This is a critical feature for the "Maestro" concept, allowing multiple agents to work on the same repo simultaneously without index locking conflicts.

### Workflow
1.  **Path Generation:** Worktrees are stored in `~/.claude-maestro/worktrees/<RepoHash>/<SanitizedBranchName>`.
2.  **Creation Logic:**
    *   When a session requests a branch, `WorktreeManager` checks if a worktree already exists.
    *   **Conflict Resolution:** If the *main* repository is currently checked out to the requested branch, `git worktree add` will fail (Git forbids two dirs checking out the same branch). The Manager handles this by forcing the main repo to switch to `defaultBranch` (or another random branch) to "release" the lock before creating the worktree.
3.  **Cleanup:**
    *   **Orphan Pruning:** On app launch, it runs `git worktree prune` to remove stale metadata.
    *   **Session Cleanup:** When a session ends, `removeWorktree` is called to delete the directory and run `git worktree remove`.

---

# 5. Quick Actions

**Source:** `QuickActionManager.swift`, `QuickAction.swift`

### Model & Storage
*   **Model:** `QuickAction` struct contains `id`, `name`, `icon` (SF Symbol name), `colorHex`, `prompt` (the actual LLM instruction), and `sortOrder`.
*   **Storage:** Serialized to JSON and stored in `UserDefaults` under key `claude-maestro-quick-actions`.
*   **Defaults:** On first launch, it seeds the storage with 4 hardcoded actions: "Run App", "Commit & Push", "Fix Errors", and "Lint & Format".

### Execution
The `QuickActionsManagerSheet` allows CRUD operations. When a user clicks a button in the terminal UI (not shown in this file set, but inferred), the `prompt` string is sent to the active AI agent context.

---

# 6. Template Presets

**Source:** `PresetSelector.swift`, `TemplatePreset.swift`

### Mechanism
*   **Purpose:** Allows saving "layouts" of terminals (e.g., "3 Claude Agents + 1 Standard Terminal").
*   **Model:** `TemplatePreset` contains a list of `SessionConfiguration` objects. Each config stores the `TerminalMode` (Claude, Gemini, Codex, Terminal) and optional `branch`.
*   **Storage:** Stored in memory in `SessionManager` (likely persisted to UserDefaults or disk, though the specific persistence code is in `SessionManager` which wasn't provided, logic dictates it functions like QuickActions).
*   **Restoration:** Clicking a preset iterates through the configurations and spawns the corresponding number of terminal sessions with the specified modes.

---

# 7. Conversion Strategy: Tauri 2.x (Linux)

To port this to Linux using Tauri 2.x, the architecture will shift from **Swift/AppKit** to **Rust/React**.

### A. Git Operations (Backend)
*   **Approach:** Use Rust's `std::process::Command` to execute Git CLI commands, mimicking the Swift `GitManager`.
*   **Why CLI over libgit2?** The Swift code relies heavily on specific CLI output formats (`--format=%H|...`). Replicating this exact output parsing in Rust is safer and faster than rewriting logic to use `git2-rs`, ensuring 1:1 behavior parity.
*   **Async:** All Git commands should be Tauri Commands (`#[tauri::command]`) running on a thread pool to avoid freezing the UI.

### B. Git Graph Visualization (Frontend)
*   **Rendering:** React + **HTML5 Canvas** (or SVG).
    *   **Logic:** Port `GraphLayoutEngine.swift` to TypeScript. The algorithm (topological sort + column assignment) is purely mathematical and translates directly.
    *   **Drawing:**
        *   Use a `<canvas>` layer for the "Rails" (Bezier curves).
        *   Use HTML DOM elements (absolute positioning) for the Commit Nodes and text to ensure text selectability and accessibility.
*   **Virtualization:** Use `tanstack-virtual` (React Virtual) to handle large commit lists, mimicking the batch loading in Swift.

### C. Worktree Management (Backend)
*   **Pathing:** Use `dirs` crate in Rust to find `~/.local/share/maestro/worktrees` (XDG compliance) instead of the hardcoded macOS path.
*   **Logic:** Port `WorktreeManager.swift` logic to Rust. Rust's `std::fs` and `std::path` are robust.
*   **State:** Keep track of active worktrees in a `Mutex<HashMap<SessionId, PathBuf>>` within the Tauri `State`.

### D. Data Persistence (Quick Actions / Presets)
*   **Storage:** Use `tauri-plugin-store`. It provides a simple key-value store (JSON based) compatible with the Swift `UserDefaults` approach.
*   **Migration:** Since this is a rewrite, you can define the JSON schema in Rust structs (`serde`) and read/write directly to `~/.config/maestro/store.json`.

### E. UI Components (Frontend)
*   **Framework:** React (or Svelte/Vue).
*   **Styling:** TailwindCSS.
*   **Icons:** `lucide-react` to replace SF Symbols.
*   **Components:**
    *   `GitTreeView`: A virtual list component.
    *   `PresetSelector`: A Grid/Flex layout.
    *   `QuickActionEditor`: A standard Modal/Dialog form.

### Summary Table

| Subsystem | Swift Implementation | Tauri/Rust Strategy |
| :--- | :--- | :--- |
| **Git Engine** | `Process()` wrapper around CLI | `std::process::Command` wrapper in Rust |
| **Graph Algo** | `GraphLayoutEngine.swift` | Port logic to TypeScript (Frontend) |
| **Graph Render** | SwiftUI Canvas + Views | HTML Canvas (Lines) + DOM (Nodes) |
| **Worktrees** | `FileManager` + Git CLI | `std::fs` + Git CLI in Rust |
| **Storage** | `UserDefaults` | `tauri-plugin-store` (JSON) |
| **Branching** | `git for-each-ref` parsing | Same CLI command, parsed in Rust |
| **Icons** | SF Symbols | Lucide Icons (React) |
