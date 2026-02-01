import { useRef, useCallback, forwardRef, useImperativeHandle } from "react";
import { useWorkspaceStore } from "@/stores/useWorkspaceStore";
import { IdleLandingView } from "./IdleLandingView";
import { SessionPodGrid } from "../terminal/SessionPodGrid";
import { TerminalGrid, type TerminalGridHandle } from "../terminal/TerminalGrid";

const DEFAULT_SESSION_COUNT = 6;

interface MultiProjectViewProps {
  onSessionCountChange?: (tabId: string, slotCount: number, launchedCount: number) => void;
}

export interface MultiProjectViewHandle {
  addSessionToActiveProject: () => void;
  launchAllInActiveProject: () => Promise<void>;
}

/**
 * Root content view that renders ALL open projects simultaneously.
 * Uses CSS opacity/pointer-events to show only the active project
 * while keeping terminal state alive in inactive projects (ZStack pattern).
 *
 * This is modeled after the Swift app's MultiProjectContentView which
 * uses a ZStack to preserve terminal NSView state across project switches.
 */
export const MultiProjectView = forwardRef<MultiProjectViewHandle, MultiProjectViewProps>(
  function MultiProjectView({ onSessionCountChange }, ref) {
  const tabs = useWorkspaceStore((s) => s.tabs);
  const setSessionsLaunched = useWorkspaceStore((s) => s.setSessionsLaunched);
  const gridRefs = useRef<Map<string, TerminalGridHandle>>(new Map());

  // Expose methods to parent
  useImperativeHandle(ref, () => ({
    addSessionToActiveProject: () => {
      const activeTab = tabs.find((t) => t.active);
      if (activeTab) {
        const gridRef = gridRefs.current.get(activeTab.id);
        gridRef?.addSession();
      }
    },
    launchAllInActiveProject: async () => {
      const activeTab = tabs.find((t) => t.active);
      if (activeTab) {
        const gridRef = gridRefs.current.get(activeTab.id);
        await gridRef?.launchAll();
      }
    },
  }), [tabs]);

  const handleSessionCountChange = useCallback(
    (tabId: string) => (slotCount: number, launchedCount: number) => {
      onSessionCountChange?.(tabId, slotCount, launchedCount);
    },
    [onSessionCountChange]
  );

  const handleLaunch = useCallback(
    (tabId: string) => () => {
      setSessionsLaunched(tabId, true);
    },
    [setSessionsLaunched]
  );

  const setGridRef = useCallback(
    (tabId: string) => (handle: TerminalGridHandle | null) => {
      if (handle) {
        gridRefs.current.set(tabId, handle);
      } else {
        gridRefs.current.delete(tabId);
      }
    },
    []
  );

  // No projects open - show placeholder grid
  if (tabs.length === 0) {
    return <SessionPodGrid sessionCount={DEFAULT_SESSION_COUNT} />;
  }

  return (
    <div className="relative h-full w-full">
      {/* Render ALL project views in a stacked container (ZStack equivalent) */}
      {tabs.map((tab) => (
        <div
          key={tab.id}
          className={`absolute inset-0 transition-opacity duration-150 ${
            tab.active
              ? "opacity-100 pointer-events-auto z-10"
              : "opacity-0 pointer-events-none z-0"
          }`}
          style={{
            // Keep in DOM but visually hidden when inactive
            visibility: tab.active ? "visible" : "hidden",
          }}
        >
          {tab.sessionsLaunched ? (
            <TerminalGrid
              ref={setGridRef(tab.id)}
              tabId={tab.id}
              projectPath={tab.projectPath}
              preserveOnHide={true}
              onSessionCountChange={handleSessionCountChange(tab.id)}
            />
          ) : (
            <IdleLandingView onAdd={handleLaunch(tab.id)} />
          )}
        </div>
      ))}
    </div>
  );
});

/**
 * Get a grid handle for a specific tab to call addSession.
 */
export function useMultiProjectGridRef() {
  const gridRefs = useRef<Map<string, TerminalGridHandle>>(new Map());

  return {
    getGridRef: (tabId: string) => gridRefs.current.get(tabId),
    setGridRef: (tabId: string, handle: TerminalGridHandle | null) => {
      if (handle) {
        gridRefs.current.set(tabId, handle);
      } else {
        gridRefs.current.delete(tabId);
      }
    },
  };
}
