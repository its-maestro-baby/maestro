# Story: OpenCode Mode Selection
**ID:** opencode-support-01  
**Status:** Ready for Development  
**Priority:** P0  
**Estimate:** 2 days

## User Story
As a Maestro user, I want to select OpenCode as an AI mode when configuring a session, so that I can use OpenCode alongside other AI assistants.

## Acceptance Criteria
- [ ] OpenCode appears in the AI mode dropdown in PreLaunchCard
- [ ] OpenCode uses purple/violet color scheme (`text-purple-500`, `bg-purple-500/20`)
- [ ] OpenCode uses `Code2` Lucide icon (or custom OpenCode icon if available)
- [ ] Selecting OpenCode persists as the mode for that session
- [ ] Mode is displayed correctly in TerminalHeader with OpenCode branding
- [ ] CLI availability check works for `opencode` command
- [ ] If OpenCode is not installed, display install hint: `npm install -g opencode-ai`

## Technical Implementation

### Backend Changes
**File:** `src-tauri/src/core/session_manager.rs`
```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AiMode {
    Claude,
    Gemini,
    Codex,
    OpenCode,  // Add this variant
    Plain,
}
```

### Frontend Changes
**File:** `src/lib/terminal.ts`
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
    installHint: "npm install -g opencode-ai",
    skipPermissionsFlag: "--dangerously-skip-permissions",
  },
  // ...
};
```

**File:** `src/components/terminal/TerminalHeader.tsx`
```typescript
export type AIProvider = "claude" | "gemini" | "codex" | "opencode" | "plain";

const providerConfig: Record<AIProvider, { icon: typeof BrainCircuit; label: string }> = {
  // ... existing providers
  opencode: { icon: Code2, label: "OpenCode" },
  // ...
};
```

**File:** `src/components/terminal/PreLaunchCard.tsx`
```typescript
const AI_MODES: { mode: AiMode; icon: typeof BrainCircuit; label: string; color: string }[] = [
  // ... existing modes
  { mode: "OpenCode", icon: Code2, label: "OpenCode", color: "text-purple-500" },
  // ...
];
```

**File:** `src/components/terminal/TerminalView.tsx`
```typescript
function mapAiMode(mode: AiMode): AIProvider {
  const map: Record<AiMode, AIProvider> = {
    Claude: "claude",
    Gemini: "gemini",
    Codex: "codex",
    OpenCode: "opencode",  // Add this
    Plain: "plain",
  };
  // ...
}
```

## Definition of Done
- [ ] User can select OpenCode from mode dropdown
- [ ] OpenCode icon and label display correctly in all UI components
- [ ] Install hint shown when OpenCode CLI not found
- [ ] Mode persists across session operations
- [ ] Unit tests for mode selection and mapping
- [ ] Manual testing on macOS, Windows, Linux

## Dependencies
- None (this is the foundation story)

## Open Questions
- Should we use a custom OpenCode icon or the generic `Code2` icon?
- Do we need to check for minimum OpenCode version?

## Resources
- **Website:** https://opencode.ai
- **Documentation:** https://opencode.ai/docs/
- **GitHub:** https://github.com/anomalyco/opencode
- **npm Package:** opencode-ai
