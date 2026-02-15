# Story: OpenCode CLI Settings
**ID:** opencode-support-03  
**Status:** Ready for Development  
**Priority:** P1  
**Estimate:** 2 days

## User Story
As a Maestro user, I want to configure OpenCode-specific CLI flags (like --dangerously-skip-permissions), so that I can customize how OpenCode behaves without typing flags manually.

## Acceptance Criteria
- [ ] OpenCode appears as a tab in CLI Settings modal
- [ ] "Skip Permissions" toggle works for OpenCode (`--dangerously-skip-permissions`)
- [ ] Custom flags input field accepts user-defined flags
- [ ] Command preview updates in real-time showing the full opencode command
- [ ] Settings persist across app restarts
- [ ] Reset to defaults button works for OpenCode
- [ ] Visual styling matches other AI modes (purple color scheme)

## Technical Implementation

### Frontend Changes
**File:** `src/components/terminal/CliSettingsModal.tsx`
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

**File:** `src/stores/useCliSettingsStore.ts`
```typescript
const DEFAULT_FLAGS: CliFlagsConfig = {
  Claude: { ...DEFAULT_MODE_FLAGS },
  Gemini: { ...DEFAULT_MODE_FLAGS },
  Codex: { ...DEFAULT_MODE_FLAGS },
  OpenCode: { ...DEFAULT_MODE_FLAGS },  // Add this
};
```

**File:** `src/lib/terminal.ts`
- Update `buildCliCommand` to handle OpenCode flags
- Example: `opencode --dangerously-skip-permissions --custom-flag`

### Data Flow
1. User opens CLI Settings modal
2. User selects "OpenCode" tab
3. User toggles "Skip Permissions" checkbox
4. User adds custom flags in text input
5. Command preview updates: `opencode --dangerously-skip-permissions {custom flags}`
6. Settings saved to store and persisted to disk
7. Next OpenCode session uses these flags

## Definition of Done
- [ ] OpenCode tab in CLI Settings modal
- [ ] Skip permissions toggle works
- [ ] Custom flags input works
- [ ] Command preview updates correctly
- [ ] Settings persist after app restart
- [ ] Reset buttons work correctly
- [ ] Unit tests for flag building logic
- [ ] Manual testing completed

## Test Scenarios
1. **Enable Skip Permissions:** Toggle on → Preview shows `--dangerously-skip-permissions`
2. **Add Custom Flags:** Type `--verbose --debug` → Preview includes custom flags
3. **Both Flags:** Toggle on + custom flags → Both appear in preview
4. **Persistence:** Close app → Reopen → Settings preserved
5. **Reset:** Click reset → Returns to defaults

## Dependencies
- Story 01: OpenCode Mode Selection
- Story 02: OpenCode Session Launch

## UI Mockup
```
┌─────────────────────────────────────┐
│ CLI Settings                    [X] │
├─────────────────────────────────────┤
│ [Claude] [Gemini] [Codex] [OpenCode]│
├─────────────────────────────────────┤
│ OpenCode Settings                   │
│                                     │
│ [ ] Skip Permissions                │
│     (--dangerously-skip-permissions)│
│                                     │
│ Custom Flags:                       │
│ [________________________]          │
│                                     │
│ Preview:                            │
│ opencode --dangerously-skip-perms   │
│                                     │
│ [Reset to Defaults]                 │
└─────────────────────────────────────┘
```

**Note:** OpenCode tab uses the custom `OpenCodeIcon` component instead of Lucide icons.

## Resources
- **OpenCode Configuration:** https://opencode.ai/docs/config/
- **Flag Documentation:** Check OpenCode docs for available flags
