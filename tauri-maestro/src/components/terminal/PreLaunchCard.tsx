import {
  BrainCircuit,
  Check,
  ChevronDown,
  Code2,
  FolderGit2,
  GitBranch,
  Package,
  Play,
  Server,
  Sparkles,
  Terminal,
  X,
  Zap,
} from "lucide-react";
import { useEffect, useRef, useState } from "react";

import type { BranchWithWorktreeStatus } from "@/lib/git";
import type { McpServerConfig } from "@/lib/mcp";
import type { PluginConfig, SkillConfig, SkillSource } from "@/lib/plugins";
import type { AiMode } from "@/stores/useSessionStore";

/** Returns badge styling and text for a skill source. */
function getSkillSourceLabel(source: SkillSource): { text: string; className: string } {
  switch (source.type) {
    case "project":
      return {
        text: "Project",
        className: "bg-maestro-accent/20 text-maestro-accent",
      };
    case "personal":
      return {
        text: "Personal",
        className: "bg-maestro-green/20 text-maestro-green",
      };
    case "plugin":
      return {
        text: source.name,
        className: "bg-maestro-purple/20 text-maestro-purple",
      };
    case "legacy":
      return {
        text: "Legacy",
        className: "bg-maestro-muted/20 text-maestro-muted",
      };
  }
}

/** Pre-launch session slot configuration. */
export interface SessionSlot {
  id: string;
  mode: AiMode;
  branch: string | null;
  sessionId: number | null;
  /** Path to the worktree if one was created for this session. */
  worktreePath: string | null;
  /** Names of enabled MCP servers for this session. */
  enabledMcpServers: string[];
  /** IDs of enabled skills for this session. */
  enabledSkills: string[];
  /** IDs of enabled plugins for this session. */
  enabledPlugins: string[];
}

interface PreLaunchCardProps {
  slot: SessionSlot;
  projectPath: string;
  branches: BranchWithWorktreeStatus[];
  isLoadingBranches: boolean;
  isGitRepo: boolean;
  mcpServers: McpServerConfig[];
  skills: SkillConfig[];
  plugins: PluginConfig[];
  onModeChange: (mode: AiMode) => void;
  onBranchChange: (branch: string | null) => void;
  onMcpToggle: (serverName: string) => void;
  onSkillToggle: (skillId: string) => void;
  onPluginToggle: (pluginId: string) => void;
  onLaunch: () => void;
  onRemove: () => void;
}

const AI_MODES: { mode: AiMode; icon: typeof BrainCircuit; label: string; color: string }[] = [
  { mode: "Claude", icon: BrainCircuit, label: "Claude Code", color: "text-violet-500" },
  { mode: "Gemini", icon: Sparkles, label: "Gemini CLI", color: "text-blue-400" },
  { mode: "Codex", icon: Code2, label: "Codex", color: "text-green-400" },
  { mode: "Plain", icon: Terminal, label: "Terminal", color: "text-maestro-muted" },
];

function getModeConfig(mode: AiMode) {
  return AI_MODES.find((m) => m.mode === mode) ?? AI_MODES[0];
}

