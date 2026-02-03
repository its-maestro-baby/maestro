import { LazyStore } from "@tauri-apps/plugin-store";
import { create } from "zustand";
import { createJSONStorage, persist, type StateStorage } from "zustand/middleware";
import {
  type AvailableFont,
  EMBEDDED_FONT,
  getAvailableFonts,
  selectBestFont,
} from "@/lib/fonts";

// --- Types ---

/** Terminal font and display settings. */
export type TerminalSettings = {
  /** The selected font family name. */
  fontFamily: string;
  /** Font size in pixels. */
  fontSize: number;
  /** Line height multiplier (1.0 = 100%). */
  lineHeight: number;
};

/** Read-only slice of the terminal settings store; persisted to disk. */
type TerminalSettingsState = {
  settings: TerminalSettings;
  availableFonts: AvailableFont[];
  isLoading: boolean;
  isInitialized: boolean;
};

/** Actions for managing terminal settings. */
type TerminalSettingsActions = {
  /** Initialize the store by detecting available fonts. */
  initialize: () => Promise<void>;
  /** Update a specific setting. */
  setSetting: <K extends keyof TerminalSettings>(
    key: K,
    value: TerminalSettings[K]
  ) => void;
  /** Reset all settings to defaults. */
  resetToDefaults: () => void;
  /** Get the current font family, falling back to embedded if needed. */
  getEffectiveFontFamily: () => string;
};

// --- Default Settings ---

const DEFAULT_SETTINGS: TerminalSettings = {
  fontFamily: EMBEDDED_FONT,
  fontSize: 14,
  lineHeight: 1.2,
};

// --- Tauri LazyStore-backed StateStorage adapter ---

/**
 * Singleton LazyStore instance for terminal settings.
 * Stored separately from the main store.json to keep concerns separate.
 */
const lazyStore = new LazyStore("terminal-settings.json");

/**
 * Zustand-compatible StateStorage adapter backed by the Tauri plugin-store.
 */
const tauriStorage: StateStorage = {
  getItem: async (name: string): Promise<string | null> => {
    try {
      const value = await lazyStore.get<string>(name);
      return value ?? null;
    } catch (err) {
      console.error(`tauriStorage.getItem("${name}") failed:`, err);
      return null;
    }
  },
  setItem: async (name: string, value: string): Promise<void> => {
    try {
      await lazyStore.set(name, value);
      await lazyStore.save();
    } catch (err) {
      console.error(`tauriStorage.setItem("${name}") failed:`, err);
      throw err;
    }
  },
  removeItem: async (name: string): Promise<void> => {
    try {
      await lazyStore.delete(name);
      await lazyStore.save();
    } catch (err) {
      console.error(`tauriStorage.removeItem("${name}") failed:`, err);
      throw err;
    }
  },
};

// --- Store ---

/**
 * Global store for terminal display settings.
 *
 * Manages font family, font size, and line height settings with persistence.
 * Automatically detects available system fonts on initialization.
 */
export const useTerminalSettingsStore = create<
  TerminalSettingsState & TerminalSettingsActions
>()(
  persist(
    (set, get) => ({
      settings: DEFAULT_SETTINGS,
      availableFonts: [],
      isLoading: false,
      isInitialized: false,

      initialize: async () => {
        const { isInitialized, isLoading } = get();
        if (isInitialized || isLoading) return;

        set({ isLoading: true });

        try {
          const fonts = await getAvailableFonts();
          const currentSettings = get().settings;

          // If user hasn't set a custom font, auto-select the best one
          const shouldAutoSelect = currentSettings.fontFamily === EMBEDDED_FONT;
          const bestFont = shouldAutoSelect ? selectBestFont(fonts) : currentSettings.fontFamily;

          // Check if the currently selected font is still available
          const currentFontAvailable =
            currentSettings.fontFamily === EMBEDDED_FONT ||
            fonts.some((f) => f.family === currentSettings.fontFamily);

          set({
            availableFonts: fonts,
            isLoading: false,
            isInitialized: true,
            settings: {
              ...currentSettings,
              fontFamily: currentFontAvailable ?
                (shouldAutoSelect ? bestFont : currentSettings.fontFamily) :
                EMBEDDED_FONT,
            },
          });
        } catch (err) {
          console.error("Failed to initialize terminal settings:", err);
          set({
            availableFonts: [],
            isLoading: false,
            isInitialized: true,
          });
        }
      },

      setSetting: (key, value) => {
        set({
          settings: {
            ...get().settings,
            [key]: value,
          },
        });
      },

      resetToDefaults: () => {
        const { availableFonts } = get();
        // When resetting, auto-select the best font if we have detected fonts
        const fontFamily = availableFonts.length > 0
          ? selectBestFont(availableFonts)
          : DEFAULT_SETTINGS.fontFamily;

        set({
          settings: {
            ...DEFAULT_SETTINGS,
            fontFamily,
          },
        });
      },

      getEffectiveFontFamily: () => {
        const { settings, availableFonts } = get();

        // If the selected font is the embedded font, always use it
        if (settings.fontFamily === EMBEDDED_FONT) {
          return EMBEDDED_FONT;
        }

        // Check if the selected font is available
        const isAvailable = availableFonts.some(
          (f) => f.family === settings.fontFamily
        );

        return isAvailable ? settings.fontFamily : EMBEDDED_FONT;
      },
    }),
    {
      name: "maestro-terminal-settings",
      storage: createJSONStorage(() => tauriStorage),
      partialize: (state) => ({ settings: state.settings }),
      version: 1,
    }
  )
);
