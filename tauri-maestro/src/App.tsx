import { invoke } from "@tauri-apps/api/core";
import { useCallback, useEffect, useRef, useState } from "react";
import { killSession } from "@/lib/terminal";
import { useOpenProject } from "@/lib/useOpenProject";
import { useSessionStore } from "@/stores/useSessionStore";
import { useWorkspaceStore } from "@/stores/useWorkspaceStore";
import { GitGraphPanel } from "./components/git/GitGraphPanel";
import { BottomBar } from "./components/shared/BottomBar";
import { FloatingAddButton } from "./components/shared/FloatingAddButton";
import { MultiProjectView, type MultiProjectViewHandle } from "./components/shared/MultiProjectView";
import { ProjectTabs } from "./components/shared/ProjectTabs";
import { TopBar } from "./components/shared/TopBar";
import { Sidebar } from "./components/sidebar/Sidebar";

const DEFAULT_SESSION_COUNT = 6;

type Theme = "dark" | "light";

function isValidTheme(value: string | null): value is Theme {
  return value === "dark" || value === "light";
}

function App() {
  const tabs = useWorkspaceStore((s) => s.tabs);
  const selectTab = useWorkspaceStore((s) => s.selectTab);
  const closeTab = useWorkspaceStore((s) => s.closeTab);
  const setSessionsLaunched = useWorkspaceStore((s) => s.setSessionsLaunched);
  const fetchSessions = useSessionStore((s) => s.fetchSessions);
  const initListeners = useSessionStore((s) => s.initListeners);
  const handleOpenProject = useOpenProject();
  const multiProjectRef = useRef<MultiProjectViewHandle>(null);
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [gitPanelOpen, setGitPanelOpen] = useState(false);
  const [sessionCounts, setSessionCounts] = useState<Map<string, number>>(new Map());
  const [currentBranch, setCurrentBranch] = useState<string | undefined>(undefined);
  const [theme, setTheme] = useState<Theme>(() => {
    const stored = localStorage.getItem("maestro-theme");
    return isValidTheme(stored) ? stored : "dark";
  });

  useEffect(() => {
    document.documentElement.setAttribute("data-theme", theme);
    localStorage.setItem("maestro-theme", theme);
  }, [theme]);

  // Initialize session store: fetch initial state and subscribe to events
  useEffect(() => {
    fetchSessions().catch((err) => {
      console.error("Failed to fetch sessions:", err);
    });

    const unlistenPromise = initListeners().catch((err) => {
      console.error("Failed to initialize listeners:", err);
      return () => {}; // no-op cleanup
    });

    return () => {
      unlistenPromise.then((unlisten) => unlisten());
    };
  }, [fetchSessions, initListeners]);

  const toggleTheme = () => setTheme((t) => (t === "dark" ? "light" : "dark"));
  const activeTab = tabs.find((tab) => tab.active) ?? null;
  const activeProjectPath = activeTab?.projectPath;

  useEffect(() => {
    let cancelled = false;
    if (!activeProjectPath) {
      setCurrentBranch(undefined);
      return () => {};
    }
    invoke<string>("git_current_branch", { repoPath: activeProjectPath })
      .then((branch) => {
        if (!cancelled) setCurrentBranch(branch);
      })
      .catch((err) => {
        console.error("Failed to load current branch:", err);
        if (!cancelled) setCurrentBranch(undefined);
      });
    return () => {
      cancelled = true;
    };
  }, [activeProjectPath]);

  // Derive state from active tab
  const activeTabSessionsLaunched = activeTab?.sessionsLaunched ?? false;
  const activeTabSessionCount = activeTab ? (sessionCounts.get(activeTab.id) ?? 0) : 0;

  // Handler to launch a session for the active project
  const handleAddSession = () => {
    if (activeTab) {
      setSessionsLaunched(activeTab.id, true);
    }
  };

  const handleSessionCountChange = useCallback((tabId: string, count: number) => {
    setSessionCounts((prev) => {
      const next = new Map(prev);
      next.set(tabId, count);
      return next;
    });
  }, []);

  return (
    <div className="flex h-screen w-screen flex-col bg-maestro-bg">
      {/* Project tabs — full width at top (with window controls) */}
      <ProjectTabs
        tabs={tabs.map((t) => ({ id: t.id, name: t.name, active: t.active }))}
        onSelectTab={selectTab}
        onCloseTab={closeTab}
        onNewTab={handleOpenProject}
        onToggleSidebar={() => setSidebarOpen((prev) => !prev)}
        sidebarOpen={sidebarOpen}
      />

      {/* Main area: sidebar + content */}
      <div className="flex flex-1 overflow-hidden">
        {/* Sidebar — below project tabs */}
        <Sidebar
          collapsed={!sidebarOpen}
          onCollapse={() => setSidebarOpen(false)}
          theme={theme}
          onToggleTheme={toggleTheme}
        />

        {/* Right column: top bar + content + bottom bar */}
        <div className="flex flex-1 flex-col overflow-hidden">
          {/* Top bar (branch selector, settings - no window controls since ProjectTabs has them) */}
          <TopBar
            sidebarOpen={sidebarOpen}
            onToggleSidebar={() => setSidebarOpen((prev) => !prev)}
            branchName={currentBranch}
            repoPath={activeTab ? activeTab.projectPath : undefined}
            onToggleGitPanel={() => setGitPanelOpen((prev) => !prev)}
            gitPanelOpen={gitPanelOpen}
            hideWindowControls
          />

          {/* Content area (main + optional git panel) */}
          <div className="flex flex-1 overflow-hidden">
            {/* Main content - MultiProjectView keeps all projects alive */}
            <main className="relative flex-1 overflow-hidden bg-maestro-bg">
              <MultiProjectView
                ref={multiProjectRef}
                onSessionCountChange={handleSessionCountChange}
              />
            </main>

            {/* Git graph panel (optional right side) */}
            <GitGraphPanel open={gitPanelOpen} onClose={() => setGitPanelOpen(false)} />
          </div>

          {/* Bottom action bar */}
          <div className="bg-maestro-bg">
            <BottomBar
              sessionsActive={activeTabSessionsLaunched}
              sessionCount={activeTabSessionCount}
              onSelectDirectory={handleOpenProject}
              onLaunchAll={handleAddSession}
              onStopAll={async () => {
                if (!activeTab) return;
                // Kill all running sessions for this project via the session store
                const sessionStore = useSessionStore.getState();
                const projectSessions = sessionStore.getSessionsByProject(activeTab.projectPath);
                const results = await Promise.allSettled(projectSessions.map((s) => killSession(s.id)));
                for (const result of results) {
                  if (result.status === "rejected") {
                    console.error("Failed to stop session:", result.reason);
                  }
                }
                setSessionsLaunched(activeTab.id, false);
                setSessionCounts((prev) => {
                  const next = new Map(prev);
                  next.set(activeTab.id, 0);
                  return next;
                });
              }}
            />
          </div>
        </div>
      </div>

      {/* Floating add session button (only when sessions active and below max) */}
      {activeTabSessionsLaunched && activeTabSessionCount < DEFAULT_SESSION_COUNT && (
        <FloatingAddButton onClick={() => multiProjectRef.current?.addSessionToActiveProject()} />
      )}
    </div>
  );
}

export default App;
