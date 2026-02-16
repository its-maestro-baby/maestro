# Story: OpenCode Mode Selection
**ID:** opencode-support-01  
**Status:** Completed
**Priority:** P0  
**Estimate:** 2 days

## User Story
As a Maestro user, I want to select OpenCode as an AI mode when configuring a session, so that I can use OpenCode alongside other AI assistants.

## Acceptance Criteria
- [✅] OpenCode appears in the AI mode dropdown in PreLaunchCard
- [✅] OpenCode uses purple/violet color scheme (`text-purple-500`, `bg-purple-500/20`)
- [✅] OpenCode uses custom `OpenCodeIcon` component (from https://dashboardicons.com/icons/opencode)
- [✅] Selecting OpenCode persists as the mode for that session
- [✅] Mode is displayed correctly in TerminalHeader with OpenCode branding
- [✅] CLI availability check works for `opencode` command
- [✅] If OpenCode is not installed, display install hint: `npm install -g opencode-ai`

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

### Icon Component Setup

**Step 1: Download the OpenCode icon**
1. Visit https://dashboardicons.com/icons/opencode
2. Download the SVG file
3. Save it to your workspace

**Step 2: Create the OpenCodeIcon component**
**File:** `src/components/icons/OpenCodeIcon.tsx`
```typescript
import type { SVGProps } from "react";

interface OpenCodeIconProps extends SVGProps<SVGSVGElement> {
  size?: number;
}

/**
 * OpenCode brand icon component.
 * Downloaded from https://dashboardicons.com/icons/opencode
 * Accepts same props as Lucide icons for consistency.
 */
export function OpenCodeIcon({ 
  size = 24, 
  className = "", 
  ...props 
}: OpenCodeIconProps) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      {...props}
    >
      {/* Paste SVG path data from downloaded file here */}
      {/* Example structure - replace with actual SVG content: */}
      <path
        d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"
        fill="currentColor"
      />
    </svg>
  );
}
```

**Step 3: Export from icons index**
**File:** `src/components/icons/index.ts`
```typescript
export { OpenCodeIcon } from "./OpenCodeIcon";
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
import { OpenCodeIcon } from "@/components/icons/OpenCodeIcon";

export type AIProvider = "claude" | "gemini" | "codex" | "opencode" | "plain";

const providerConfig: Record<AIProvider, { icon: typeof BrainCircuit; label: string }> = {
  // ... existing providers
  opencode: { icon: OpenCodeIcon, label: "OpenCode" },
  // ...
};
```

**File:** `src/components/terminal/PreLaunchCard.tsx`
```typescript
import { OpenCodeIcon } from "@/components/icons/OpenCodeIcon";

const AI_MODES: { mode: AiMode; icon: typeof BrainCircuit; label: string; color: string }[] = [
  // ... existing modes
  { mode: "OpenCode", icon: OpenCodeIcon, label: "OpenCode", color: "text-purple-500" },
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
- [✅] OpenCodeIcon.tsx component created with SVG from dashboardicons.com
- [✅] User can select OpenCode from mode dropdown
- [✅] OpenCode icon (OpenCodeIcon component) and label display correctly in all UI components
- [✅] Install hint shown when OpenCode CLI not found
- [✅] Mode persists across session operations
- [✅] Unit tests for mode selection and mapping
- [ ] Manual testing on macOS, Windows, Linux

## Dependencies
- None (this is the foundation story)

## Open Questions
- Do we need to check for minimum OpenCode version?

## Resources
- **Website:** https://opencode.ai
- **Documentation:** https://opencode.ai/docs/
- **GitHub:** https://github.com/anomalyco/opencode
- **npm Package:** opencode-ai
