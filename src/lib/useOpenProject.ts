import { useCallback, useState } from "react";
import { pickProjectFolder } from "@/lib/dialog";
import { ensurePathAccess, checkFullDiskAccess } from "@/lib/permissions";
import { useWorkspaceStore } from "@/stores/useWorkspaceStore";

const FDA_DISMISSED_KEY = "maestro:permissions:fda-dismissed";

/**
 * Hook for opening project folders with macOS FDA permission handling.
 *
 * On macOS, if the user selects a TCC-protected path (Desktop, Documents,
 * Downloads) and the app lacks Full Disk Access, shows a dialog explaining
 * how to grant permission.
 */
export function useOpenProject(): {
  openProject: () => Promise<void>;
  showFDADialog: boolean;
  fdaPath: string | null;
  dismissFDADialog: () => void;
  dismissFDADialogPermanently: () => void;
  retryAfterFDAGrant: () => Promise<void>;
} {
  const openProjectToWorkspace = useWorkspaceStore((s) => s.openProject);
  const [showFDADialog, setShowFDADialog] = useState(false);
  const [pendingPath, setPendingPath] = useState<string | null>(null);

  const dismissFDADialog = useCallback(() => {
    setShowFDADialog(false);
    setPendingPath(null);
  }, []);

  const dismissFDADialogPermanently = useCallback(() => {
    localStorage.setItem(FDA_DISMISSED_KEY, "true");
    setShowFDADialog(false);
    setPendingPath(null);
  }, []);

  /**
   * Re-check FDA and open the project if access was granted.
   * Called after user says they've granted permission in System Settings.
   */
  const retryAfterFDAGrant = useCallback(async () => {
    if (!pendingPath) return;

    const hasAccess = await checkFullDiskAccess();
    if (hasAccess) {
      openProjectToWorkspace(pendingPath);
      setShowFDADialog(false);
      setPendingPath(null);
    }
    // If still no access, keep dialog open - user can try again or dismiss
  }, [pendingPath, openProjectToWorkspace]);

  const openProject = useCallback(async () => {
    try {
      const path = await pickProjectFolder();
      if (!path) return;

      // Check if this path requires FDA
      const { hasAccess, needsFDA } = await ensurePathAccess(path);

      if (needsFDA && !hasAccess) {
        // Check if user previously dismissed the dialog permanently
        const dismissed = localStorage.getItem(FDA_DISMISSED_KEY);
        if (dismissed) {
          // Re-check - user may have granted FDA since dismissing
          const nowHasAccess = await checkFullDiskAccess();
          if (nowHasAccess) {
            localStorage.removeItem(FDA_DISMISSED_KEY);
          }
          openProjectToWorkspace(path);
          return;
        }

        // Show FDA dialog with the path that triggered it
        setPendingPath(path);
        setShowFDADialog(true);
        return;
      }

      // No FDA needed or already have access - open directly
      openProjectToWorkspace(path);
    } catch (err) {
      console.error("Failed to open project folder:", err);
    }
  }, [openProjectToWorkspace]);

  return {
    openProject,
    showFDADialog,
    fdaPath: pendingPath,
    dismissFDADialog,
    dismissFDADialogPermanently,
    retryAfterFDAGrant,
  };
}
