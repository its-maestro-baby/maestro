import {
  ChevronDown,
  ChevronRight,
  Clock,
  FileText,
  Brain,
  Loader2,
  RefreshCw,
  Cpu,
  Wrench,
  MessageSquare,
  Search,
  Play,
} from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { useClaudeDataStore } from "@/stores/useClaudeDataStore";
import { useWorkspaceStore } from "@/stores/useWorkspaceStore";
import { useResumeRequestStore } from "@/stores/useResumeRequestStore";
import type { SessionConfig, AiMode } from "@/stores/useSessionStore";
import {
  dbGetSessionsForProject,
  dbSearchSessions,
  type EnrichedSession,
} from "@/lib/database";

function formatRelativeTime(timestamp: number): string {
  const now = Date.now();
  const ts = timestamp > 1e12 ? timestamp : timestamp * 1000;
  const diff = now - ts;
  const seconds = Math.floor(diff / 1000);
  const minutes = Math.floor(seconds / 60);
  const hours = Math.floor(minutes / 60);
  const days = Math.floor(hours / 24);

  if (days > 0) return `${days}d ago`;
  if (hours > 0) return `${hours}h ago`;
  if (minutes > 0) return `${minutes}m ago`;
  return "just now";
}

function formatTokens(count: number): string {
  if (count >= 1_000_000) return `${(count / 1_000_000).toFixed(1)}M`;
  if (count >= 1_000) return `${(count / 1_000).toFixed(1)}K`;
  return String(count);
}

