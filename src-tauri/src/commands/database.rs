//! IPC commands for querying the unified SQLite database.

use std::sync::Arc;

use tauri::State;

use crate::core::claude_data_sync::ClaudeDataSyncTask;
use crate::core::database::{
    Database, FileEntry, HistoryRow, PaginatedResult, PlanRow, QueryOptions, SessionRow,
};

/// Get sessions for a project with filtering, sorting, and pagination.
#[tauri::command]
pub async fn db_get_sessions_for_project(
    db: State<'_, Arc<Database>>,
    project_path: String,
    opts: Option<QueryOptions>,
) -> Result<PaginatedResult<SessionRow>, String> {
    let opts = opts.unwrap_or_default();
    db.get_sessions_for_project(&project_path, &opts)
}

/// Search sessions across projects by query string.
#[tauri::command]
pub async fn db_search_sessions(
    db: State<'_, Arc<Database>>,
    query: String,
    project_path: Option<String>,
) -> Result<Vec<SessionRow>, String> {
    db.search_sessions(&query, project_path.as_deref())
}

/// Get history entries with optional project filter and pagination.
#[tauri::command]
pub async fn db_get_history(
    db: State<'_, Arc<Database>>,
    project_path: Option<String>,
    limit: Option<u32>,
    offset: Option<u32>,
) -> Result<PaginatedResult<HistoryRow>, String> {
    db.get_history(project_path.as_deref(), limit.unwrap_or(50), offset.unwrap_or(0))
}

/// Get project memory content.
#[tauri::command]
pub async fn db_get_project_memory(
    db: State<'_, Arc<Database>>,
    project_path: String,
) -> Result<Option<String>, String> {
    db.get_project_memory(&project_path)
}

/// Get plans with pagination.
#[tauri::command]
pub async fn db_get_plans(
    db: State<'_, Arc<Database>>,
    limit: Option<u32>,
    offset: Option<u32>,
) -> Result<PaginatedResult<PlanRow>, String> {
    db.get_plans(limit.unwrap_or(50), offset.unwrap_or(0))
}

/// Get files modified by a session.
#[tauri::command]
pub async fn db_get_session_files(
    db: State<'_, Arc<Database>>,
    session_id: i64,
) -> Result<Vec<FileEntry>, String> {
    db.get_session_files(session_id)
}

/// Trigger a manual sync of Claude Code data.
#[tauri::command]
pub async fn db_trigger_sync(
    db: State<'_, Arc<Database>>,
) -> Result<(), String> {
    ClaudeDataSyncTask::sync_all(&db).await
}

/// Add token usage to a session (write-through from frontend activity events).
#[tauri::command]
pub async fn db_add_session_tokens(
    db: State<'_, Arc<Database>>,
    maestro_session_id: u32,
    input_tokens: i64,
    output_tokens: i64,
) -> Result<(), String> {
    db.add_session_tokens(maestro_session_id, input_tokens, output_tokens)
}

/// Add a file modification entry for a session.
#[tauri::command]
pub async fn db_add_session_file(
    db: State<'_, Arc<Database>>,
    maestro_session_id: u32,
    file_path: String,
    action: String,
) -> Result<(), String> {
    db.add_session_file(maestro_session_id, &file_path, &action)
}