export function PreLaunchCard({
  slot,
  branches,
  isLoadingBranches,
  isGitRepo,
  mcpServers,
  skills,
  plugins,
  onModeChange,
  onBranchChange,
  onMcpToggle,
  onSkillToggle,
  onPluginToggle,
  onLaunch,
  onRemove,
}: PreLaunchCardProps) {
  const [modeDropdownOpen, setModeDropdownOpen] = useState(false);
  const [branchDropdownOpen, setBranchDropdownOpen] = useState(false);
  const [mcpDropdownOpen, setMcpDropdownOpen] = useState(false);
  const [skillsDropdownOpen, setSkillsDropdownOpen] = useState(false);
  const [pluginsDropdownOpen, setPluginsDropdownOpen] = useState(false);
  const modeDropdownRef = useRef<HTMLDivElement>(null);
  const branchDropdownRef = useRef<HTMLDivElement>(null);
  const mcpDropdownRef = useRef<HTMLDivElement>(null);
  const skillsDropdownRef = useRef<HTMLDivElement>(null);
  const pluginsDropdownRef = useRef<HTMLDivElement>(null);

  const modeConfig = getModeConfig(slot.mode);
  const ModeIcon = modeConfig.icon;

  // Close dropdowns on outside click
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (modeDropdownRef.current && !modeDropdownRef.current.contains(event.target as Node)) {
        setModeDropdownOpen(false);
      }
      if (branchDropdownRef.current && !branchDropdownRef.current.contains(event.target as Node)) {
        setBranchDropdownOpen(false);
      }
      if (mcpDropdownRef.current && !mcpDropdownRef.current.contains(event.target as Node)) {
        setMcpDropdownOpen(false);
      }
      if (skillsDropdownRef.current && !skillsDropdownRef.current.contains(event.target as Node)) {
        setSkillsDropdownOpen(false);
      }
      if (pluginsDropdownRef.current && !pluginsDropdownRef.current.contains(event.target as Node)) {
        setPluginsDropdownOpen(false);
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // MCP server display info
  const enabledCount = slot.enabledMcpServers.length;
  const totalCount = mcpServers.length;
  const hasMcpServers = totalCount > 0;

  // Skills display info
  const enabledSkillsCount = slot.enabledSkills.length;
  const totalSkillsCount = skills.length;
  const hasSkills = totalSkillsCount > 0;

  // Plugins display info
  const enabledPluginsCount = slot.enabledPlugins.length;
  const totalPluginsCount = plugins.length;
  const hasPlugins = totalPluginsCount > 0;

  // Find current branch display info
  const currentBranch = branches.find((b) => b.isCurrent);
  const selectedBranchInfo = slot.branch
    ? branches.find((b) => b.name === slot.branch)
    : currentBranch;
  const displayBranch = selectedBranchInfo?.name ?? slot.branch ?? "Current";

  // Separate local and remote branches
  const localBranches = branches.filter((b) => !b.isRemote);
  const remoteBranches = branches.filter((b) => b.isRemote);

  return (
    <div className="content-dark terminal-cell flex h-full flex-col items-center justify-center bg-maestro-bg p-4">
      {/* Card content */}
      <div className="flex w-full max-w-xs flex-col gap-4">
        {/* Header with remove button */}
        <div className="flex items-center justify-between">
          <span className="text-sm font-medium text-maestro-text">Configure Session</span>
          <button
            type="button"
            onClick={onRemove}
            className="rounded p-1 text-maestro-muted transition-colors hover:bg-maestro-card hover:text-maestro-red"
            title="Remove session slot"
            aria-label="Remove session slot"
          >
            <X size={14} />
          </button>
        </div>

        {/* AI Mode Selector */}
        <div className="relative" ref={modeDropdownRef}>
          <label className="mb-1 block text-[10px] font-medium uppercase tracking-wide text-maestro-muted">
            AI Mode
          </label>
          <button
            type="button"
            onClick={() => setModeDropdownOpen(!modeDropdownOpen)}
            className="flex w-full items-center justify-between gap-2 rounded border border-maestro-border bg-maestro-card px-3 py-2 text-left text-sm text-maestro-text transition-colors hover:border-maestro-accent/50"
          >
            <div className="flex items-center gap-2">
              <ModeIcon size={16} className={modeConfig.color} />
              <span>{modeConfig.label}</span>
            </div>
            <ChevronDown size={14} className="text-maestro-muted" />
          </button>

          {modeDropdownOpen && (
            <div className="absolute left-0 right-0 top-full z-10 mt-1 overflow-hidden rounded border border-maestro-border bg-maestro-card shadow-lg">
              {AI_MODES.map((option) => {
                const Icon = option.icon;
                const isSelected = option.mode === slot.mode;
                return (
                  <button
                    key={option.mode}
                    type="button"
                    onClick={() => {
                      onModeChange(option.mode);
                      setModeDropdownOpen(false);
                    }}
                    className={`flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors ${
                      isSelected
                        ? "bg-maestro-accent/10 text-maestro-text"
                        : "text-maestro-muted hover:bg-maestro-surface hover:text-maestro-text"
                    }`}
                  >
                    <Icon size={16} className={option.color} />
                    <span>{option.label}</span>
                  </button>
                );
              })}
            </div>
          )}
        </div>

        {/* Branch Selector */}
        <div className="relative" ref={branchDropdownRef}>
          <label className="mb-1 block text-[10px] font-medium uppercase tracking-wide text-maestro-muted">
            Git Branch
          </label>
          {!isGitRepo ? (
            <div className="flex items-center gap-2 rounded border border-maestro-border bg-maestro-card/50 px-3 py-2 text-sm text-maestro-muted">
              <Terminal size={14} />
              <span>Not a Git repository</span>
            </div>
          ) : (
            <>
              <button
                type="button"
                onClick={() => setBranchDropdownOpen(!branchDropdownOpen)}
                disabled={isLoadingBranches}
                className="flex w-full items-center justify-between gap-2 rounded border border-maestro-border bg-maestro-card px-3 py-2 text-left text-sm text-maestro-text transition-colors hover:border-maestro-accent/50 disabled:opacity-50"
              >
                <div className="flex min-w-0 items-center gap-2">
                  <GitBranch size={14} className="shrink-0 text-maestro-accent" />
                  <span className="truncate">{displayBranch}</span>
                  {selectedBranchInfo?.hasWorktree && (
                    <span title="Worktree exists">
                      <FolderGit2 size={12} className="shrink-0 text-maestro-orange" />
                    </span>
                  )}
                  {selectedBranchInfo?.isCurrent && (
                    <span className="shrink-0 rounded bg-maestro-green/20 px-1 text-[9px] text-maestro-green">
                      current
                    </span>
                  )}
                </div>
                <ChevronDown size={14} className="shrink-0 text-maestro-muted" />
              </button>

              {branchDropdownOpen && (
                <div className="absolute left-0 right-0 top-full z-10 mt-1 max-h-48 overflow-y-auto rounded border border-maestro-border bg-maestro-card shadow-lg">
                  {/* Current branch option */}
                  <button
                    type="button"
                    onClick={() => {
                      onBranchChange(null);
                      setBranchDropdownOpen(false);
                    }}
                    className={`flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors ${
                      slot.branch === null
                        ? "bg-maestro-accent/10 text-maestro-text"
                        : "text-maestro-muted hover:bg-maestro-surface hover:text-maestro-text"
                    }`}
                  >
                    <GitBranch size={14} />
                    <span>Use current branch</span>
                  </button>

                  {/* Local branches */}
                  {localBranches.length > 0 && (
                    <>
                      <div className="border-t border-maestro-border px-3 py-1 text-[9px] font-medium uppercase tracking-wide text-maestro-muted">
                        Local
                      </div>
                      {localBranches.map((branch) => (
                        <button
                          key={branch.name}
                          type="button"
                          onClick={() => {
                            onBranchChange(branch.name);
                            setBranchDropdownOpen(false);
                          }}
                          className={`flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors ${
                            slot.branch === branch.name
                              ? "bg-maestro-accent/10 text-maestro-text"
                              : "text-maestro-muted hover:bg-maestro-surface hover:text-maestro-text"
                          }`}
                        >
                          <GitBranch size={14} />
                          <span className="truncate">{branch.name}</span>
                          {branch.hasWorktree && (
                            <span title="Worktree exists">
                              <FolderGit2 size={12} className="shrink-0 text-maestro-orange" />
                            </span>
                          )}
                          {branch.isCurrent && (
                            <span className="shrink-0 rounded bg-maestro-green/20 px-1 text-[9px] text-maestro-green">
                              current
                            </span>
                          )}
                        </button>
                      ))}
                    </>
                  )}

                  {/* Remote branches */}
                  {remoteBranches.length > 0 && (
                    <>
                      <div className="border-t border-maestro-border px-3 py-1 text-[9px] font-medium uppercase tracking-wide text-maestro-muted">
                        Remote
                      </div>
                      {remoteBranches.map((branch) => (
                        <button
                          key={branch.name}
                          type="button"
                          onClick={() => {
                            onBranchChange(branch.name);
                            setBranchDropdownOpen(false);
                          }}
                          className={`flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors ${
                            slot.branch === branch.name
                              ? "bg-maestro-accent/10 text-maestro-text"
                              : "text-maestro-muted hover:bg-maestro-surface hover:text-maestro-text"
                          }`}
                        >
                          <GitBranch size={14} className="text-maestro-muted/60" />
                          <span className="truncate">{branch.name}</span>
                          {branch.hasWorktree && (
                            <span title="Worktree exists">
                              <FolderGit2 size={12} className="shrink-0 text-maestro-orange" />
                            </span>
                          )}
                        </button>
                      ))}
                    </>
                  )}
                </div>
              )}
            </>
          )}
        </div>

        {/* MCP Servers Selector */}
        <div className="relative" ref={mcpDropdownRef}>
          <label className="mb-1 block text-[10px] font-medium uppercase tracking-wide text-maestro-muted">
            MCP Servers
          </label>
          {!hasMcpServers ? (
            <div className="flex items-center gap-2 rounded border border-maestro-border bg-maestro-card/50 px-3 py-2 text-sm text-maestro-muted">
              <Server size={14} />
              <span>No MCP servers configured</span>
            </div>
          ) : (
            <>
              <button
                type="button"
                onClick={() => setMcpDropdownOpen(!mcpDropdownOpen)}
                className="flex w-full items-center justify-between gap-2 rounded border border-maestro-border bg-maestro-card px-3 py-2 text-left text-sm text-maestro-text transition-colors hover:border-maestro-accent/50"
              >
                <div className="flex items-center gap-2">
                  <Server size={14} className="text-maestro-green" />
                  <span>
                    {enabledCount} of {totalCount} servers
                  </span>
                </div>
                <ChevronDown size={14} className="text-maestro-muted" />
              </button>

              {mcpDropdownOpen && (
                <div className="absolute left-0 right-0 top-full z-10 mt-1 max-h-48 overflow-y-auto rounded border border-maestro-border bg-maestro-card shadow-lg">
                  {mcpServers.map((server) => {
                    const isEnabled = slot.enabledMcpServers.includes(server.name);
                    const serverType = server.type;
                    return (
                      <button
                        key={server.name}
                        type="button"
                        onClick={() => onMcpToggle(server.name)}
                        className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors hover:bg-maestro-surface"
                      >
                        <span
                          className={`flex h-4 w-4 shrink-0 items-center justify-center rounded border ${
                            isEnabled
                              ? "border-maestro-green bg-maestro-green"
                              : "border-maestro-border bg-transparent"
                          }`}
                        >
                          {isEnabled && <Check size={12} className="text-white" />}
                        </span>
                        <span className={isEnabled ? "text-maestro-text" : "text-maestro-muted"}>
                          {server.name}
                        </span>
                        <span className="ml-auto text-[10px] text-maestro-muted/60">
                          {serverType}
                        </span>
                      </button>
                    );
                  })}
                </div>
              )}
            </>
          )}
        </div>

        {/* Skills Selector */}
        <div className="relative" ref={skillsDropdownRef}>
          <label className="mb-1 block text-[10px] font-medium uppercase tracking-wide text-maestro-muted">
            Skills
          </label>
          {!hasSkills ? (
            <div className="flex items-center gap-2 rounded border border-maestro-border bg-maestro-card/50 px-3 py-2 text-sm text-maestro-muted">
              <Zap size={14} />
              <span>No skills configured</span>
            </div>
          ) : (
            <>
              <button
                type="button"
                onClick={() => setSkillsDropdownOpen(!skillsDropdownOpen)}
                className="flex w-full items-center justify-between gap-2 rounded border border-maestro-border bg-maestro-card px-3 py-2 text-left text-sm text-maestro-text transition-colors hover:border-maestro-accent/50"
              >
                <div className="flex items-center gap-2">
                  <Zap size={14} className="text-maestro-orange" />
                  <span>
                    {enabledSkillsCount} of {totalSkillsCount} skills
                  </span>
                </div>
                <ChevronDown size={14} className="text-maestro-muted" />
              </button>

              {skillsDropdownOpen && (
                <div className="absolute left-0 right-0 top-full z-10 mt-1 max-h-48 overflow-y-auto rounded border border-maestro-border bg-maestro-card shadow-lg">
                  {skills.map((skill) => {
                    const isEnabled = slot.enabledSkills.includes(skill.id);
                    const sourceLabel = getSkillSourceLabel(skill.source);
                    return (
                      <button
                        key={skill.id}
                        type="button"
                        onClick={() => onSkillToggle(skill.id)}
                        className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors hover:bg-maestro-surface"
                        title={skill.description || undefined}
                      >
                        <span
                          className={`flex h-4 w-4 shrink-0 items-center justify-center rounded border ${
                            isEnabled
                              ? "border-maestro-orange bg-maestro-orange"
                              : "border-maestro-border bg-transparent"
                          }`}
                        >
                          {isEnabled && <Check size={12} className="text-white" />}
                        </span>
                        <span className={`flex-1 truncate ${isEnabled ? "text-maestro-text" : "text-maestro-muted"}`}>
                          {skill.name}
                        </span>
                        <span className={`shrink-0 rounded px-1 text-[9px] ${sourceLabel.className}`}>
                          {sourceLabel.text}
                        </span>
                      </button>
                    );
                  })}
                </div>
              )}
            </>
          )}
        </div>

        {/* Plugins Selector */}
        <div className="relative" ref={pluginsDropdownRef}>
          <label className="mb-1 block text-[10px] font-medium uppercase tracking-wide text-maestro-muted">
            Plugins
          </label>
          {!hasPlugins ? (
            <div className="flex items-center gap-2 rounded border border-maestro-border bg-maestro-card/50 px-3 py-2 text-sm text-maestro-muted">
              <Package size={14} />
              <span>No plugins configured</span>
            </div>
          ) : (
            <>
              <button
                type="button"
                onClick={() => setPluginsDropdownOpen(!pluginsDropdownOpen)}
                className="flex w-full items-center justify-between gap-2 rounded border border-maestro-border bg-maestro-card px-3 py-2 text-left text-sm text-maestro-text transition-colors hover:border-maestro-accent/50"
              >
                <div className="flex items-center gap-2">
                  <Package size={14} className="text-maestro-purple" />
                  <span>
                    {enabledPluginsCount} of {totalPluginsCount} plugins
                  </span>
                </div>
                <ChevronDown size={14} className="text-maestro-muted" />
              </button>

              {pluginsDropdownOpen && (
                <div className="absolute left-0 right-0 top-full z-10 mt-1 max-h-48 overflow-y-auto rounded border border-maestro-border bg-maestro-card shadow-lg">
                  {plugins.map((plugin) => {
                    const isEnabled = slot.enabledPlugins.includes(plugin.id);
                    return (
                      <button
                        key={plugin.id}
                        type="button"
                        onClick={() => onPluginToggle(plugin.id)}
                        className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm transition-colors hover:bg-maestro-surface"
                      >
                        <span
                          className={`flex h-4 w-4 shrink-0 items-center justify-center rounded border ${
                            isEnabled
                              ? "border-maestro-purple bg-maestro-purple"
                              : "border-maestro-border bg-transparent"
                          }`}
                        >
                          {isEnabled && <Check size={12} className="text-white" />}
                        </span>
                        <span className={isEnabled ? "text-maestro-text" : "text-maestro-muted"}>
                          {plugin.name}
                        </span>
                        <span className="ml-auto text-[10px] text-maestro-muted/60">
                          v{plugin.version}
                        </span>
                      </button>
                    );
                  })}
                </div>
              )}
            </>
          )}
        </div>

        {/* Launch Button */}
        <button
          type="button"
          onClick={onLaunch}
          className="flex items-center justify-center gap-2 rounded bg-maestro-accent px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-maestro-accent/80"
        >
          <Play size={16} fill="currentColor" />
          Launch Session
        </button>
      </div>
    </div>
  );
}
