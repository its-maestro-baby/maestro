import { forwardRef, useCallback, useEffect, useImperativeHandle, useRef, useState } from "react";

import { getBranchesWithWorktreeStatus, type BranchWithWorktreeStatus } from "@/lib/git";
import { setSessionMcpServers, type McpServerConfig } from "@/lib/mcp";
import { setSessionSkills, setSessionPlugins, type PluginConfig, type SkillConfig } from "@/lib/plugins";
import {
  AI_CLI_CONFIG,
  assignSessionBranch,
  checkCliAvailable,
  createSession,
  killSession,
  spawnShell,
  writeStdin,
} from "@/lib/terminal";
import { cleanupSessionWorktree, prepareSessionWorktree } from "@/lib/worktreeManager";
import { useMcpStore } from "@/stores/useMcpStore";
import { usePluginStore } from "@/stores/usePluginStore";
import { useSessionStore } from "@/stores/useSessionStore";
import type { AiMode } from "@/stores/useSessionStore";
import { useWorkspaceStore } from "@/stores/useWorkspaceStore";
import { PreLaunchCard, type SessionSlot } from "./PreLaunchCard";
import { TerminalView } from "./TerminalView";

/** Stable empty arrays to avoid infinite re-render loops in Zustand selectors. */
const EMPTY_MCP_SERVERS: McpServerConfig[] = [];
const EMPTY_SKILLS: SkillConfig[] = [];
const EMPTY_PLUGINS: PluginConfig[] = [];

/** Hard ceiling on concurrent PTY sessions per grid to bound resource usage. */
const MAX_SESSIONS = 6;

/**
 * Returns Tailwind grid-cols/grid-rows classes that produce a compact layout
 * for the given session count (1x1, 2x1, 3x1, 2x2, 3x2, etc.).
 */
function gridClass(count: number): string {
  if (count <= 1) return "grid-cols-1 grid-rows-1";
  if (count === 2) return "grid-cols-2 grid-rows-1";
  if (count === 3) return "grid-cols-3 grid-rows-1";
  if (count === 4) return "grid-cols-2 grid-rows-2";
  if (count <= 6) return "grid-cols-3 grid-rows-2";
  if (count <= 9) return "grid-cols-3 grid-rows-3";
  if (count <= 12) return "grid-cols-4 grid-rows-3";
  return "grid-cols-4";
}

