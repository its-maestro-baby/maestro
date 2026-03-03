/**
 * IPC wrappers for the unified SQLite database.
 */

import { invoke } from "@tauri-apps/api/core";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** A unified session row from the SQLite database. */
export interface EnrichedSession {
  id: number;
  maestro_session_id: number | null;
  claude_session_uuid: string | null;
  mode: string;
  name: string | null;
  branch: string | null;
  status: string;
  worktree_path: string | null;
  project_path: string;
  hidden: boolean;
  status_message: string | null;
  needs_input_prompt: string | null;
  // Enrichment from Claude Code transcript
  first_message: string | null;
  model: string | null;
  transcript_path: string | null;
  total_input_tokens: number;
  total_output_tokens: number;
  files_modified_count: number;
  tools_used: string | null; // JSON array string
  subagent_count: number;
  // Timestamps
  created_at: string | null;
  updated_at: string | null;
  ended_at: string | null;
  // Sync tracking
  claude_data_synced_at: string | null;
  history_display: string | null;
  history_timestamp: number | null;
}

/** Query options for listing sessions. */
export interface QueryOptions {
  status?: string[];
  mode?: string[];
  search?: string;
  sort_by?: string;
  sort_dir?: "asc" | "desc";
  limit?: number;
  offset?: number;
  include_hidden?: boolean;
}

/** Paginated result wrapper. */
export interface PaginatedResult<T> {
  items: T[];
  total: number;
  offset: number;
  limit: number;
}

/** A history entry from the database. */
export interface DbHistoryEntry {
  id: number;
  display: string;
  timestamp: number;
  project: string | null;
  session_id: string | null;
  synced_at: string | null;
}

/** A plan row from the database. */
export interface DbPlanRow {
  id: number;
  filename: string;
  size_bytes: number;
  modified_at: number | null;
  synced_at: string | null;
}

/** A file entry for a session. */
export interface DbFileEntry {
  id: number;
  session_id: number;
  file_path: string;
  action: string;
  timestamp: string | null;
}

// ---------------------------------------------------------------------------
// IPC wrappers
// ---------------------------------------------------------------------------

/** Get sessions for a project with filtering, sorting, and pagination. */
export async function dbGetSessionsForProject(
  projectPath: string,
  opts?: QueryOptions
): Promise<PaginatedResult<EnrichedSession>> {
  return invoke<PaginatedResult<EnrichedSession>>("db_get_sessions_for_project", {
    projectPath,
    opts,
  });
}

/** Search sessions by query string. */
export async function dbSearchSessions(
  query: string,
  projectPath?: string
): Promise<EnrichedSession[]> {
  return invoke<EnrichedSession[]>("db_search_sessions", { query, projectPath });
}

/** Get history entries with optional project filter and pagination. */
export async function dbGetHistory(
  projectPath?: string,
  limit?: number,
  offset?: number
): Promise<PaginatedResult<DbHistoryEntry>> {
  return invoke<PaginatedResult<DbHistoryEntry>>("db_get_history", {
    projectPath,
    limit,
    offset,
  });
}

/** Get project memory content. */
export async function dbGetProjectMemory(
  projectPath: string
): Promise<string | null> {
  return invoke<string | null>("db_get_project_memory", { projectPath });
}

/** Get plans with pagination. */
export async function dbGetPlans(
  limit?: number,
  offset?: number
): Promise<PaginatedResult<DbPlanRow>> {
  return invoke<PaginatedResult<DbPlanRow>>("db_get_plans", { limit, offset });
}

/** Get files modified by a session. */
export async function dbGetSessionFiles(
  sessionId: number
): Promise<DbFileEntry[]> {
  return invoke<DbFileEntry[]>("db_get_session_files", { sessionId });
}

/** Trigger a manual sync of Claude Code data. */
export async function dbTriggerSync(): Promise<void> {
  return invoke<void>("db_trigger_sync");
}

/** Add token usage to a session (write-through). */
export async function dbAddSessionTokens(
  maestroSessionId: number,
  inputTokens: number,
  outputTokens: number
): Promise<void> {
  return invoke<void>("db_add_session_tokens", {
    maestroSessionId,
    inputTokens,
    outputTokens,
  });
}

/** Add a file modification entry for a session. */
export async function dbAddSessionFile(
  maestroSessionId: number,
  filePath: string,
  action: string
): Promise<void> {
  return invoke<void>("db_add_session_file", {
    maestroSessionId,
    filePath,
    action,
  });
}
