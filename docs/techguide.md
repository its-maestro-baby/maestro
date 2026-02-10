# Maestro Technical Guide

## Git Setup

Two remotes:

| Name | URL | Role |
|------|-----|------|
| `origin` | `github.com/its-maestro-baby/maestro` | Upstream (the real repo) |
| `fork` | `github.com/bennyblancobronx/maestro` | Your fork (where branches live) |

PRs go from `fork/<branch>` into `origin/main`.

## Branch Workflow

### Starting new work

Always start from latest upstream main:

```bash
git fetch origin main
git checkout -b <branch-name> origin/main
```

This guarantees your branch has zero extra commits. No duplicates, no already-merged history.

### Branch naming

| Type | Pattern | Example |
|------|---------|---------|
| Feature | `feature/<name>` | `feature/auto-update` |
| Bug fix | `fix/<name>` | `fix/macos-fda-permissions` |
| Docs | `docs/<name>` | `docs/update-readme` |
| Refactor | `refactor/<name>` | `refactor/mcp-status-reliability` |

### Never reuse branches

If a branch was already merged (or its commit was merged via another PR), do NOT add more commits to it and open a new PR. Create a fresh branch from `origin/main`.

## Commits

### One feature per commit

Each commit = one logical change. If you're adding auto-update AND new CLI modes, those are two separate commits (or two separate PRs).

### Message format

```
type(scope): short description
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `ci`

Scope is optional, use when it narrows the context: `macos`, `windows`, `terminal`, `sidebar`.

Examples from this repo:

```
feat: pre-launch auto-update for CLI agents
fix(macos): stop repeating volume permission dialogs on external drives
fix(macos): request FDA for TCC-protected paths, skip external drives
docs: improve Linux build instructions for Ubuntu 24.04 LTS
refactor: extract worktree manager from TerminalGrid
```

### Message body

For non-trivial changes, add a body after a blank line. Plain language. What changed and why.

```
feat: pre-launch auto-update for CLI agents

When enabled, the launch sequence runs the agent's update command before
starting the CLI (update && agent). Detects install source and builds
platform-aware update commands. Claude uses native installer after
upstream npm deprecation.
```

### What NOT to commit

- `.claude-flow/`, `.swarm/` -- tool artifacts
- Working notes (`autoupdate.md`, `plan.md`)
- Docs in `docs/issues/` unless the PR is specifically about those docs
- `scripts/` utility scripts unless the PR is about them
- `.env`, credentials, secrets

## Pull Requests

### Creating a PR

```bash
# 1. Make sure branch is clean and based on latest main
git fetch origin main
git log --oneline origin/main..HEAD   # should show ONLY your commits

# 2. Push to your fork
git push fork <branch-name>

# 3. Open PR from fork to upstream
gh pr create --repo its-maestro-baby/maestro \
  --head bennyblancobronx:<branch-name> \
  --base main \
  --title "type: short description" \
  --body "..."
```

### PR description format

```
## What

One or two sentences. What does this PR do.

## Why

Bullet points. What problem does it solve.

## How

Numbered steps or bullet points. How it works.

## Files changed

Group by area. One line per file with a short note.

Tested on macOS XX.X with <what you tested>.
```

No test plan checklists (if it's tested, just say so). No feature specs. Keep it factual.

### Before opening a PR, verify

```bash
# Only your commits, nothing else
git log --oneline origin/main..HEAD

# No commits from main missing
git log --oneline HEAD..origin/main   # should be empty

# No unintended files
git diff --stat origin/main..HEAD
```

If `git log --oneline HEAD..origin/main` shows commits, you need to rebase:

```bash
git fetch origin main
git rebase origin/main
```

### One feature per PR

Do not bundle unrelated changes. If you have:
- Auto-update feature
- New CLI modes (OpenLLM, LiteLLM, Ollama)

Those are two PRs on two branches.

### Fixing a PR

If a PR has problems (wrong commits, merge conflicts):

1. Create a new clean branch from `origin/main`
2. Cherry-pick only the commits you want: `git cherry-pick <hash>`
3. Close the bad PR, open a new one
4. Stash local work first if needed: `git stash`

Do NOT try to fix it by amending/rebasing the old branch repeatedly. Start clean.

## Build Verification

Before committing:

```bash
npm run build          # frontend compiles
cd src-tauri && cargo check && cd ..   # rust compiles
```

Before opening a PR:

```bash
npm run build
npm run lint
```

## Quick Reference

```bash
# Start new feature
git fetch origin main && git checkout -b feature/my-thing origin/main

# Check what you have
git log --oneline origin/main..HEAD

# Push to fork
git push fork feature/my-thing

# Open PR
gh pr create --repo its-maestro-baby/maestro --head bennyblancobronx:feature/my-thing --base main

# Stash local work
git stash -m "description"

# Restore stash
git stash pop
```
