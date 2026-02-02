import { useCallback } from "react";
import { pickProjectFolder } from "@/lib/dialog";
import { useWorkspaceStore } from "@/stores/useWorkspaceStore";

/**
 * Returns an async callback that opens the native folder picker dialog and,
 * if the user selects a folder, adds it as a workspace tab.
 *
 * Silently no-ops when the user cancels the dialog (path is null).
 * Logs to console on IPC or dialog errors rather than surfacing to the UI.
 */
export function useOpenProject(): () => Promise<void> {
  const openProject = useWorkspaceStore((s) => s.openProject);

  return useCallback(async () => {
    try {
      const path = await pickProjectFolder();
      if (path) {
        await openProject(path);
      }
    } catch (err) {
      console.error("Failed to open project folder:", err);
      // TODO: Wire to toast notification when toast system is added
    }
  }, [openProject]);
}
