# Maestro - Repository Overview

## Project Summary

**Maestro** is a cross-platform desktop application that orchestrates multiple AI coding assistants in parallel. Built with Tauri, it allows running 1-6 Claude Code (or other AI CLI) sessions simultaneously, each in its own isolated git worktree.

- **Version**: 0.2.0
- **License**: MIT
- **Repository**: https://github.com/its-maestro-baby/maestro
- **Documentation**: https://its-maestro-baby.github.io/maestro/

---

## Architecture

### Technology Stack

| Component | Technology |
|-----------|------------|
| Desktop Framework | Tauri 2.0 |
| Frontend | React 18 + TypeScript 5 + Tailwind CSS |
| Terminal Emulator | xterm.js |
| Backend | Rust 1.78+ |
| State Management | Zustand |
| Build Tool | Vite |

### Repository Statistics

```
Total Files:        206
Symbols:            2,654
Edges:              1,677
Languages:          TSX (68), TypeScript (50), Rust (46), Markdown (17)
Parse Coverage:     92%
Avg Symbols/File:   12.9
```

### Directory Structure

```
maestro/
├── src/                        # React/TypeScript frontend (118 files)
│   ├── components/             # UI components
│   │   ├── git/               # Git visualization & operations
│   │   ├── marketplace/       # Plugin marketplace UI
│   │   ├── quickactions/      # Quick action components
│   │   ├── settings/          # Settings modals
│   │   ├── shared/            # Shared UI components
│   │   ├── sidebar/           # Sidebar navigation
│   │   ├── tamagotchi/        # Usage tracker widget
│   │   └── terminal/          # Terminal grid & panes
│   ├── hooks/                 # Custom React hooks
│   ├── lib/                   # Utility libraries
│   ├── stores/                # Zustand state stores
│   └── types/                 # TypeScript type definitions
├── src-tauri/                 # Tauri Rust backend (48 files)
│   └── src/
│       ├── commands/          # Tauri command handlers
│       └── core/              # Core business logic
├── maestro-mcp-server/        # Rust MCP server (4 files)
├── website/                   # Documentation website (12 files)
└── docs/                      # Documentation (7 files)
```

---

## Core Features

### 1. Multi-Terminal Session Grid
- Dynamic grid layout (1x1 to 2x3)
- iTerm2-style split panes (Cmd+D vertical, Cmd+Shift+D horizontal)
- Real-time session status indicators
- Per-session AI mode selection

### 2. Git Worktree Isolation
- Automatic worktree creation at `~/.claude-maestro/worktrees/`
- Branch-based isolation for conflict-free parallel development
- Visual branch assignment in sidebar

### 3. MCP Server Integration
- Built-in MCP server for agent status reporting
- Real-time status updates (idle, working, needs_input, finished, error)
- Status communication via `maestro_status` tool

### 4. Visual Git Graph
- GitKraken-style commit visualization
- Branch relationship view with colored rails
- PR/Issue/Discussion management

### 5. Plugin Marketplace
- Browse and install community plugins
- Plugin types: Skills, Commands, MCP servers, Agents, Hooks
- Per-session plugin configuration

### 6. Multi-AI Support
- Claude Code (Anthropic)
- Gemini CLI (Google)
- OpenAI Codex
- Plain Terminal

---

## Code Health Analysis

### Architecture Health

| Metric | Status |
|--------|--------|
| Circular Dependencies | None detected (healthy) |
| God Components | None |
| Layer Violations | 0 |
| Architecture | Clean, well-structured |

### Most Referenced Files (Architectural Hotspots)

| File | Dependents | Description |
|------|------------|-------------|
| `src/stores/useGitHubStore.ts` | 16 | GitHub integration state |
| `src/stores/useGitStore.ts` | 11 | Git operations state |
| `src/stores/useWorkspaceStore.ts` | 8 | Workspace management |
| `src/stores/useSessionStore.ts` | 8 | Session management |
| `src/types/marketplace.ts` | 7 | Marketplace types |
| `src/lib/terminal.ts` | 6 | Terminal utilities |
| `src/lib/graphLayout.ts` | 6 | Git graph layout |

### Most Complex Files (by complexity score)

| File | Complexity Score | Symbols | Description |
|------|-----------------|---------|-------------|
| `src/stores/useGitHubStore.ts` | 6,016 | 376 | GitHub state management |
| `src/stores/useGitStore.ts` | 3,322 | 302 | Git state management |
| `src/stores/useWorkspaceStore.ts` | 1,520 | 190 | Workspace state |
| `src/stores/useMarketplaceStore.ts` | 1,512 | 216 | Marketplace state |
| `src/components/sidebar/Sidebar.tsx` | 417 | 417 | Main sidebar UI |

### Files with Most Dependencies

| File | Dependencies | Description |
|------|--------------|-------------|
| `src/components/sidebar/Sidebar.tsx` | 21 | Main sidebar component |
| `src/App.tsx` | 20 | Root application component |
| `src/components/terminal/TerminalGrid.tsx` | 15 | Terminal grid container |

---

## Backend Modules (Rust)

### Command Handlers (`src-tauri/src/commands/`)

| Module | Purpose |
|--------|---------|
| `claudemd.rs` | Claude.md file operations |
| `fonts.rs` | System font detection |
| `git.rs` | Git operations (branches, worktrees, commits) |
| `github.rs` | GitHub API integration (PRs, Issues, Discussions) |
| `marketplace.rs` | Plugin marketplace commands |
| `mcp.rs` | MCP server management |
| `plugin.rs` | Plugin/skill management |
| `session.rs` | Session lifecycle |
| `terminal.rs` | Terminal backend operations |
| `update.rs` | Auto-updater |
| `usage.rs` | Claude API usage tracking |
| `worktree.rs` | Git worktree management |

