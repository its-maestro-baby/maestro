# Business Requirements Document (BRD)
## Add OpenCode Support to Maestro

**Version:** 1.0  
**Date:** February 15, 2026  
**Status:** Draft  
**Author:** Product Team  

---

## 1. Executive Summary

### 1.1 Overview
This BRD outlines the requirements for adding OpenCode support to Maestro, enabling users to orchestrate OpenCode CLI sessions alongside existing AI assistants (Claude Code, Gemini CLI, OpenAI Codex).

### 1.2 Purpose
OpenCode is an emerging AI coding assistant that provides a unique approach to AI-assisted development. By supporting OpenCode, Maestro expands its ecosystem coverage and provides users with more flexibility in their AI tooling choices.

### 1.3 Key Stakeholders
- **Users:** Developers who want to use OpenCode in multi-session workflows
- **Product Team:** Feature prioritization and roadmap planning
- **Engineering:** Implementation and maintenance
- **QA:** Testing and quality assurance

---

## 2. Background and Context

### 2.1 Current State
Maestro currently supports four AI modes:
1. **Claude Code** (Anthropic) - `claude` command
2. **Gemini CLI** (Google) - `gemini` command
3. **OpenAI Codex** - `codex` command
4. **Plain Terminal** - No AI, standard shell

### 2.2 Market Context
OpenCode is gaining traction in the developer community as an open-source AI coding assistant alternative. Supporting OpenCode aligns with Maestro's strategy of being AI-agnostic and providing maximum flexibility to users.

### 2.3 User Impact
Users who prefer OpenCode for its open-source nature, privacy features, or specific capabilities will be able to:
- Launch OpenCode sessions alongside other AI assistants
- Manage multiple OpenCode worktrees
- Use OpenCode's CLI flags and configuration options
- Track OpenCode usage and status through Maestro's MCP integration

---

## 3. Objectives and Success Criteria

### 3.1 Primary Objectives
1. **Full Feature Parity:** OpenCode support should match existing AI mode capabilities
2. **Seamless Integration:** Users can switch to OpenCode as easily as other AI modes
3. **Configuration Support:** Full support for OpenCode CLI flags and settings
4. **UI Consistency:** OpenCode mode should be visually consistent with other AI modes

### 3.2 Success Criteria
- [ ] Users can select "OpenCode" as an AI mode in the session configuration
- [ ] OpenCode sessions launch successfully in isolated git worktrees
- [ ] OpenCode CLI flags are configurable via Maestro's CLI Settings modal
- [ ] OpenCode status updates are received via MCP protocol
- [ ] OpenCode appears correctly in all UI components (mode selector, terminal header, etc.)
- [ ] Documentation is updated to include OpenCode installation and usage

### 3.3 KPIs
- **Adoption Rate:** % of sessions using OpenCode mode within 3 months of launch
- **User Satisfaction:** Support ticket volume for OpenCode-related issues
- **Stability:** Crash/error rate for OpenCode sessions vs. other AI modes

---

## 4. Scope

### 4.1 In Scope
1. **Core Integration:**
   - Add "OpenCode" to AiMode enum (frontend and backend)
   - Configure OpenCode CLI command and flags
   - Support OpenCode installation detection

2. **UI/UX:**
   - Add OpenCode to mode selector dropdown
   - Add OpenCode icon and branding to UI components
   - Add OpenCode CLI settings configuration

3. **Session Management:**
   - Launch OpenCode in isolated worktrees
   - Handle OpenCode status updates via MCP
   - Support OpenCode-specific environment variables

4. **Documentation:**
   - Update README with OpenCode installation instructions
   - Update CLI settings documentation
   - Add OpenCode to feature lists

### 4.2 Out of Scope (Future Phases)
- OpenCode-specific plugin marketplace support
- OpenCode usage tracking/limitations (if API becomes available)
- OpenCode-specific quick actions
- Integration with OpenCode's proprietary features not available via CLI

### 4.3 Assumptions
- OpenCode CLI follows standard conventions similar to other AI CLIs
- OpenCode supports stdio-based MCP communication
- OpenCode can be installed via npm or similar package manager
- OpenCode accepts command-line flags for configuration

