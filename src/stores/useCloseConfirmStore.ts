import { create } from "zustand";

export interface CloseConfirmRequest {
  /** Title shown in dialog header */
  title: string;
  /** Description message */
  message: string;
  /** Label for confirm button */
  confirmLabel?: string;
  /** Resolve callback — true = confirmed, false = cancelled */
  resolve: (confirmed: boolean) => void;
}

interface CloseConfirmState {
  /** Current pending request, or null if dialog is hidden */
  request: CloseConfirmRequest | null;
  /** User preference: skip confirmation dialogs */
  skipConfirm: boolean;
  /** Show the confirmation dialog. Returns a promise that resolves when user responds. */
  confirm: (title: string, message: string, confirmLabel?: string) => Promise<boolean>;
  /** User clicked confirm */
  accept: () => void;
  /** User clicked cancel */
  cancel: () => void;
  /** Toggle "Don't ask again" */
  setSkipConfirm: (skip: boolean) => void;
}

export const useCloseConfirmStore = create<CloseConfirmState>((set, get) => ({
  request: null,
  skipConfirm: localStorage.getItem("maestro-skip-close-confirm") === "true",

  confirm: (title, message, confirmLabel) => {
    // If user opted out of confirmations, auto-confirm
    if (get().skipConfirm) return Promise.resolve(true);

    return new Promise<boolean>((resolve) => {
      set({ request: { title, message, confirmLabel, resolve } });
    });
  },

  accept: () => {
    const req = get().request;
    if (req) {
      req.resolve(true);
      set({ request: null });
    }
  },

  cancel: () => {
    const req = get().request;
    if (req) {
      req.resolve(false);
      set({ request: null });
    }
  },

  setSkipConfirm: (skip) => {
    localStorage.setItem("maestro-skip-close-confirm", String(skip));
    set({ skipConfirm: skip });
  },
}));
