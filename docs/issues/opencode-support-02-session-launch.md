# Story: OpenCode Session Launch
**ID:** opencode-support-02  
**Status:** Ready for Development  
**Priority:** P0  
**Estimate:** 2 days

## User Story
As a Maestro user, I want to launch OpenCode sessions in isolated git worktrees, so that I can work on multiple tasks simultaneously using OpenCode.

## Acceptance Criteria
- [ ] OpenCode process spawns correctly with working directory set to worktree
- [ ] Environment variables (including MAESTRO_SESSION_ID) passed correctly to OpenCode
- [ ] Session registers with SessionManager with correct mode
- [ ] PTY output streams display in terminal
- [ ] User can interact with OpenCode normally (type commands, see output)
- [ ] Session status updates are tracked (Starting → Idle → Working → etc.)
- [ ] Error handling for launch failures (clear error messages)
- [ ] User can kill OpenCode session via terminal header

## Technical Implementation

### Backend Changes
**File:** `src-tauri/src/commands/terminal.rs`
- Update `check_cli_available` to detect `opencode` command
- Ensure spawn_shell handles OpenCode executable correctly

### Frontend Changes
**File:** `src/lib/terminal.ts`
- Ensure `buildCliCommand` supports OpenCode mode
- OpenCode command: `opencode` (launched in worktree directory)

**File:** `src/stores/useSessionStore.ts`
```typescript
export type AiMode = "Claude" | "Gemini" | "Codex" | "OpenCode" | "Plain";
```

**File:** `src/components/terminal/TerminalView.tsx`
- Ensure status mapping works for OpenCode
- Handle OpenCode-specific status transitions

### Integration Points
- Worktree creation (reuse existing worktree manager)
- Session lifecycle management
- Process spawning via PTY
- MCP status reporting (if OpenCode supports it)

## Definition of Done
- [ ] OpenCode session launches successfully in worktree
- [ ] User can type commands and see output
- [ ] Session appears in sidebar with correct status
- [ ] Kill session button works
- [ ] Error messages displayed on launch failure
- [ ] Status transitions tracked correctly
- [ ] Integration tests for session lifecycle
- [ ] Manual testing completed

## Test Scenarios
1. **Happy Path:** Select OpenCode → Launch → Interact → Kill
2. **Launch Failure:** OpenCode not in PATH → Error message displayed
3. **Worktree Isolation:** Changes in OpenCode session don't affect other sessions
4. **Status Updates:** Status changes reflected in UI in real-time

## Dependencies
- Story 01: OpenCode Mode Selection (completed)

## Notes
- OpenCode should work like other AI CLIs - launched as subprocess in worktree
- Stdio should be connected to PTY for terminal interaction
- MCP integration can be added in later story if OpenCode supports it

## Resources
- **OpenCode Docs:** https://opencode.ai/docs/
- **Configuration:** https://opencode.ai/docs/config/
