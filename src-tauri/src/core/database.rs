//! SQLite database manager for unified Maestro + Claude Code sessions.
//!
//! Single-writer via `Mutex<Connection>`, WAL mode for concurrent reads.
//! This replaces both Zustand persist (store.json) and direct filesystem
//! reads from `~/.claude/` with a single source of truth.

use std::path::Path;
use std::sync::Mutex;

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};

/// Current schema version — bump when adding migrations.
#[allow(dead_code)]
const SCHEMA_VERSION: i64 = 1;

// ---------------------------------------------------------------------------
// Row types
// ---------------------------------------------------------------------------

/// A unified session row combining Maestro + Claude Code data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionRow {
    pub id: i64,
    pub maestro_session_id: Option<i64>,
    pub claude_session_uuid: Option<String>,
    pub mode: String,
    pub name: Option<String>,
    pub branch: Option<String>,
    pub status: String,
    pub worktree_path: Option<String>,
    pub project_path: String,
    pub hidden: bool,
    pub status_message: Option<String>,
    pub needs_input_prompt: Option<String>,
    // Enrichment from Claude Code transcript
    pub first_message: Option<String>,
    pub model: Option<String>,
    pub transcript_path: Option<String>,
    pub total_input_tokens: i64,
    pub total_output_tokens: i64,
    pub files_modified_count: i64,
    pub tools_used: Option<String>, // JSON array
    pub subagent_count: i64,
    // Timestamps
    pub created_at: Option<String>,
    pub updated_at: Option<String>,
    pub ended_at: Option<String>,
    // Sync tracking
    pub claude_data_synced_at: Option<String>,
    pub history_display: Option<String>,
    pub history_timestamp: Option<f64>,
}

/// A file modified by a session.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileEntry {
    pub id: i64,
    pub session_id: i64,
    pub file_path: String,
    pub action: String,
    pub timestamp: Option<String>,
}

/// An entry from claude_history table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HistoryRow {
    pub id: i64,
    pub display: String,
    pub timestamp: f64,
    pub project: Option<String>,
    pub session_id: Option<String>,
    pub synced_at: Option<String>,
}

/// A plan summary from the plans table.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlanRow {
    pub id: i64,
    pub filename: String,
    pub size_bytes: i64,
    pub modified_at: Option<f64>,
    pub synced_at: Option<String>,
}

/// Query options for listing sessions.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct QueryOptions {
    pub status: Option<Vec<String>>,
    pub mode: Option<Vec<String>>,
    pub search: Option<String>,
    pub sort_by: Option<String>,
    pub sort_dir: Option<String>,
    pub limit: Option<u32>,
    pub offset: Option<u32>,
    pub include_hidden: Option<bool>,
}

/// Paginated result wrapper.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaginatedResult<T> {
    pub items: Vec<T>,
    pub total: i64,
    pub offset: u32,
    pub limit: u32,
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

pub struct Database {
    conn: Mutex<Connection>,
}

impl Database {
    /// Open (or create) the SQLite database at `path`.
    /// Applies migrations and enables WAL mode.
    pub fn open(path: &Path) -> Result<Self, String> {
        // Ensure parent directory exists
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create DB directory: {e}"))?;
        }

        let conn = Connection::open(path)
            .map_err(|e| format!("Failed to open database: {e}"))?;

        // Enable WAL mode for better concurrent read performance
        conn.execute_batch("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
            .map_err(|e| format!("Failed to set PRAGMA: {e}"))?;

        let db = Self {
            conn: Mutex::new(conn),
        };
        db.migrate()?;
        Ok(db)
    }

    /// Run schema migrations.
    fn migrate(&self) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;

