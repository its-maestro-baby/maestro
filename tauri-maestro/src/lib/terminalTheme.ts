/**
 * Unified terminal theme system for Maestro.
 *
 * Provides a single source of truth for terminal colors that can be
 * converted to different backend formats (xterm.js, Ghostty, etc.).
 */

import type { ITheme } from "@xterm/xterm";

/**
 * Platform-independent terminal color theme definition.
 * Based on GitHub Dark theme colors.
 */
export interface TerminalTheme {
  /** Background color */
  background: string;
  /** Default text color */
  foreground: string;
  /** Cursor color */
  cursor: string;
  /** Cursor text color (text under cursor) */
  cursorAccent?: string;
  /** Selection background color */
  selectionBackground: string;
  /** Selection foreground color */
  selectionForeground?: string;

  /** Standard ANSI colors (0-7) */
  black: string;
  red: string;
  green: string;
  yellow: string;
  blue: string;
  magenta: string;
  cyan: string;
  white: string;

  /** Bright ANSI colors (8-15) */
  brightBlack: string;
  brightRed: string;
  brightGreen: string;
  brightYellow: string;
  brightBlue: string;
  brightMagenta: string;
  brightCyan: string;
  brightWhite: string;
}

/**
 * Maestro's default terminal theme (GitHub Dark inspired).
 */
export const DEFAULT_THEME: TerminalTheme = {
  background: "#0d1117",
  foreground: "#e6edf3",
  cursor: "#58a6ff",
  cursorAccent: "#0d1117",
  selectionBackground: "#264f78",
  selectionForeground: undefined,

  // Standard colors
  black: "#484f58",
  red: "#f85149",
  green: "#3fb950",
  yellow: "#d29922",
  blue: "#58a6ff",
  magenta: "#bc8cff",
  cyan: "#76e3ea",
  white: "#e6edf3",

  // Bright colors
  brightBlack: "#6e7681",
  brightRed: "#ffa198",
  brightGreen: "#56d364",
  brightYellow: "#e3b341",
  brightBlue: "#79c0ff",
  brightMagenta: "#d2a8ff",
  brightCyan: "#b3f0ff",
  brightWhite: "#f0f6fc",
};

/**
 * Light terminal theme (GitHub Light inspired).
 */
export const LIGHT_THEME: TerminalTheme = {
  background: "#ffffff",
  foreground: "#24292f",
  cursor: "#0969da",
  cursorAccent: "#ffffff",
  selectionBackground: "#0969da33",
  selectionForeground: undefined,

  // Standard colors (GitHub Light palette)
  black: "#24292f",
  red: "#cf222e",
  green: "#116329",
  yellow: "#9a6700",
  blue: "#0969da",
  magenta: "#8250df",
  cyan: "#1b7c83",
  white: "#6e7781",

  // Bright colors
  brightBlack: "#57606a",
  brightRed: "#a40e26",
  brightGreen: "#1a7f37",
  brightYellow: "#7d4e00",
  brightBlue: "#218bff",
  brightMagenta: "#a475f9",
  brightCyan: "#3192aa",
  brightWhite: "#8c959f",
};

/**
 * Converts a TerminalTheme to xterm.js ITheme format.
 */
export function toXtermTheme(theme: TerminalTheme): ITheme {
  return {
    background: theme.background,
    foreground: theme.foreground,
    cursor: theme.cursor,
    cursorAccent: theme.cursorAccent,
    selectionBackground: theme.selectionBackground,
    selectionForeground: theme.selectionForeground,
    black: theme.black,
    red: theme.red,
    green: theme.green,
    yellow: theme.yellow,
    blue: theme.blue,
    magenta: theme.magenta,
    cyan: theme.cyan,
    white: theme.white,
    brightBlack: theme.brightBlack,
    brightRed: theme.brightRed,
    brightGreen: theme.brightGreen,
    brightYellow: theme.brightYellow,
    brightBlue: theme.brightBlue,
    brightMagenta: theme.brightMagenta,
    brightCyan: theme.brightCyan,
    brightWhite: theme.brightWhite,
  };
}

/**
 * Converts a hex color to RGB components.
 */
function hexToRgb(hex: string): { r: number; g: number; b: number } | null {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  return result
    ? {
        r: parseInt(result[1], 16),
        g: parseInt(result[2], 16),
        b: parseInt(result[3], 16),
      }
    : null;
}

/**
 * Converts a TerminalTheme to Ghostty config format.
 * Returns a string that can be used in a Ghostty config file.
 */
export function toGhosttyConfig(theme: TerminalTheme): string {
  const lines: string[] = [];

  const addColor = (name: string, hex: string) => {
    const rgb = hexToRgb(hex);
    if (rgb) {
      lines.push(`${name} = ${rgb.r}, ${rgb.g}, ${rgb.b}`);
    }
  };

  addColor("background", theme.background);
  addColor("foreground", theme.foreground);
  addColor("cursor-color", theme.cursor);
  addColor("selection-background", theme.selectionBackground);

  // Palette colors (0-15)
  addColor("palette = 0", theme.black);
  addColor("palette = 1", theme.red);
  addColor("palette = 2", theme.green);
  addColor("palette = 3", theme.yellow);
  addColor("palette = 4", theme.blue);
  addColor("palette = 5", theme.magenta);
  addColor("palette = 6", theme.cyan);
  addColor("palette = 7", theme.white);
  addColor("palette = 8", theme.brightBlack);
  addColor("palette = 9", theme.brightRed);
  addColor("palette = 10", theme.brightGreen);
  addColor("palette = 11", theme.brightYellow);
  addColor("palette = 12", theme.brightBlue);
  addColor("palette = 13", theme.brightMagenta);
  addColor("palette = 14", theme.brightCyan);
  addColor("palette = 15", theme.brightWhite);

  return lines.join("\n");
}

/**
 * Terminal backend type as reported by the Rust backend.
 */
export type BackendType = "xterm-passthrough" | "vte-parser";

/**
 * Backend capabilities as reported by the Rust backend.
 */
export interface BackendCapabilities {
  /** Backend supports enhanced terminal state queries */
  enhancedState: boolean;
  /** Backend supports text reflow on resize */
  textReflow: boolean;
  /** Backend supports Kitty graphics protocol */
  kittyGraphics: boolean;
  /** Backend supports shell integration hooks */
  shellIntegration: boolean;
  /** Name of the backend implementation */
  backendName: string;
}

/**
 * Terminal state as reported by backends that support it.
 */
export interface TerminalState {
  /** Current cursor row position (0-indexed) */
  cursorRow: number;
  /** Current cursor column position (0-indexed) */
  cursorCol: number;
  /** Cursor shape */
  cursorShape: "block" | "underline" | "bar";
  /** Whether the cursor is visible */
  cursorVisible: boolean;
  /** Current scrollback position (lines from bottom) */
  scrollbackPosition: number;
  /** Total lines in scrollback buffer */
  scrollbackTotal: number;
  /** Terminal title (set by shell escape sequences) */
  title: string | null;
}
