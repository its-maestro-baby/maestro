import { useEffect } from "react";

interface UseTerminalKeyboardOptions {
  /** Total number of launched terminals */
  terminalCount: number;
  /** Currently focused terminal index (0-based), or null if none focused */
  focusedIndex: number | null;
  /** Callback to focus a specific terminal by index */
  onFocusTerminal: (index: number) => void;
  /** Callback to cycle to the next terminal */
  onCycleNext: () => void;
  /** Callback to cycle to the previous terminal */
  onCyclePrevious: () => void;
}

/**
 * Detect whether the current platform uses Cmd (Mac) or Ctrl (Windows/Linux) as the modifier key.
 */
function isMac(): boolean {
  return navigator.platform.toLowerCase().includes("mac");
}

/**
 * Global keyboard shortcut handler for terminal navigation.
 *
 * Shortcuts:
 * - Cmd/Ctrl+1-9,0: Jump to terminal N (1-9 for terminals 1-9, 0 for terminal 10)
 * - Cmd/Ctrl+[: Cycle to previous terminal
 * - Cmd/Ctrl+]: Cycle to next terminal
 */
export function useTerminalKeyboard({
  terminalCount,
  focusedIndex,
  onFocusTerminal,
  onCycleNext,
  onCyclePrevious,
}: UseTerminalKeyboardOptions): void {
  useEffect(() => {
    if (terminalCount === 0) return;

    function handleKeyDown(event: KeyboardEvent) {
      const modifierKey = isMac() ? event.metaKey : event.ctrlKey;
      if (!modifierKey) return;

      // Don't interfere with other modifier combinations
      if (event.altKey || event.shiftKey) return;

      // Handle number keys 1-9 and 0 for terminal jumping
      if (event.key >= "1" && event.key <= "9") {
        const targetIndex = parseInt(event.key, 10) - 1;
        if (targetIndex < terminalCount) {
          event.preventDefault();
          onFocusTerminal(targetIndex);
        }
        return;
      }

      if (event.key === "0") {
        // 0 maps to terminal 10 (index 9)
        const targetIndex = 9;
        if (targetIndex < terminalCount) {
          event.preventDefault();
          onFocusTerminal(targetIndex);
        }
        return;
      }

      // Handle bracket keys for cycling
      if (event.key === "]") {
        event.preventDefault();
        onCycleNext();
        return;
      }

      if (event.key === "[") {
        event.preventDefault();
        onCyclePrevious();
        return;
      }
    }

    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [terminalCount, focusedIndex, onFocusTerminal, onCycleNext, onCyclePrevious]);
}