        // Create schema_version table if it doesn't exist
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER NOT NULL,
                applied_at TEXT DEFAULT (datetime('now'))
            );"
        ).map_err(|e| format!("Failed to create schema_version: {e}"))?;

        let current_version: i64 = conn
            .query_row(
                "SELECT COALESCE(MAX(version), 0) FROM schema_version",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);

        if current_version < 1 {
            self.apply_v1(&conn)?;
        }

        Ok(())
    }

    /// Schema v1 — initial tables.
    fn apply_v1(&self, conn: &Connection) -> Result<(), String> {
        conn.execute_batch(
            "
            -- Unified sessions: both Maestro sessions and Claude Code sessions
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                maestro_session_id INTEGER,
                claude_session_uuid TEXT,
                mode TEXT NOT NULL DEFAULT 'Claude',
                name TEXT,
                branch TEXT,
                status TEXT NOT NULL DEFAULT 'Done',
                worktree_path TEXT,
                project_path TEXT NOT NULL,
                hidden INTEGER NOT NULL DEFAULT 0,
                status_message TEXT,
                needs_input_prompt TEXT,
                first_message TEXT,
                model TEXT,
                transcript_path TEXT,
                total_input_tokens INTEGER DEFAULT 0,
                total_output_tokens INTEGER DEFAULT 0,
                files_modified_count INTEGER DEFAULT 0,
                tools_used TEXT,
                subagent_count INTEGER DEFAULT 0,
                created_at TEXT DEFAULT (datetime('now')),
                updated_at TEXT DEFAULT (datetime('now')),
                ended_at TEXT,
                claude_data_synced_at TEXT,
                history_display TEXT,
                history_timestamp REAL
            );

            CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(project_path);
            CREATE INDEX IF NOT EXISTS idx_sessions_claude_uuid ON sessions(claude_session_uuid);
            CREATE INDEX IF NOT EXISTS idx_sessions_maestro_id ON sessions(maestro_session_id);
            CREATE INDEX IF NOT EXISTS idx_sessions_created ON sessions(created_at);

            -- Files modified by sessions
            CREATE TABLE IF NOT EXISTS session_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
                file_path TEXT NOT NULL,
                action TEXT NOT NULL,
                timestamp TEXT
            );

            -- History entries from ~/.claude/history.jsonl
            CREATE TABLE IF NOT EXISTS claude_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                display TEXT NOT NULL,
                timestamp REAL NOT NULL,
                project TEXT,
                session_id TEXT,
                synced_at TEXT DEFAULT (datetime('now'))
            );
            CREATE INDEX IF NOT EXISTS idx_history_project ON claude_history(project);
            CREATE INDEX IF NOT EXISTS idx_history_timestamp ON claude_history(timestamp DESC);

            -- Project memory cache
            CREATE TABLE IF NOT EXISTS project_memory (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                project_path TEXT NOT NULL UNIQUE,
                content TEXT NOT NULL,
                synced_at TEXT DEFAULT (datetime('now'))
            );

            -- Plans cache
            CREATE TABLE IF NOT EXISTS plans (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                filename TEXT NOT NULL UNIQUE,
                size_bytes INTEGER DEFAULT 0,
                modified_at REAL,
                synced_at TEXT DEFAULT (datetime('now'))
            );

            -- Sync state (incremental sync tracking)
            CREATE TABLE IF NOT EXISTS sync_state (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TEXT DEFAULT (datetime('now'))
            );

            -- Record schema version
            INSERT INTO schema_version (version) VALUES (1);
            "
        ).map_err(|e| format!("Failed to apply schema v1: {e}"))?;

        log::info!("Applied database schema v1");
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Session CRUD
    // -----------------------------------------------------------------------

    /// Insert a new Maestro session. Returns the database row ID.
    pub fn insert_maestro_session(
        &self,
        maestro_session_id: u32,
        mode: &str,
        project_path: &str,
    ) -> Result<i64, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        conn.execute(
            "INSERT INTO sessions (maestro_session_id, mode, status, project_path)
             VALUES (?1, ?2, 'Idle', ?3)",
            params![maestro_session_id as i64, mode, project_path],
        ).map_err(|e| format!("Failed to insert session: {e}"))?;
        Ok(conn.last_insert_rowid())
    }

    /// Update session status by maestro_session_id.
    pub fn update_session_status(
        &self,
        maestro_session_id: u32,
        status: &str,
        status_message: Option<&str>,
        needs_input_prompt: Option<&str>,
    ) -> Result<bool, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        let rows = conn.execute(
            "UPDATE sessions SET status = ?1, status_message = ?2, needs_input_prompt = ?3,
             updated_at = datetime('now')
             WHERE maestro_session_id = ?4 AND ended_at IS NULL",
            params![status, status_message, needs_input_prompt, maestro_session_id as i64],
        ).map_err(|e| format!("Failed to update status: {e}"))?;
        Ok(rows > 0)
    }

    /// Link a Claude session UUID to a Maestro session.
    pub fn update_session_claude_uuid(
        &self,
        maestro_session_id: u32,
        uuid: &str,
    ) -> Result<bool, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        let rows = conn.execute(
            "UPDATE sessions SET claude_session_uuid = ?1, updated_at = datetime('now')
             WHERE maestro_session_id = ?2 AND ended_at IS NULL",
            params![uuid, maestro_session_id as i64],
        ).map_err(|e| format!("Failed to update claude_uuid: {e}"))?;
        Ok(rows > 0)
    }

    /// Rename a session by maestro_session_id.
    pub fn rename_session(
        &self,
        maestro_session_id: u32,
        name: Option<&str>,
    ) -> Result<bool, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        let rows = conn.execute(
            "UPDATE sessions SET name = ?1, updated_at = datetime('now')
             WHERE maestro_session_id = ?2",
            params![name, maestro_session_id as i64],
        ).map_err(|e| format!("Failed to rename session: {e}"))?;
        Ok(rows > 0)
    }

    /// Hide or unhide a session.
    pub fn set_session_hidden(
        &self,
        maestro_session_id: u32,
        hidden: bool,
    ) -> Result<bool, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        let rows = conn.execute(
            "UPDATE sessions SET hidden = ?1, updated_at = datetime('now')
             WHERE maestro_session_id = ?2",
            params![hidden as i32, maestro_session_id as i64],
        ).map_err(|e| format!("Failed to set hidden: {e}"))?;
        Ok(rows > 0)
    }

    /// Mark a session as ended (Done).
    pub fn mark_session_ended(
        &self,
        maestro_session_id: u32,
    ) -> Result<bool, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        let rows = conn.execute(
            "UPDATE sessions SET status = 'Done', ended_at = datetime('now'),
             updated_at = datetime('now')
             WHERE maestro_session_id = ?1 AND ended_at IS NULL",
            params![maestro_session_id as i64],
        ).map_err(|e| format!("Failed to mark ended: {e}"))?;
        Ok(rows > 0)
    }

    /// Update session branch and worktree path.
    pub fn assign_session_branch(
        &self,
        maestro_session_id: u32,
        branch: &str,
        worktree_path: Option<&str>,
    ) -> Result<bool, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        let rows = conn.execute(
            "UPDATE sessions SET branch = ?1, worktree_path = ?2, updated_at = datetime('now')
             WHERE maestro_session_id = ?3 AND ended_at IS NULL",
            params![branch, worktree_path, maestro_session_id as i64],
        ).map_err(|e| format!("Failed to assign branch: {e}"))?;
        Ok(rows > 0)
    }

    /// Mark all active (non-ended) sessions as Done. Called on app startup.
    pub fn mark_all_active_sessions_done(&self) -> Result<u64, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        let rows = conn.execute(
            "UPDATE sessions SET status = 'Done', ended_at = datetime('now'),
             updated_at = datetime('now')
             WHERE ended_at IS NULL AND status != 'Done'",
            [],
        ).map_err(|e| format!("Failed to mark all done: {e}"))?;
        if rows > 0 {
            log::info!("Marked {} active sessions as Done on startup", rows);
        }
        Ok(rows as u64)
    }

    // -----------------------------------------------------------------------
    // Session queries
    // -----------------------------------------------------------------------

    /// Get sessions for a project with filtering, sorting, pagination.
    pub fn get_sessions_for_project(
        &self,
        project_path: &str,
        opts: &QueryOptions,
    ) -> Result<PaginatedResult<SessionRow>, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;

        let mut where_clauses = vec!["project_path = ?1".to_string()];
        let include_hidden = opts.include_hidden.unwrap_or(false);
        if !include_hidden {
            where_clauses.push("hidden = 0".to_string());
        }

        // Status filter
        if let Some(statuses) = &opts.status {
            if !statuses.is_empty() {
                let placeholders: Vec<String> = statuses.iter().map(|s| format!("'{}'", s.replace('\'', "''"))).collect();
                where_clauses.push(format!("status IN ({})", placeholders.join(",")));
            }
        }

        // Mode filter
        if let Some(modes) = &opts.mode {
            if !modes.is_empty() {
                let placeholders: Vec<String> = modes.iter().map(|m| format!("'{}'", m.replace('\'', "''"))).collect();
                where_clauses.push(format!("mode IN ({})", placeholders.join(",")));
            }
        }

        // Search filter
        if let Some(search) = &opts.search {
            if !search.is_empty() {
                let escaped = search.replace('\'', "''").replace('%', "\\%");
                where_clauses.push(format!(
                    "(name LIKE '%{escaped}%' ESCAPE '\\' OR first_message LIKE '%{escaped}%' ESCAPE '\\')"
                ));
            }
        }

        let where_sql = where_clauses.join(" AND ");
        let sort_by = opts.sort_by.as_deref().unwrap_or("created_at");
        let sort_dir = opts.sort_dir.as_deref().unwrap_or("desc");

        // Validate sort column
        let sort_col = match sort_by {
            "created_at" | "updated_at" | "name" | "status" | "ended_at" => sort_by,
            _ => "created_at",
        };
        let sort_direction = if sort_dir.eq_ignore_ascii_case("asc") { "ASC" } else { "DESC" };

        let limit = opts.limit.unwrap_or(50);
        let offset = opts.offset.unwrap_or(0);

        // Count total
        let count_sql = format!("SELECT COUNT(*) FROM sessions WHERE {where_sql}");
        let total: i64 = conn
            .query_row(&count_sql, params![project_path], |row| row.get(0))
            .map_err(|e| format!("Failed to count sessions: {e}"))?;

        // Fetch rows
        let query_sql = format!(
            "SELECT id, maestro_session_id, claude_session_uuid, mode, name, branch, status,
                    worktree_path, project_path, hidden, status_message, needs_input_prompt,
                    first_message, model, transcript_path, total_input_tokens, total_output_tokens,
                    files_modified_count, tools_used, subagent_count,
                    created_at, updated_at, ended_at, claude_data_synced_at,
                    history_display, history_timestamp
             FROM sessions WHERE {where_sql}
             ORDER BY {sort_col} {sort_direction}
             LIMIT ?2 OFFSET ?3"
        );

        let mut stmt = conn
            .prepare(&query_sql)
            .map_err(|e| format!("Failed to prepare query: {e}"))?;

        let rows = stmt
            .query_map(params![project_path, limit, offset], |row| {
                Ok(SessionRow {
                    id: row.get(0)?,
                    maestro_session_id: row.get(1)?,
                    claude_session_uuid: row.get(2)?,
                    mode: row.get(3)?,
                    name: row.get(4)?,
                    branch: row.get(5)?,
                    status: row.get(6)?,
                    worktree_path: row.get(7)?,
                    project_path: row.get(8)?,
                    hidden: row.get::<_, i32>(9)? != 0,
                    status_message: row.get(10)?,
                    needs_input_prompt: row.get(11)?,
                    first_message: row.get(12)?,
                    model: row.get(13)?,
                    transcript_path: row.get(14)?,
                    total_input_tokens: row.get(15)?,
                    total_output_tokens: row.get(16)?,
                    files_modified_count: row.get(17)?,
                    tools_used: row.get(18)?,
                    subagent_count: row.get(19)?,
                    created_at: row.get(20)?,
                    updated_at: row.get(21)?,
                    ended_at: row.get(22)?,
                    claude_data_synced_at: row.get(23)?,
                    history_display: row.get(24)?,
                    history_timestamp: row.get(25)?,
                })
            })
            .map_err(|e| format!("Failed to query sessions: {e}"))?;

        let items: Vec<SessionRow> = rows.filter_map(|r| r.ok()).collect();

        Ok(PaginatedResult {
            items,
            total,
            offset,
            limit,
        })
    }

    /// Search sessions across all projects (or filtered to one).
    pub fn search_sessions(
        &self,
        query: &str,
        project_path: Option<&str>,
    ) -> Result<Vec<SessionRow>, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;

        let escaped = query.replace('\'', "''").replace('%', "\\%");
        let mut where_clauses = vec![format!(
            "(name LIKE '%{escaped}%' ESCAPE '\\' OR first_message LIKE '%{escaped}%' ESCAPE '\\' \
             OR history_display LIKE '%{escaped}%' ESCAPE '\\')"
        )];

        if let Some(pp) = project_path {
            where_clauses.push(format!("project_path = '{}'", pp.replace('\'', "''")));
        }

        let where_sql = where_clauses.join(" AND ");
        let sql = format!(
            "SELECT id, maestro_session_id, claude_session_uuid, mode, name, branch, status,
                    worktree_path, project_path, hidden, status_message, needs_input_prompt,
                    first_message, model, transcript_path, total_input_tokens, total_output_tokens,
                    files_modified_count, tools_used, subagent_count,
                    created_at, updated_at, ended_at, claude_data_synced_at,
                    history_display, history_timestamp
             FROM sessions WHERE {where_sql}
             ORDER BY created_at DESC LIMIT 100"
        );

        let mut stmt = conn
            .prepare(&sql)
            .map_err(|e| format!("Failed to prepare search: {e}"))?;

        let rows = stmt
            .query_map([], |row| {
                Ok(SessionRow {
                    id: row.get(0)?,
                    maestro_session_id: row.get(1)?,
                    claude_session_uuid: row.get(2)?,
                    mode: row.get(3)?,
                    name: row.get(4)?,
                    branch: row.get(5)?,
                    status: row.get(6)?,
                    worktree_path: row.get(7)?,
                    project_path: row.get(8)?,
                    hidden: row.get::<_, i32>(9)? != 0,
                    status_message: row.get(10)?,
                    needs_input_prompt: row.get(11)?,
                    first_message: row.get(12)?,
                    model: row.get(13)?,
                    transcript_path: row.get(14)?,
                    total_input_tokens: row.get(15)?,
                    total_output_tokens: row.get(16)?,
                    files_modified_count: row.get(17)?,
                    tools_used: row.get(18)?,
                    subagent_count: row.get(19)?,
                    created_at: row.get(20)?,
                    updated_at: row.get(21)?,
                    ended_at: row.get(22)?,
                    claude_data_synced_at: row.get(23)?,
                    history_display: row.get(24)?,
                    history_timestamp: row.get(25)?,
                })
            })
            .map_err(|e| format!("Failed to search sessions: {e}"))?;

        Ok(rows.filter_map(|r| r.ok()).collect())
    }

    // -----------------------------------------------------------------------
    // Session files
    // -----------------------------------------------------------------------

    /// Add a file entry for a session (by maestro_session_id).
    pub fn add_session_file(
        &self,
        maestro_session_id: u32,
        file_path: &str,
        action: &str,
    ) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;

        // Look up the DB session id
        let db_id: Option<i64> = conn
            .query_row(
                "SELECT id FROM sessions WHERE maestro_session_id = ?1 AND ended_at IS NULL",
                params![maestro_session_id as i64],
                |row| row.get(0),
            )
            .optional()
            .map_err(|e| format!("Failed to lookup session: {e}"))?;

        if let Some(session_id) = db_id {
            conn.execute(
                "INSERT INTO session_files (session_id, file_path, action, timestamp)
                 VALUES (?1, ?2, ?3, datetime('now'))",
                params![session_id, file_path, action],
            ).map_err(|e| format!("Failed to insert file: {e}"))?;

            // Update count
            conn.execute(
                "UPDATE sessions SET files_modified_count = (
                     SELECT COUNT(DISTINCT file_path) FROM session_files WHERE session_id = ?1
                 ), updated_at = datetime('now')
                 WHERE id = ?1",
                params![session_id],
            ).map_err(|e| format!("Failed to update file count: {e}"))?;
        }
        Ok(())
    }

    /// Get files for a session by DB id.
    pub fn get_session_files(&self, session_id: i64) -> Result<Vec<FileEntry>, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        let mut stmt = conn
            .prepare(
                "SELECT id, session_id, file_path, action, timestamp
                 FROM session_files WHERE session_id = ?1 ORDER BY id"
            )
            .map_err(|e| format!("Failed to prepare: {e}"))?;

        let rows = stmt
            .query_map(params![session_id], |row| {
                Ok(FileEntry {
                    id: row.get(0)?,
                    session_id: row.get(1)?,
                    file_path: row.get(2)?,
                    action: row.get(3)?,
                    timestamp: row.get(4)?,
                })
            })
            .map_err(|e| format!("Failed to query files: {e}"))?;

        Ok(rows.filter_map(|r| r.ok()).collect())
    }

    // -----------------------------------------------------------------------
    // Token usage write-through
    // -----------------------------------------------------------------------

    /// Add token usage to a session (incremental).
    pub fn add_session_tokens(
        &self,
        maestro_session_id: u32,
        input_tokens: i64,
        output_tokens: i64,
    ) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        conn.execute(
            "UPDATE sessions SET
             total_input_tokens = total_input_tokens + ?1,
             total_output_tokens = total_output_tokens + ?2,
             updated_at = datetime('now')
             WHERE maestro_session_id = ?3 AND ended_at IS NULL",
            params![input_tokens, output_tokens, maestro_session_id as i64],
        ).map_err(|e| format!("Failed to add tokens: {e}"))?;
        Ok(())
    }

    // -----------------------------------------------------------------------
    // History CRUD
    // -----------------------------------------------------------------------

    /// Bulk upsert history entries (deduplicate by timestamp + display).
    pub fn upsert_history_entries(
        &self,
        entries: &[(String, f64, Option<String>, Option<String>)],
    ) -> Result<usize, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        let mut count = 0;
        for (display, timestamp, project, session_id) in entries {
            let existing: bool = conn
                .query_row(
                    "SELECT COUNT(*) > 0 FROM claude_history WHERE timestamp = ?1 AND display = ?2",
                    params![timestamp, display],
                    |row| row.get(0),
                )
                .unwrap_or(false);

            if !existing {
                conn.execute(
                    "INSERT INTO claude_history (display, timestamp, project, session_id)
                     VALUES (?1, ?2, ?3, ?4)",
                    params![display, timestamp, project, session_id],
                ).map_err(|e| format!("Failed to insert history: {e}"))?;
                count += 1;
            }
        }
        Ok(count)
    }

    /// Get history entries, optionally filtered by project.
    pub fn get_history(
        &self,
        project_path: Option<&str>,
        limit: u32,
        offset: u32,
    ) -> Result<PaginatedResult<HistoryRow>, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;

        let (_where_sql, count_sql, query_sql) = if let Some(pp) = project_path {
            let escaped = pp.replace('\'', "''");
            (
                format!("WHERE project = '{escaped}'"),
                format!("SELECT COUNT(*) FROM claude_history WHERE project = '{escaped}'"),
                format!(
                    "SELECT id, display, timestamp, project, session_id, synced_at
                     FROM claude_history WHERE project = '{escaped}'
                     ORDER BY timestamp DESC LIMIT ?1 OFFSET ?2"
                ),
            )
        } else {
            (
                String::new(),
                "SELECT COUNT(*) FROM claude_history".to_string(),
                "SELECT id, display, timestamp, project, session_id, synced_at
                 FROM claude_history ORDER BY timestamp DESC LIMIT ?1 OFFSET ?2".to_string(),
            )
        };

        let total: i64 = conn
            .query_row(&count_sql, [], |row| row.get(0))
            .map_err(|e| format!("Failed to count history: {e}"))?;

        let mut stmt = conn
            .prepare(&query_sql)
            .map_err(|e| format!("Failed to prepare history query: {e}"))?;

        let rows = stmt
            .query_map(params![limit, offset], |row| {
                Ok(HistoryRow {
                    id: row.get(0)?,
                    display: row.get(1)?,
                    timestamp: row.get(2)?,
                    project: row.get(3)?,
                    session_id: row.get(4)?,
                    synced_at: row.get(5)?,
                })
            })
            .map_err(|e| format!("Failed to query history: {e}"))?;

        Ok(PaginatedResult {
            items: rows.filter_map(|r| r.ok()).collect(),
            total,
            offset,
            limit,
        })
    }

    // -----------------------------------------------------------------------
    // Project memory
    // -----------------------------------------------------------------------

    /// Upsert project memory content.
    pub fn upsert_project_memory(
        &self,
        project_path: &str,
        content: &str,
    ) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        conn.execute(
            "INSERT INTO project_memory (project_path, content, synced_at)
             VALUES (?1, ?2, datetime('now'))
             ON CONFLICT(project_path) DO UPDATE SET
                content = excluded.content,
                synced_at = datetime('now')",
            params![project_path, content],
        ).map_err(|e| format!("Failed to upsert memory: {e}"))?;
        Ok(())
    }

    /// Get project memory.
    pub fn get_project_memory(&self, project_path: &str) -> Result<Option<String>, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        conn.query_row(
            "SELECT content FROM project_memory WHERE project_path = ?1",
            params![project_path],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| format!("Failed to get memory: {e}"))
    }

    // -----------------------------------------------------------------------
    // Plans
    // -----------------------------------------------------------------------

    /// Upsert a plan entry.
    pub fn upsert_plan(
        &self,
        filename: &str,
        size_bytes: i64,
        modified_at: Option<f64>,
    ) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        conn.execute(
            "INSERT INTO plans (filename, size_bytes, modified_at, synced_at)
             VALUES (?1, ?2, ?3, datetime('now'))
             ON CONFLICT(filename) DO UPDATE SET
                size_bytes = excluded.size_bytes,
                modified_at = excluded.modified_at,
                synced_at = datetime('now')",
            params![filename, size_bytes, modified_at],
        ).map_err(|e| format!("Failed to upsert plan: {e}"))?;
        Ok(())
    }

    /// Get plans with pagination.
    pub fn get_plans(
        &self,
        limit: u32,
        offset: u32,
    ) -> Result<PaginatedResult<PlanRow>, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;

        let total: i64 = conn
            .query_row("SELECT COUNT(*) FROM plans", [], |row| row.get(0))
            .map_err(|e| format!("Failed to count plans: {e}"))?;

        let mut stmt = conn
            .prepare(
                "SELECT id, filename, size_bytes, modified_at, synced_at
                 FROM plans ORDER BY modified_at DESC NULLS LAST
                 LIMIT ?1 OFFSET ?2"
            )
            .map_err(|e| format!("Failed to prepare plans query: {e}"))?;

        let rows = stmt
            .query_map(params![limit, offset], |row| {
                Ok(PlanRow {
                    id: row.get(0)?,
                    filename: row.get(1)?,
                    size_bytes: row.get(2)?,
                    modified_at: row.get(3)?,
                    synced_at: row.get(4)?,
                })
            })
            .map_err(|e| format!("Failed to query plans: {e}"))?;

        Ok(PaginatedResult {
            items: rows.filter_map(|r| r.ok()).collect(),
            total,
            offset,
            limit,
        })
    }

    // -----------------------------------------------------------------------
    // Sync state
    // -----------------------------------------------------------------------

    /// Get a sync state value.
    pub fn get_sync_state(&self, key: &str) -> Result<Option<String>, String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        conn.query_row(
            "SELECT value FROM sync_state WHERE key = ?1",
            params![key],
            |row| row.get(0),
        )
        .optional()
        .map_err(|e| format!("Failed to get sync state: {e}"))
    }

    /// Set a sync state value.
    pub fn set_sync_state(&self, key: &str, value: &str) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        conn.execute(
            "INSERT INTO sync_state (key, value, updated_at)
             VALUES (?1, ?2, datetime('now'))
             ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = datetime('now')",
            params![key, value],
        ).map_err(|e| format!("Failed to set sync state: {e}"))?;
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Claude session upsert (from sync)
    // -----------------------------------------------------------------------

    /// Upsert a Claude Code session discovered during sync.
    pub fn upsert_claude_session(
        &self,
        claude_session_uuid: &str,
        project_path: &str,
        first_message: Option<&str>,
        model: Option<&str>,
        transcript_path: Option<&str>,
        total_input_tokens: i64,
        total_output_tokens: i64,
        files_modified_count: i64,
        tools_used: Option<&str>,
        subagent_count: i64,
        history_display: Option<&str>,
        history_timestamp: Option<f64>,
    ) -> Result<(), String> {
        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;

        // Check if session exists (by claude_session_uuid)
        let existing_id: Option<i64> = conn
            .query_row(
                "SELECT id FROM sessions WHERE claude_session_uuid = ?1",
                params![claude_session_uuid],
                |row| row.get(0),
            )
            .optional()
            .map_err(|e| format!("Failed to check existing: {e}"))?;

        if let Some(id) = existing_id {
            // Update enrichment data
            conn.execute(
                "UPDATE sessions SET
                 first_message = COALESCE(?1, first_message),
                 model = COALESCE(?2, model),
                 transcript_path = COALESCE(?3, transcript_path),
                 total_input_tokens = CASE WHEN ?4 > total_input_tokens THEN ?4 ELSE total_input_tokens END,
                 total_output_tokens = CASE WHEN ?5 > total_output_tokens THEN ?5 ELSE total_output_tokens END,
                 files_modified_count = CASE WHEN ?6 > files_modified_count THEN ?6 ELSE files_modified_count END,
                 tools_used = COALESCE(?7, tools_used),
                 subagent_count = CASE WHEN ?8 > subagent_count THEN ?8 ELSE subagent_count END,
                 history_display = COALESCE(?9, history_display),
                 history_timestamp = COALESCE(?10, history_timestamp),
                 claude_data_synced_at = datetime('now'),
                 updated_at = datetime('now')
                 WHERE id = ?11",
                params![
                    first_message, model, transcript_path,
                    total_input_tokens, total_output_tokens, files_modified_count,
                    tools_used, subagent_count,
                    history_display, history_timestamp,
                    id,
                ],
            ).map_err(|e| format!("Failed to update claude session: {e}"))?;
        } else {
            // Insert new Claude-only session
            conn.execute(
                "INSERT INTO sessions (
                    claude_session_uuid, mode, status, project_path,
                    first_message, model, transcript_path,
                    total_input_tokens, total_output_tokens, files_modified_count,
                    tools_used, subagent_count,
                    history_display, history_timestamp,
                    claude_data_synced_at
                 ) VALUES (?1, 'Claude', 'Done', ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, datetime('now'))",
                params![
                    claude_session_uuid, project_path,
                    first_message, model, transcript_path,
                    total_input_tokens, total_output_tokens, files_modified_count,
                    tools_used, subagent_count,
                    history_display, history_timestamp,
                ],
            ).map_err(|e| format!("Failed to insert claude session: {e}"))?;
        }
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Migration from store.json
    // -----------------------------------------------------------------------

    /// One-time migration from Zustand persist data (store.json).
    /// Reads serialized sessions and imports them into SQLite.
    pub fn migrate_from_store_json(&self, store_path: &Path) -> Result<usize, String> {
        // Check if already migrated
        if let Some(val) = self.get_sync_state("store_json_migrated")? {
            if val == "true" {
                return Ok(0);
            }
        }

        if !store_path.exists() {
            self.set_sync_state("store_json_migrated", "true")?;
            return Ok(0);
        }

        let content = std::fs::read_to_string(store_path)
            .map_err(|e| format!("Failed to read store.json: {e}"))?;

        // Parse the store JSON — sessions are under "maestro-sessions" key
        let store_val: serde_json::Value = serde_json::from_str(&content)
            .map_err(|e| format!("Failed to parse store.json: {e}"))?;

        let sessions_str = store_val
            .get("maestro-sessions")
            .and_then(|v| v.as_str());

        let count = if let Some(sessions_json) = sessions_str {
            self.import_sessions_json(sessions_json)?
        } else {
            // Try direct object format
            if let Some(sessions_obj) = store_val.get("maestro-sessions") {
                let json_str = serde_json::to_string(sessions_obj).unwrap_or_default();
                self.import_sessions_json(&json_str)?
            } else {
                0
            }
        };

        self.set_sync_state("store_json_migrated", "true")?;
        if count > 0 {
            log::info!("Migrated {} sessions from store.json to SQLite", count);
        }
        Ok(count)
    }

    fn import_sessions_json(&self, json: &str) -> Result<usize, String> {
        #[derive(Deserialize)]
        struct PersistedState {
            #[serde(default)]
            sessions: Vec<PersistedSession>,
        }

        #[derive(Deserialize)]
        struct PersistedSession {
            id: u32,
            mode: String,
            name: Option<String>,
            branch: Option<String>,
            worktree_path: Option<String>,
            project_path: String,
            #[serde(default)]
            hidden: bool,
            claude_session_uuid: Option<String>,
        }

        // Try parsing as the persist wrapper format first
        let sessions = if let Ok(state) = serde_json::from_str::<PersistedState>(json) {
            state.sessions
        } else if let Ok(wrapper) = serde_json::from_str::<serde_json::Value>(json) {
            // Zustand persist wraps as { state: { sessions: [...] }, version: N }
            if let Some(state) = wrapper.get("state") {
                serde_json::from_value::<PersistedState>(state.clone())
                    .map(|s| s.sessions)
                    .unwrap_or_default()
            } else {
                Vec::new()
            }
        } else {
            Vec::new()
        };

        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        let mut count = 0;
        for s in &sessions {
            // Check if already exists
            let exists: bool = conn
                .query_row(
                    "SELECT COUNT(*) > 0 FROM sessions WHERE maestro_session_id = ?1",
                    params![s.id as i64],
                    |row| row.get(0),
                )
                .unwrap_or(false);

            if !exists {
                conn.execute(
                    "INSERT INTO sessions (maestro_session_id, claude_session_uuid, mode, name, branch,
                     status, worktree_path, project_path, hidden, ended_at)
                     VALUES (?1, ?2, ?3, ?4, ?5, 'Done', ?6, ?7, ?8, datetime('now'))",
                    params![
                        s.id as i64,
                        s.claude_session_uuid,
                        s.mode,
                        s.name,
                        s.branch,
                        s.worktree_path,
                        s.project_path,
                        s.hidden as i32,
                    ],
                ).map_err(|e| format!("Failed to import session {}: {e}", s.id))?;
                count += 1;
            }
        }
        Ok(count)
    }

    /// Delete stale plans that no longer exist on disk.
    pub fn delete_plans_not_in(&self, filenames: &[String]) -> Result<usize, String> {
        if filenames.is_empty() {
            // Delete all plans if none exist on disk
            let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
            let rows = conn
                .execute("DELETE FROM plans", [])
                .map_err(|e| format!("Failed to delete plans: {e}"))?;
            return Ok(rows);
        }

        let conn = self.conn.lock().map_err(|e| format!("Lock error: {e}"))?;
        let placeholders: Vec<String> = filenames
            .iter()
            .map(|f| format!("'{}'", f.replace('\'', "''")))
            .collect();
        let sql = format!(
            "DELETE FROM plans WHERE filename NOT IN ({})",
            placeholders.join(",")
        );
        let rows = conn
            .execute(&sql, [])
            .map_err(|e| format!("Failed to delete stale plans: {e}"))?;
        Ok(rows)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    fn create_test_db() -> (Database, TempDir) {
        let tmp = TempDir::new().unwrap();
        let db_path = tmp.path().join("test.db");
        let db = Database::open(&db_path).unwrap();
        (db, tmp)
    }

    #[test]
    fn test_create_and_query_session() {
        let (db, _tmp) = create_test_db();

        let row_id = db.insert_maestro_session(1, "Claude", "/test/project").unwrap();
        assert!(row_id > 0);

        let result = db
            .get_sessions_for_project("/test/project", &QueryOptions::default())
            .unwrap();
        assert_eq!(result.items.len(), 1);
        assert_eq!(result.items[0].maestro_session_id, Some(1));
        assert_eq!(result.items[0].status, "Idle");
    }

    #[test]
    fn test_update_status() {
        let (db, _tmp) = create_test_db();
        db.insert_maestro_session(1, "Claude", "/test").unwrap();

        let updated = db.update_session_status(1, "Working", Some("Editing files"), None).unwrap();
        assert!(updated);

        let result = db.get_sessions_for_project("/test", &QueryOptions::default()).unwrap();
        assert_eq!(result.items[0].status, "Working");
        assert_eq!(result.items[0].status_message.as_deref(), Some("Editing files"));
    }

    #[test]
    fn test_mark_all_done() {
        let (db, _tmp) = create_test_db();
        db.insert_maestro_session(1, "Claude", "/test").unwrap();
        db.insert_maestro_session(2, "Claude", "/test").unwrap();

        let count = db.mark_all_active_sessions_done().unwrap();
        assert_eq!(count, 2);

        let result = db.get_sessions_for_project("/test", &QueryOptions::default()).unwrap();
        assert!(result.items.iter().all(|s| s.status == "Done"));
    }

    #[test]
    fn test_history_upsert() {
        let (db, _tmp) = create_test_db();
        let entries = vec![
            ("test command".to_string(), 1234567890.0, Some("/project".to_string()), Some("session-1".to_string())),
        ];
        let count = db.upsert_history_entries(&entries).unwrap();
        assert_eq!(count, 1);

        // Duplicate should not insert
        let count2 = db.upsert_history_entries(&entries).unwrap();
        assert_eq!(count2, 0);
    }

    #[test]
    fn test_sync_state() {
        let (db, _tmp) = create_test_db();
        assert_eq!(db.get_sync_state("test_key").unwrap(), None);

        db.set_sync_state("test_key", "test_value").unwrap();
        assert_eq!(db.get_sync_state("test_key").unwrap(), Some("test_value".to_string()));

        db.set_sync_state("test_key", "updated").unwrap();
        assert_eq!(db.get_sync_state("test_key").unwrap(), Some("updated".to_string()));
    }

    #[test]
    fn test_project_memory() {
        let (db, _tmp) = create_test_db();
        assert_eq!(db.get_project_memory("/test").unwrap(), None);

        db.upsert_project_memory("/test", "# Memory").unwrap();
        assert_eq!(db.get_project_memory("/test").unwrap(), Some("# Memory".to_string()));

        db.upsert_project_memory("/test", "# Updated").unwrap();
        assert_eq!(db.get_project_memory("/test").unwrap(), Some("# Updated".to_string()));
    }
}