/** Generates a unique ID for a new session slot. */
function generateSlotId(): string {
  return `slot-${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;
}

/** Creates a new empty session slot with default configuration. */
function createEmptySlot(
  mcpServers: McpServerConfig[] = [],
  skills: SkillConfig[] = [],
  plugins: PluginConfig[] = []
): SessionSlot {
  return {
    id: generateSlotId(),
    mode: "Claude",
    branch: null,
    sessionId: null,
    worktreePath: null,
    enabledMcpServers: mcpServers.map((s) => s.name), // All enabled by default
    enabledSkills: skills.map((s) => s.id), // All enabled by default
    enabledPlugins: plugins.filter((p) => p.enabled_by_default).map((p) => p.id),
  };
}

/**
 * Imperative handle exposed via `useImperativeHandle` so parent components
 * (e.g. a toolbar button) can add sessions or launch all without lifting state up.
 */
export interface TerminalGridHandle {
  addSession: () => void;
  launchAll: () => Promise<void>;
}

/**
 * @property projectPath - Working directory passed to `spawnShell`; when absent the backend
 *   uses its own default cwd.
 * @property tabId - Workspace tab ID for session-project association.
 * @property preserveOnHide - If true, don't kill sessions when component unmounts (for project switching).
 * @property onSessionCountChange - Fires whenever session counts change,
 *   providing both total slot count and launched session count.
 */
interface TerminalGridProps {
  projectPath?: string;
  tabId?: string;
  preserveOnHide?: boolean;
  onSessionCountChange?: (slotCount: number, launchedCount: number) => void;
}

/**
 * Manages a dynamic grid of session slots that can be either:
 * - Pre-launch cards (allowing user to configure AI mode and branch before launching)
 * - Active terminal views (connected to a backend PTY session)
 *
 * Lifecycle:
 * - On mount, creates a single empty slot for the user to configure.
 * - User configures AI mode and branch, then clicks "Launch" to spawn a shell.
 * - `addSession` creates new pre-launch slots up to MAX_SESSIONS.
 * - "Launch All" spawns all unlaunched slots with their configured settings.
 * - When all sessions are killed by the user, an auto-respawn effect creates
 *   a fresh slot so the user is never left with an empty grid.
 */
export const TerminalGrid = forwardRef<TerminalGridHandle, TerminalGridProps>(function TerminalGrid(
  { projectPath, tabId, preserveOnHide = false, onSessionCountChange },
  ref,
) {
  const addSessionToProject = useWorkspaceStore((s) => s.addSessionToProject);
  const removeSessionFromProject = useWorkspaceStore((s) => s.removeSessionFromProject);

  // MCP store - use stable empty array reference to avoid infinite re-render loops
  const mcpServers = useMcpStore((s) =>
    projectPath ? (s.projectServers[projectPath] ?? EMPTY_MCP_SERVERS) : EMPTY_MCP_SERVERS
  );
  const fetchMcpServers = useMcpStore((s) => s.fetchProjectServers);

  // Plugin store - use stable empty array references
  const skills = usePluginStore((s) =>
    projectPath ? (s.projectSkills[projectPath] ?? EMPTY_SKILLS) : EMPTY_SKILLS
  );
  const plugins = usePluginStore((s) =>
    projectPath ? (s.projectPlugins[projectPath] ?? EMPTY_PLUGINS) : EMPTY_PLUGINS
  );
  const fetchPlugins = usePluginStore((s) => s.fetchProjectPlugins);

  // Track session slots (pre-launch and launched)
  const [slots, setSlots] = useState<SessionSlot[]>(() => [createEmptySlot()]);
  const [error, setError] = useState<string | null>(null);

  // Git branch data
  const [branches, setBranches] = useState<BranchWithWorktreeStatus[]>([]);
  const [isLoadingBranches, setIsLoadingBranches] = useState(false);
  const [isGitRepo, setIsGitRepo] = useState(true);

  // Refs for cleanup
  const slotsRef = useRef<SessionSlot[]>([]);
  const mounted = useRef(false);

  // Sync refs with state and report counts to parent
  useEffect(() => {
    slotsRef.current = slots;
    const launchedCount = slots.filter((s) => s.sessionId !== null).length;
    onSessionCountChange?.(slots.length, launchedCount);
  }, [slots, onSessionCountChange]);

  // Fetch branches and MCP servers when projectPath is available
  useEffect(() => {
    if (!projectPath) {
      setIsGitRepo(false);
      return;
    }

    setIsLoadingBranches(true);
    getBranchesWithWorktreeStatus(projectPath)
      .then((branchList) => {
        setBranches(branchList);
        setIsGitRepo(true);
        setIsLoadingBranches(false);
      })
      .catch((err) => {
        console.error("Failed to fetch branches:", err);
        setIsGitRepo(false);
        setIsLoadingBranches(false);
      });

    // Fetch MCP servers
    fetchMcpServers(projectPath).catch(console.error);

    // Fetch plugins/skills
    fetchPlugins(projectPath).catch(console.error);
  }, [projectPath, fetchMcpServers, fetchPlugins]);

  // Update slot enabled MCP servers when servers are fetched
  useEffect(() => {
    if (mcpServers.length > 0) {
      setSlots((prev) =>
        prev.map((slot) => {
          // Only update if the slot has no enabled servers (fresh slot)
          if (slot.enabledMcpServers.length === 0) {
            return { ...slot, enabledMcpServers: mcpServers.map((s) => s.name) };
          }
          return slot;
        })
      );
    }
  }, [mcpServers]);

  // Update slot enabled skills/plugins when they are fetched
  useEffect(() => {
    if (skills.length > 0 || plugins.length > 0) {
      setSlots((prev) =>
        prev.map((slot) => {
          let updated = slot;
          // Only update if the slot has no enabled skills (fresh slot)
          if (slot.enabledSkills.length === 0 && skills.length > 0) {
            updated = { ...updated, enabledSkills: skills.map((s) => s.id) };
          }
          // Only update if the slot has no enabled plugins (fresh slot)
          if (slot.enabledPlugins.length === 0 && plugins.length > 0) {
            updated = {
              ...updated,
              enabledPlugins: plugins.filter((p) => p.enabled_by_default).map((p) => p.id),
            };
          }
          return updated;
        })
      );
    }
  }, [skills, plugins]);

  // Mark as mounted after first render
  useEffect(() => {
    mounted.current = true;
    return () => {
      mounted.current = false;
      // Kill all launched sessions on unmount (unless preserving)
      if (!preserveOnHide) {
        for (const slot of slotsRef.current) {
          if (slot.sessionId !== null) {
            killSession(slot.sessionId).catch(console.error);
          }
        }
      }
    };
  }, [preserveOnHide]);

  // Auto-respawn a slot when all slots are removed (not on initial mount)
  useEffect(() => {
    if (slots.length === 0 && mounted.current && !error) {
      setSlots([createEmptySlot(mcpServers, skills, plugins)]);
    }
  }, [slots.length, error, mcpServers, skills, plugins]);

  /**
   * Launches a single slot by spawning a shell with the configured settings.
   * If a branch is selected, prepares a worktree for that branch first.
   */
  const launchSlot = useCallback(async (slotId: string) => {
    const slot = slotsRef.current.find((s) => s.id === slotId);
    if (!slot || slot.sessionId !== null) return;

    try {
      // Determine the working directory
      // If a branch is selected, prepare a worktree first
      let workingDirectory = projectPath;
      let worktreePath: string | null = null;

      if (projectPath && slot.branch) {
        const result = await prepareSessionWorktree(projectPath, slot.branch);
        workingDirectory = result.working_directory;
        worktreePath = result.worktree_path;
      }

      // Spawn the shell in the correct directory (worktree or project path)
      const sessionId = await spawnShell(workingDirectory);

      // Register the session in SessionManager (required before assigning branch)
      if (projectPath) {
        await createSession(sessionId, slot.mode, projectPath);
      }

      // Assign the branch to the session so the header displays it
      if (slot.branch) {
        await assignSessionBranch(sessionId, slot.branch, worktreePath);
      }

      // Save enabled MCP servers for this session
      if (projectPath) {
        await setSessionMcpServers(projectPath, sessionId, slot.enabledMcpServers);
      }

      // Save enabled skills and plugins for this session
      if (projectPath) {
        await setSessionSkills(projectPath, sessionId, slot.enabledSkills);
        await setSessionPlugins(projectPath, sessionId, slot.enabledPlugins);
      }

      // Refresh sessions in store so TerminalView can read the updated config
      await useSessionStore.getState().fetchSessions();

      // Auto-launch AI CLI after shell initializes
      if (slot.mode !== "Plain") {
        const cliConfig = AI_CLI_CONFIG[slot.mode];
        if (cliConfig.command) {
          const isAvailable = await checkCliAvailable(cliConfig.command);

          if (isAvailable) {
            // Wait for shell to initialize
            await new Promise((resolve) => setTimeout(resolve, 500));
            // Send CLI launch command with carriage return
            await writeStdin(sessionId, `${cliConfig.command}\r`);
          } else {
            console.warn(
              `CLI '${cliConfig.command}' not found. Install with: ${cliConfig.installHint}`
            );
          }
        }
      }

      setSlots((prev) =>
        prev.map((s) =>
          s.id === slotId ? { ...s, sessionId, worktreePath } : s
        )
      );

      // Register session with the project
      if (tabId) {
        addSessionToProject(tabId, sessionId);
      }
    } catch (err) {
      console.error("Failed to spawn shell:", err);
      setError("Failed to start terminal session");
    }
  }, [projectPath, tabId, addSessionToProject]);

  /**
   * Launches all unlaunched slots sequentially.
   */
  const launchAll = useCallback(async () => {
    const unlaunchedSlots = slotsRef.current.filter((s) => s.sessionId === null);
    for (const slot of unlaunchedSlots) {
      await launchSlot(slot.id);
    }
  }, [launchSlot]);

  /**
   * Handles killing/closing a session, updating the slot state.
   * Also cleans up any associated worktree.
   */
  const handleKill = useCallback((sessionId: number) => {
    // Find the slot to get worktree path before removing
    const slot = slotsRef.current.find((s) => s.sessionId === sessionId);
    const worktreePath = slot?.worktreePath;

    setSlots((prev) => prev.filter((s) => s.sessionId !== sessionId));

    // Unregister session from the project
    if (tabId) {
      removeSessionFromProject(tabId, sessionId);
    }

    // Clean up worktree if one was created (fire-and-forget)
    if (projectPath && worktreePath) {
      cleanupSessionWorktree(projectPath, worktreePath).catch(console.error);
    }
  }, [tabId, projectPath, removeSessionFromProject]);

  /**
   * Removes a pre-launch slot (before it's launched).
   */
  const removeSlot = useCallback((slotId: string) => {
    setSlots((prev) => prev.filter((s) => s.id !== slotId));
  }, []);

  /**
   * Updates the AI mode for a slot.
   */
  const updateSlotMode = useCallback((slotId: string, mode: AiMode) => {
    setSlots((prev) =>
      prev.map((s) =>
        s.id === slotId ? { ...s, mode } : s
      )
    );
  }, []);

  /**
   * Updates the branch for a slot.
   */
  const updateSlotBranch = useCallback((slotId: string, branch: string | null) => {
    setSlots((prev) =>
      prev.map((s) =>
        s.id === slotId ? { ...s, branch } : s
      )
    );
  }, []);

  /**
   * Toggles an MCP server for a slot.
   */
  const toggleSlotMcp = useCallback((slotId: string, serverName: string) => {
    setSlots((prev) =>
      prev.map((s) => {
        if (s.id !== slotId) return s;
        const isEnabled = s.enabledMcpServers.includes(serverName);
        const newEnabled = isEnabled
          ? s.enabledMcpServers.filter((n) => n !== serverName)
          : [...s.enabledMcpServers, serverName];
        return { ...s, enabledMcpServers: newEnabled };
      })
    );
  }, []);

  /**
   * Toggles a skill for a slot.
   */
  const toggleSlotSkill = useCallback((slotId: string, skillId: string) => {
    setSlots((prev) =>
      prev.map((s) => {
        if (s.id !== slotId) return s;
        const isEnabled = s.enabledSkills.includes(skillId);
        const newEnabled = isEnabled
          ? s.enabledSkills.filter((id) => id !== skillId)
          : [...s.enabledSkills, skillId];
        return { ...s, enabledSkills: newEnabled };
      })
    );
  }, []);

  /**
   * Toggles a plugin for a slot.
   * Also toggles all skills belonging to that plugin.
   */
  const toggleSlotPlugin = useCallback((slotId: string, pluginId: string) => {
    // Find the plugin and its associated skills
    const plugin = plugins.find((p) => p.id === pluginId);
    if (!plugin) return;

    // Helper to extract base name from skill ID
    const getSkillBaseName = (skillId: string): string => {
      const colonIndex = skillId.indexOf(":");
      return colonIndex >= 0 ? skillId.slice(colonIndex + 1) : skillId;
    };

    // Build map of base name -> skill for lookup
    const skillByBaseName = new Map(skills.map((s) => [getSkillBaseName(s.id), s]));

    // Find all skill IDs that belong to this plugin
    const pluginSkillIds: string[] = [];
    for (const skillId of plugin.skills) {
      const baseName = getSkillBaseName(skillId);
      const skill = skillByBaseName.get(baseName);
      if (skill) {
        pluginSkillIds.push(skill.id);
      }
    }

    setSlots((prev) =>
      prev.map((s) => {
        if (s.id !== slotId) return s;
        const isEnabled = s.enabledPlugins.includes(pluginId);

        // Toggle plugin
        const newEnabledPlugins = isEnabled
          ? s.enabledPlugins.filter((id) => id !== pluginId)
          : [...s.enabledPlugins, pluginId];

        // Toggle all associated skills
        let newEnabledSkills: string[];
        if (isEnabled) {
          // Disabling plugin - remove all its skills
          newEnabledSkills = s.enabledSkills.filter((id) => !pluginSkillIds.includes(id));
        } else {
          // Enabling plugin - add all its skills (avoid duplicates)
          const skillsToAdd = pluginSkillIds.filter((id) => !s.enabledSkills.includes(id));
          newEnabledSkills = [...s.enabledSkills, ...skillsToAdd];
        }

        return { ...s, enabledPlugins: newEnabledPlugins, enabledSkills: newEnabledSkills };
      })
    );
  }, [plugins, skills]);

  /**
   * Adds a new pre-launch slot to the grid.
   */
  const addSession = useCallback(() => {
    if (slotsRef.current.length >= MAX_SESSIONS) return;
    setSlots((prev) => {
      if (prev.length >= MAX_SESSIONS) return prev;
      return [...prev, createEmptySlot(mcpServers, skills, plugins)];
    });
  }, [mcpServers, skills, plugins]);

  useImperativeHandle(ref, () => ({ addSession, launchAll }), [addSession, launchAll]);

  if (error) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-3 text-maestro-muted">
        <span className="text-sm text-maestro-red">{error}</span>
        <button
          type="button"
          onClick={() => {
            setError(null);
            setSlots([createEmptySlot()]);
          }}
          className="rounded bg-maestro-border px-3 py-1.5 text-xs text-maestro-text hover:bg-maestro-muted/20"
        >
          Retry
        </button>
      </div>
    );
  }

  if (slots.length === 0) {
    return (
      <div className="flex h-full items-center justify-center text-maestro-muted text-sm">
        Initializing...
      </div>
    );
  }

  return (
    <div className={`grid h-full ${gridClass(slots.length)} gap-2 bg-maestro-bg p-2`}>
      {slots.map((slot) =>
        slot.sessionId !== null ? (
          <TerminalView key={slot.id} sessionId={slot.sessionId} onKill={handleKill} />
        ) : (
          <PreLaunchCard
            key={slot.id}
            slot={slot}
            projectPath={projectPath ?? ""}
            branches={branches}
            isLoadingBranches={isLoadingBranches}
            isGitRepo={isGitRepo}
            mcpServers={mcpServers}
            skills={skills}
            plugins={plugins}
            onModeChange={(mode) => updateSlotMode(slot.id, mode)}
            onBranchChange={(branch) => updateSlotBranch(slot.id, branch)}
            onMcpToggle={(serverName) => toggleSlotMcp(slot.id, serverName)}
            onSkillToggle={(skillId) => toggleSlotSkill(slot.id, skillId)}
            onPluginToggle={(pluginId) => toggleSlotPlugin(slot.id, pluginId)}
            onLaunch={() => launchSlot(slot.id)}
            onRemove={() => removeSlot(slot.id)}
          />
        )
      )}
    </div>
  );
});