### Core Modules (`src-tauri/src/core/`)

| Module | Purpose |
|--------|---------|
| `process_manager.rs` | PTY session management |
| `plugin_manager.rs` | Plugin discovery & management |
| `marketplace_manager.rs` | Marketplace operations |
| `mcp_manager.rs` | MCP server discovery |
| `worktree_manager.rs` | Worktree lifecycle |
| `session_manager.rs` | Session state management |
| `font_detector.rs` | Font detection & selection |
| `status_server.rs` | MCP status server |
| `terminal_backend/` | Terminal implementations |

---

## Frontend State Stores

| Store | Purpose | Complexity |
|-------|---------|------------|
| `useGitHubStore` | GitHub auth, PRs, Issues, Discussions | High (6,016) |
| `useGitStore` | Git operations, branches, worktrees | High (3,322) |
| `useWorkspaceStore` | Project tabs, repositories | Medium (1,520) |
| `useMarketplaceStore` | Plugin marketplace data | Medium (1,512) |
| `useSessionStore` | Terminal sessions | Medium (1,096) |
| `useMcpStore` | MCP server configuration | Medium (664) |
| `usePluginStore` | Plugin/skills state | Medium (398) |
| `useTerminalSettingsStore` | Terminal preferences | Low (345) |
| `useQuickActionStore` | Quick action definitions | Low (180) |
| `useUpdateStore` | Auto-update state | Low (460) |

---

## Code Clusters

The codebase forms several natural clusters based on cohesion analysis:

### Major Clusters

1. **Stores + Lib + Sidebar** (110 symbols, 70% cohesion)
   - Core state management and UI
   - Cross-cuts: `src/stores/`, `src/lib/`, `src/components/sidebar/`

2. **Terminal + MultiProjectView** (89 symbols, 70% cohesion)
   - Terminal grid and multi-project support
   - Cross-cuts: `src/components/terminal/`, `src/components/shared/`

3. **Git + GitHub Integration** (88 symbols, 82% cohesion)
   - Git visualization and GitHub operations
   - Cross-cuts: `src/components/git/`, `src-tauri/src/github/`

4. **Marketplace + Plugins** (61 symbols, 88% cohesion)
   - Plugin marketplace and installation
   - Cross-cuts: `src/components/marketplace/`, `src/lib/`

5. **MCP Protocol** (59 symbols, 87% cohesion)
   - MCP server management
   - Cross-cuts: `src-tauri/src/core/mcp_manager.rs`, `src-tauri/src/commands/`

---

## Entry Points

### Frontend
- **`src/App.tsx`** - Root React application component
- **`src/main.tsx`** - React DOM entry point

### Backend
- **`src-tauri/src/main.rs`** - Tauri application entry
- **`src-tauri/src/lib.rs`** - Library root with `run()` function
- **`maestro-mcp-server/src/main.rs`** - MCP server entry

---

## Dependencies

### Key Frontend Dependencies
```json
{
  "@tauri-apps/api": "^2.10.1",
  "@xterm/xterm": "^5.5.0",
  "react": "^18.3.0",
  "zustand": "^5.0.10",
  "tailwindcss": "^3.4.0"
}
```

### Key Backend Dependencies
- Tauri 2.0 (desktop framework)
- tokio (async runtime)
- serde (serialization)
- DashMap (concurrent hash maps)

---

## Documentation

The project includes comprehensive documentation:

| Document | Purpose |
|----------|---------|
| `README.md` | Main project documentation |
| `docs/research/00-MASTER-ARCHITECTURAL-PLAN.md` | Architecture overview |
| `docs/research/01-core-architecture-breakdown.md` | Core systems |
| `docs/research/02-mcp-marketplace-plugins-breakdown.md` | MCP & plugins |
| `docs/research/03-git-visualization-actions-breakdown.md` | Git visualization |
| `docs/specs/tamagotchi-multi-provider.md` | Usage tracker spec |
| `website/` | Full documentation website |

---

## Testing

- **Framework**: Vitest
- **Location**: `src/**/*.test.tsx`
- **Run**: `npm run test`
- **Coverage**: Components include unit tests (e.g., `BranchDropdown.test.tsx`, `FDADialog.test.tsx`)

Backend tests are embedded in source files using Rust's `#[cfg(test)]` modules.

---

## Build & Development

### Development
```bash
npm install
cargo build --release -p maestro-mcp-server
npm run tauri dev
```

### Production Build
```bash
npm run tauri build
```

### Testing
```bash
npm run test
```

---

## Key Insights

### Strengths
1. **Clean Architecture**: No circular dependencies, well-separated concerns
2. **Comprehensive Git Integration**: Full worktree isolation with visual graph
3. **Extensible Plugin System**: Marketplace with multiple plugin types
4. **Multi-AI Support**: Works with Claude, Gemini, and OpenAI Codex
5. **Rich Terminal Experience**: xterm.js with split panes and custom fonts

### Areas of High Complexity
1. **GitHub Store** (`useGitHubStore.ts`) - Most complex component (6,016 complexity score)
2. **Git Store** (`useGitStore.ts`) - Heavy git operations state
3. **Sidebar** (`Sidebar.tsx`) - Complex UI with many sections
4. **Terminal Grid** (`TerminalGrid.tsx`) - Complex terminal management

### Potential Refactoring Targets
- The mega-cluster spanning stores/lib/sidebar (70% cohesion) could benefit from clearer boundaries
- High complexity store files indicate potential for splitting or simplifying

---

## Generated

This overview was generated using:
- **dora**: Code exploration and dependency analysis
- **roam**: Symbol analysis and architecture health checks

*Generated: 2026-02-14*