---

## 5. Technical Requirements

### 5.1 Backend Changes (Rust)

#### 5.1.1 Session Manager (`src-tauri/src/core/session_manager.rs`)
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AiMode {
    Claude,
    Gemini,
    Codex,
    OpenCode,  // NEW
    Plain,
}
```

#### 5.1.2 Terminal Commands (`src-tauri/src/commands/terminal.rs`)
- Update `check_cli_available` to detect `opencode` command
- Add OpenCode to supported CLI verification

### 5.2 Frontend Changes (TypeScript/React)

#### 5.2.1 Type Definitions

**`src/lib/terminal.ts`:**
```typescript
export type AiMode = "Claude" | "Gemini" | "Codex" | "OpenCode" | "Plain";

export const AI_CLI_CONFIG: Record<AiMode, {
  command: string | null;
  installHint: string;
  skipPermissionsFlag: string | null;
}> = {
  // ... existing modes
  OpenCode: {
    command: "opencode",
    installHint: "npm install -g opencode",
    skipPermissionsFlag: "--dangerously-skip-permissions",  
  },
  // ...
};
```

**`src/components/terminal/TerminalHeader.tsx`:**
```typescript
export type AIProvider = "claude" | "gemini" | "codex" | "opencode" | "plain";

const providerConfig: Record<AIProvider, { icon: typeof BrainCircuit; label: string }> = {
  // ... existing providers
  opencode: { icon: OpenCodeIcon, label: "OpenCode" },  // Custom OpenCode icon
  // ...
};
```

#### 5.2.2 UI Components

**`src/components/terminal/PreLaunchCard.tsx`:**
```typescript
const AI_MODES: { mode: AiMode; icon: typeof BrainCircuit; label: string; color: string }[] = [
  // ... existing modes
  { mode: "OpenCode", icon: OpenCodeIcon, label: "OpenCode", color: "text-purple-500" },
  // ...
];
```

**`src/components/terminal/CliSettingsModal.tsx`:**
```typescript
const CLI_MODES: CliAiMode[] = ["Claude", "Gemini", "Codex", "OpenCode"];