export function ClaudeDataTab() {
  const tabs = useWorkspaceStore((s) => s.tabs);
  const activeTab = tabs.find((t) => t.active);
  const projectPath = activeTab?.projectPath ?? "";

  const { history, memory, plans, isLoading, fetchAll, triggerSync } = useClaudeDataStore();

  const [sessionsOpen, setSessionsOpen] = useState(true);
  const [historyOpen, setHistoryOpen] = useState(false);
  const [memoryOpen, setMemoryOpen] = useState(false);
  const [plansOpen, setPlansOpen] = useState(false);

  const [sessions, setSessions] = useState<EnrichedSession[]>([]);
  const [sessionsLoading, setSessionsLoading] = useState(false);
  const [searchQuery, setSearchQuery] = useState("");

  const loadSessions = useCallback(async () => {
    if (!projectPath) return;
    setSessionsLoading(true);
    try {
      const result = await dbGetSessionsForProject(projectPath, {
        sort_by: "created_at",
        sort_dir: "desc",
        limit: 50,
        include_hidden: true,
      });
      setSessions(result.items);
    } catch (err) {
      console.error("Failed to load sessions:", err);
    } finally {
      setSessionsLoading(false);
    }
  }, [projectPath]);

  const handleSearch = useCallback(async () => {
    if (!searchQuery.trim()) {
      loadSessions();
      return;
    }
    setSessionsLoading(true);
    try {
      const results = await dbSearchSessions(searchQuery, projectPath || undefined);
      setSessions(results);
    } catch (err) {
      console.error("Failed to search sessions:", err);
    } finally {
      setSessionsLoading(false);
    }
  }, [searchQuery, projectPath, loadSessions]);

  const handleRefresh = useCallback(async () => {
    await triggerSync();
    if (projectPath) {
      fetchAll(projectPath);
      loadSessions();
    }
  }, [projectPath, fetchAll, triggerSync, loadSessions]);

  useEffect(() => {
    if (projectPath) {
      fetchAll(projectPath);
      loadSessions();
    }
  }, [projectPath, fetchAll, loadSessions]);

  if (!projectPath) {
    return (
      <div className="flex flex-col items-center justify-center py-8 text-center">
        <Brain size={24} className="mb-2 text-maestro-muted/50" />
        <p className="text-xs text-maestro-muted">No project selected</p>
      </div>
    );
  }

  return (
    <div className="space-y-1">
      {/* Search + Refresh */}
      <div className="flex items-center gap-1.5 mb-1">
        <div className="flex flex-1 items-center gap-1 rounded bg-maestro-bg px-2 py-1 border border-maestro-border/40">
          <Search size={11} className="text-maestro-muted shrink-0" />
          <input
            type="text"
            placeholder="Search sessions..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleSearch()}
            className="w-full bg-transparent text-[11px] text-maestro-text placeholder:text-maestro-muted/60 outline-none"
          />
        </div>
        <button
          type="button"
          onClick={handleRefresh}
          disabled={isLoading}
          className="rounded p-1 text-maestro-muted hover:bg-maestro-card hover:text-maestro-text disabled:opacity-50"
          title="Sync & Refresh"
        >
          <RefreshCw size={12} className={isLoading ? "animate-spin" : ""} />
        </button>
      </div>

      {/* Claude Sessions (Enriched) */}
      <CollapsibleSection
        title="Sessions"
        icon={MessageSquare}
        open={sessionsOpen}
        onToggle={() => setSessionsOpen((v) => !v)}
        badge={sessions.length > 0 ? String(sessions.length) : undefined}
      >
        {sessionsLoading ? (
          <div className="flex items-center gap-2 py-2">
            <Loader2 size={12} className="animate-spin text-maestro-muted" />
            <span className="text-[11px] text-maestro-muted">Loading...</span>
          </div>
        ) : sessions.length === 0 ? (
          <p className="py-2 text-[11px] text-maestro-muted">No sessions found</p>
        ) : (
          <div className="space-y-1">
            {sessions.map((session) => (
              <SessionCard key={session.id} session={session} />
            ))}
          </div>
        )}
      </CollapsibleSection>

      {/* Session History */}
      <CollapsibleSection
        title="History"
        icon={Clock}
        open={historyOpen}
        onToggle={() => setHistoryOpen((v) => !v)}
        badge={history.length > 0 ? String(history.length) : undefined}
      >
        {isLoading ? (
          <div className="flex items-center gap-2 py-2">
            <Loader2 size={12} className="animate-spin text-maestro-muted" />
            <span className="text-[11px] text-maestro-muted">Loading...</span>
          </div>
        ) : history.length === 0 ? (
          <p className="py-2 text-[11px] text-maestro-muted">No history for this project</p>
        ) : (
          <div className="space-y-0.5">
            {history.map((entry, i) => (
              <div
                key={`${entry.session_id ?? i}-${entry.timestamp}`}
                className="rounded px-2 py-1.5 text-[11px] hover:bg-maestro-card"
              >
                <div className="flex items-start justify-between gap-2">
                  <span className="flex-1 text-maestro-text leading-relaxed break-all line-clamp-2">
                    {entry.display}
                  </span>
                  <span className="shrink-0 text-[10px] text-maestro-muted">
                    {formatRelativeTime(entry.timestamp)}
                  </span>
                </div>
              </div>
            ))}
          </div>
        )}
      </CollapsibleSection>

      {/* Memory */}
      <CollapsibleSection
        title="Memory"
        icon={Brain}
        open={memoryOpen}
        onToggle={() => setMemoryOpen((v) => !v)}
        badge={memory ? "MEMORY.md" : undefined}
      >
        {isLoading ? (
          <div className="flex items-center gap-2 py-2">
            <Loader2 size={12} className="animate-spin text-maestro-muted" />
            <span className="text-[11px] text-maestro-muted">Loading...</span>
          </div>
        ) : memory ? (
          <pre className="max-h-60 overflow-auto rounded bg-maestro-bg p-2 text-[10px] font-mono text-maestro-text leading-relaxed whitespace-pre-wrap break-words">
            {memory}
          </pre>
        ) : (
          <p className="py-2 text-[11px] text-maestro-muted">No MEMORY.md for this project</p>
        )}
      </CollapsibleSection>

      {/* Plans */}
      <CollapsibleSection
        title="Plans"
        icon={FileText}
        open={plansOpen}
        onToggle={() => setPlansOpen((v) => !v)}
        badge={plans.length > 0 ? String(plans.length) : undefined}
      >
        {isLoading ? (
          <div className="flex items-center gap-2 py-2">
            <Loader2 size={12} className="animate-spin text-maestro-muted" />
            <span className="text-[11px] text-maestro-muted">Loading...</span>
          </div>
        ) : plans.length === 0 ? (
          <p className="py-2 text-[11px] text-maestro-muted">No plans found</p>
        ) : (
          <div className="space-y-0.5">
            {plans.map((plan) => (
              <div
                key={plan.filename}
                className="rounded px-2 py-1.5 text-[11px] hover:bg-maestro-card"
              >
                <div className="flex items-center justify-between gap-2">
                  <span className="flex-1 truncate text-maestro-text">{plan.filename}</span>
                  <span className="shrink-0 text-[10px] text-maestro-muted">
                    {plan.modified_at ? formatRelativeTime(plan.modified_at * 1000) : ""}
                  </span>
                </div>
                <div className="text-[10px] text-maestro-muted">
                  {plan.size_bytes > 1024
                    ? `${(plan.size_bytes / 1024).toFixed(1)} KB`
                    : `${plan.size_bytes} B`}
                </div>
              </div>
            ))}
          </div>
        )}
      </CollapsibleSection>
    </div>
  );
}

