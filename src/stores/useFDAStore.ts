import { create } from "zustand";
import { checkFullDiskAccess, pathRequiresFDA } from "@/lib/permissions";

const FDA_DISMISSED_KEY = "maestro:permissions:fda-dismissed";

interface FDAState {
  showDialog: boolean;
  pendingPath: string | null;
  pendingCallback: (() => void) | null;

  /**
   * Check if a path needs FDA and show the dialog if access is missing.
   * If FDA is not needed or already granted, calls `onGranted` immediately.
   * If FDA is needed but missing, shows the dialog and stores the callback.
   */
  requireAccess: (path: string, onGranted: () => void) => Promise<void>;

  /** Dismiss the FDA dialog (single time). */
  dismiss: () => void;

  /** Dismiss the FDA dialog and remember the choice. */
  dismissPermanently: () => void;

  /** Re-check FDA after the user says they granted it, then invoke the pending callback. */
  retryAfterGrant: () => Promise<void>;
}

export const useFDAStore = create<FDAState>((set, get) => ({
  showDialog: false,
  pendingPath: null,
  pendingCallback: null,

  requireAccess: async (path, onGranted) => {
    const needsFDA = pathRequiresFDA(path);
    if (!needsFDA) {
      onGranted();
      return;
    }

    const hasAccess = await checkFullDiskAccess();
    if (hasAccess) {
      // Clear stale dismissed flag if FDA was granted since it was set
      localStorage.removeItem(FDA_DISMISSED_KEY);
      onGranted();
      return;
    }

    // Check if user previously dismissed permanently
    const dismissed = localStorage.getItem(FDA_DISMISSED_KEY);
    if (dismissed) {
      // Re-check — user may have granted FDA since dismissing
      const nowHasAccess = await checkFullDiskAccess();
      if (nowHasAccess) {
        localStorage.removeItem(FDA_DISMISSED_KEY);
        onGranted();
        return;
      }
      // Still no access but user doesn't want the dialog — proceed anyway
      onGranted();
      return;
    }

    // Show dialog and store callback for later
    set({ showDialog: true, pendingPath: path, pendingCallback: onGranted });
  },

  dismiss: () => {
    set({ showDialog: false, pendingPath: null, pendingCallback: null });
  },

  dismissPermanently: () => {
    localStorage.setItem(FDA_DISMISSED_KEY, "true");
    set({ showDialog: false, pendingPath: null, pendingCallback: null });
  },

  retryAfterGrant: async () => {
    const { pendingCallback } = get();
    const hasAccess = await checkFullDiskAccess();
    if (hasAccess) {
      localStorage.removeItem(FDA_DISMISSED_KEY);
      set({ showDialog: false, pendingPath: null, pendingCallback: null });
      pendingCallback?.();
    }
    // If still no access, keep dialog open
  },
}));