const MODE_CONFIG: Record<CliAiMode, { color: string; bgColor: string; skipFlagName: string }> = {
  // ... existing modes
  OpenCode: {
    color: "text-purple-500",
    bgColor: "bg-purple-500/20",
    skipFlagName: "--dangerously-skip-permissions",  
  },
};
```

#### 5.2.3 Store Updates

**`src/stores/useCliSettingsStore.ts`:**
```typescript
const DEFAULT_FLAGS: CliFlagsConfig = {
  Claude: { ...DEFAULT_MODE_FLAGS },
  Gemini: { ...DEFAULT_MODE_FLAGS },
  Codex: { ...DEFAULT_MODE_FLAGS },
  OpenCode: { ...DEFAULT_MODE_FLAGS },  // NEW
};
```

### 5.3 Icon Requirements
- Use the official OpenCode icon from https://dashboardicons.com/icons/opencode
- Download SVG and create `OpenCodeIcon` component at `src/components/icons/OpenCodeIcon.tsx`
- Component should accept same props as Lucide icons (size, className, etc.)
- Use OpenCode brand colors or purple/violet scheme for consistency

---

## 6. Functional Requirements

### 6.1 FR-1: Mode Selection
**Description:** Users can select OpenCode as an AI mode when configuring a session.

**Acceptance Criteria:**
- OpenCode appears in the mode dropdown in PreLaunchCard
- OpenCode is selectable alongside other AI modes
- Mode persists when session is created
- Mode is displayed correctly in TerminalHeader

**Priority:** P0

### 6.2 FR-2: CLI Detection
**Description:** Maestro detects if OpenCode CLI is installed on the system.

**Acceptance Criteria:**
- `checkCliAvailable` command detects `opencode` binary in PATH
- Appropriate error message if OpenCode is not installed
- Install hint displayed to user

**Priority:** P0

### 6.3 FR-3: Session Launch
**Description:** OpenCode sessions launch successfully in isolated worktrees.

**Acceptance Criteria:**
- OpenCode process spawns correctly with working directory set to worktree
- Environment variables passed correctly
- Session registers with SessionManager
- PTY output streams correctly

**Priority:** P0

### 6.4 FR-4: CLI Flags Configuration
**Description:** Users can configure OpenCode-specific CLI flags.

**Acceptance Criteria:**
- OpenCode appears in CLI Settings modal
- Skip permissions flag toggle works
- Custom flags input works
- Command preview updates in real-time
- Settings persist across sessions

**Priority:** P1

### 6.5 FR-5: Status Tracking
**Description:** OpenCode session status is tracked and displayed.

**Acceptance Criteria:**
- Status updates received via MCP (if supported)
- Status displayed in terminal header (idle, working, needs-input, etc.)
- Status colors and labels appropriate
- Status transitions handled correctly

**Priority:** P1

### 6.6 FR-7: Error Handling
**Description:** Errors in OpenCode sessions are handled gracefully.

**Acceptance Criteria:**
- Launch failures show meaningful error messages
- Process crashes are detected and reported
- User can kill/restart OpenCode sessions
- Logs capture OpenCode-specific errors

**Priority:** P1

---

## 7. Non-Functional Requirements

### 7.1 Performance
- OpenCode session launch time should be comparable to other AI modes (< 3 seconds)
- No performance degradation for existing AI modes
- Status updates received within 1 second

### 7.2 Security
- OpenCode runs in isolated worktree (same security model as other modes)
- No elevated privileges required beyond what OpenCode CLI needs
- Environment variables sanitized before passing to OpenCode

### 7.3 Compatibility
- Support OpenCode CLI version 1.0+
- Cross-platform support (macOS, Windows, Linux)
- Backward compatible with existing Maestro features

### 7.4 Maintainability
- Follow existing code patterns for AI modes
- Documentation comments for OpenCode-specific logic
- Unit tests for new functionality

---

## 8. UI/UX Requirements

### 8.1 Visual Design
- **Icon:** Use custom `OpenCodeIcon` component (from https://dashboardicons.com/icons/opencode)
- **Color:** Purple/violet color scheme (`text-purple-500`, `bg-purple-500/20`)
- **Label:** "OpenCode" (not "Open Code")
- **Consistency:** Match existing AI mode styling

### 8.2 User Flows

#### Flow 1: First-Time OpenCode Setup
1. User selects OpenCode mode in session configuration
2. Maestro checks if OpenCode CLI is installed
3. If not installed, display install hint: `npm install -g opencode`
4. User installs OpenCode
5. User can now launch OpenCode sessions

#### Flow 2: Configuring OpenCode Flags
1. User opens CLI Settings modal
2. User selects "OpenCode" tab
3. User toggles "Skip Permissions" flag
4. User adds custom flags in text input
5. Command preview updates in real-time
6. Settings saved automatically

#### Flow 3: Running OpenCode Session
1. User configures session with OpenCode mode
2. User clicks "Launch"
3. Terminal opens with OpenCode running
4. Terminal header shows OpenCode icon and status
5. User interacts with OpenCode normally

### 8.3 Error Messages

| Scenario | Error Message |
|----------|--------------|
| OpenCode not installed | "OpenCode CLI not found. Install with: npm install -g opencode" |
| OpenCode launch failed | "Failed to start OpenCode: {error details}" |
| OpenCode crashed | "OpenCode session ended unexpectedly" |
| Unsupported flag | "Invalid flag for OpenCode: {flag}" |

---

## 9. Implementation Plan

### Phase 1: Core Backend Changes (2 days)
- [ ] Update `AiMode` enum in Rust
- [ ] Update `AiMode` type in TypeScript
- [ ] Add OpenCode to `AI_CLI_CONFIG`
- [ ] Update CLI availability check

### Phase 2: Frontend UI Changes (2 days)
- [ ] Add OpenCode to mode selector
- [ ] Add OpenCode icon and branding
- [ ] Update TerminalHeader provider mapping
- [ ] Add OpenCode to CLI Settings modal
- [ ] Update CLI settings store defaults

### Phase 3: Integration & Testing (2 days)
- [ ] End-to-end testing of OpenCode sessions
- [ ] Test CLI flags configuration
- [ ] Test error handling scenarios
- [ ] Cross-platform testing

### Phase 4: Documentation (1 day)
- [ ] Update README.md
- [ ] Update AGENTS.md if needed
- [ ] Add OpenCode to feature lists
- [ ] Update troubleshooting guide

**Total Estimated Effort:** 7 days

---

## 10. Testing Strategy

### 10.1 Unit Tests
- **Backend:** Test AiMode serialization/deserialization
- **Frontend:** Test mode selection, flag building, icon rendering
- **Stores:** Test CLI settings persistence for OpenCode

### 10.2 Integration Tests
- Launch OpenCode session successfully
- Switch between OpenCode and other modes
- Configure and persist CLI flags
- Status updates flow correctly

### 10.3 Manual Testing Checklist
- [ ] Install OpenCode CLI
- [ ] Create new session with OpenCode mode
- [ ] Launch and interact with OpenCode
- [ ] Configure CLI flags
- [ ] Kill and restart OpenCode session
- [ ] Switch modes mid-session (if supported)
- [ ] Test on macOS, Windows, Linux

### 10.4 Test Cases

| ID | Test Case | Expected Result | Priority |
|----|-----------|----------------|----------|
| TC-1 | Select OpenCode mode | OpenCode appears selected, OpenCodeIcon shows | P0 |
| TC-2 | Launch without OpenCode installed | Error message with install hint | P0 |
| TC-3 | Launch with OpenCode installed | Session starts successfully | P0 |
| TC-4 | Configure skip permissions flag | Flag appears in command preview | P1 |
| TC-5 | Add custom flags | Custom flags appear in command preview | P1 |
| TC-6 | Status updates | Status changes reflected in UI | P1 |
| TC-7 | Kill session | Session terminates gracefully | P1 |
| TC-8 | Settings persist | Settings saved after app restart | P1 |

---

## 11. Risks and Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| OpenCode CLI changes | Medium | Medium | Monitor OpenCode releases, maintain compatibility layer |
| OpenCode doesn't support MCP | Medium | Low | Implement without MCP, add later if supported |
| Different CLI flag patterns | Low | Medium | Research OpenCode flags thoroughly before implementation |
| Icon/licensing issues | Low | Low | Use official OpenCode icon from dashboardicons.com |
| User confusion with similar tools | Medium | Low | Clear documentation, distinct branding |

---

## 12. Dependencies

### 12.1 External Dependencies
- OpenCode CLI must be installed by user
- OpenCode must support headless/CLI operation

### 12.2 Internal Dependencies
- Session management system
- CLI settings store
- Terminal PTY management
- MCP status server (optional)

---

## 13. Open Questions

1. What is the exact command name for OpenCode CLI? (`opencode` assumed)
2. Does OpenCode support a "skip permissions" flag? If so, what is it called?
3. Does OpenCode support MCP protocol for status updates?
4. What are OpenCode's exit codes and error patterns?
5. Does OpenCode have any unique environment variables?
6. What is the minimum supported OpenCode version?

---

## 14. Appendices

### Appendix A: Reference Implementation

Existing AI modes implementation can be used as a template:
- **Claude:** Most established implementation
- **Gemini:** Similar complexity to expected OpenCode
- **Codex:** Recently added, good reference for patterns

### Appendix B: OpenCode Resources

- **Website:** https://opencode.ai
- **Configuration:** https://opencode.ai/docs/config/
- **Documentation:** https://opencode.ai/docs/
- **GitHub:** https://github.com/anomalyco/opencode
- **npm Package:** opencode-ai

### Appendix C: Glossary

- **AI Mode:** The type of AI assistant running in a session
- **CLI:** Command Line Interface
- **MCP:** Model Context Protocol
- **PTY:** Pseudo-Terminal
- **Worktree:** Git worktree for isolated development
- **OpenCode:** The AI coding assistant being integrated

---

## 15. Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Product Manager | | | |
| Engineering Lead | | | |
| UX Designer | | | |
| QA Lead | | | |

---

**Document History:**

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-15 | Product Team | Initial draft |

---

*End of Document*