function SessionCard({ session }: { session: EnrichedSession }) {
  const requestResume = useResumeRequestStore((s) => s.requestResume);
  const totalTokens = session.total_input_tokens + session.total_output_tokens;
  const tools: string[] = session.tools_used ? JSON.parse(session.tools_used) : [];
  const preview = session.first_message || session.history_display || session.name;
  const time = session.created_at
    ? formatRelativeTime(new Date(session.created_at).getTime())
    : session.history_timestamp
      ? formatRelativeTime(session.history_timestamp)
      : "";
  const canResume = !!session.claude_session_uuid;

  const handleResume = () => {
    if (!session.claude_session_uuid) return;
    const config: SessionConfig = {
      id: session.maestro_session_id ?? -session.id,
      mode: (session.mode as AiMode) ?? "Claude",
      name: session.name,
      branch: session.branch,
      status: "Done",
      worktree_path: session.worktree_path,
      project_path: session.project_path,
      claude_session_uuid: session.claude_session_uuid,
      db_id: session.id,
    };
    requestResume(config);
  };

  return (
    <div className="group rounded-md bg-maestro-bg px-2 py-1.5 hover:bg-maestro-card border border-transparent hover:border-maestro-border/40 transition-colors">
      {/* First line: preview + time + resume */}
      <div className="flex items-start justify-between gap-2">
        <span className="flex-1 text-[11px] text-maestro-text leading-relaxed line-clamp-2 break-all">
          {preview || <span className="italic text-maestro-muted">No message</span>}
        </span>
        <div className="flex items-center gap-1 shrink-0">
          {canResume && (
            <button
              type="button"
              onClick={handleResume}
              className="rounded p-0.5 opacity-0 group-hover:opacity-100 hover:bg-maestro-green/10 transition-opacity"
              title="Resume Claude session"
            >
              <Play size={10} className="text-maestro-green" />
            </button>
          )}
          <span className="text-[10px] text-maestro-muted">{time}</span>
        </div>
      </div>

      {/* Second line: model + stats */}
      <div className="flex items-center gap-2 mt-0.5 flex-wrap">
        {session.model && (
          <span className="inline-flex items-center gap-0.5 text-[9px] text-maestro-accent/80">
            <Cpu size={9} />
            {session.model.replace("claude-", "").replace("-20250", "")}
          </span>
        )}
        {totalTokens > 0 && (
          <span className="text-[9px] text-maestro-muted">
            {formatTokens(totalTokens)} tok
          </span>
        )}
        {session.files_modified_count > 0 && (
          <span className="inline-flex items-center gap-0.5 text-[9px] text-maestro-muted">
            <FileText size={9} />
            {session.files_modified_count}
          </span>
        )}
        {tools.length > 0 && (
          <span className="inline-flex items-center gap-0.5 text-[9px] text-maestro-muted">
            <Wrench size={9} />
            {tools.length}
          </span>
        )}
        {session.mode && session.mode !== "Claude" && (
          <span className="rounded bg-maestro-card px-1 py-px text-[9px] text-maestro-muted">
            {session.mode}
          </span>
        )}
      </div>
    </div>
  );
}

function CollapsibleSection({
  title,
  icon: Icon,
  open,
  onToggle,
  badge,
  children,
}: {
  title: string;
  icon: React.ElementType;
  open: boolean;
  onToggle: () => void;
  badge?: string;
  children: React.ReactNode;
}) {
  return (
    <div className="rounded-lg border border-maestro-border/60 bg-maestro-card overflow-hidden">
      <button
        type="button"
        onClick={onToggle}
        className="flex w-full items-center gap-2 px-2.5 py-2 text-[11px] font-semibold uppercase tracking-wider text-maestro-muted hover:text-maestro-text"
      >
        {open ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
        <Icon size={12} />
        <span className="flex-1 text-left">{title}</span>
        {badge && (
          <span className="rounded-full bg-maestro-accent/15 px-1.5 py-px text-[9px] font-medium text-maestro-accent">
            {badge}
          </span>
        )}
      </button>
      {open && <div className="px-2 pb-2">{children}</div>}
    </div>
  );
}
