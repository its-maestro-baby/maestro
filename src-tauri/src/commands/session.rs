use std::path::Path;
use std::sync::Arc;

use tauri::State;

use crate::core::database::Database;
use crate::core::mcp_config_writer;
use crate::core::mcp_manager::McpManager;
use crate::core::plugin_manager::PluginManager;
use crate::core::process_manager::ProcessManager;
use crate::core::session_manager::{AiMode, SessionConfig, SessionManager, SessionStatus};
use crate::core::status_server::StatusServer;

/// Exposes `SessionManager::all_sessions` to the frontend.
/// Returns a snapshot of all active sessions in arbitrary order.
#[tauri::command]
pub async fn get_sessions(state: State<'_, SessionManager>) -> Result<Vec<SessionConfig>, String> {
    Ok(state.all_sessions())
}

/// Exposes `SessionManager::create_session` to the frontend.
/// Registers a new session with `Idle` status. Returns an error if the
/// session ID already exists.
#[tauri::command]
pub async fn create_session(
    state: State<'_, SessionManager>,
    db: State<'_, Arc<Database>>,
    id: u32,
    mode: AiMode,
    project_path: String,
) -> Result<SessionConfig, String> {
    // Canonicalize path for consistent storage
    let canonical = std::fs::canonicalize(&project_path)
        .map_err(|e| format!("Invalid project path '{}': {}", project_path, e))?
        .to_string_lossy()
        .into_owned();

    let mode_str = format!("{:?}", mode);
    let result = state.create_session(id, mode, canonical.clone())
        .map_err(|existing| format!("Session {} already exists", existing.id))?;

    // Write-through to SQLite
    if let Err(e) = db.insert_maestro_session(id, &mode_str, &canonical) {
        log::warn!("Failed to write session {} to SQLite: {}", id, e);
    }

    Ok(result)
}

/// Exposes `SessionManager::update_status` to the frontend.
/// Returns `false` if the session does not exist (no error raised).
#[tauri::command]
pub async fn update_session_status(
    state: State<'_, SessionManager>,
    db: State<'_, Arc<Database>>,
    session_id: u32,
    status: SessionStatus,
) -> Result<bool, String> {
    let status_str = format!("{:?}", status);
    let result = state.update_status(session_id, status);

    // Write-through to SQLite
    if result {
        if let Err(e) = db.update_session_status(session_id, &status_str, None, None) {
            log::warn!("Failed to update session {} status in SQLite: {}", session_id, e);
        }
    }

    Ok(result)
}

/// Exposes `SessionManager::assign_branch` to the frontend.
/// Links a session to a branch and optional worktree path. Returns an error
/// string if the session does not exist.
#[tauri::command]
pub async fn assign_session_branch(
    state: State<'_, SessionManager>,
    db: State<'_, Arc<Database>>,
    session_id: u32,
    branch: String,
    worktree_path: Option<String>,
) -> Result<SessionConfig, String> {
    let result = state
        .assign_branch(session_id, branch.clone(), worktree_path.clone())
        .ok_or_else(|| format!("Session {} not found", session_id))?;

    // Write-through to SQLite
    if let Err(e) = db.assign_session_branch(session_id, &branch, worktree_path.as_deref()) {
        log::warn!("Failed to assign branch for session {} in SQLite: {}", session_id, e);
    }

    Ok(result)
}

/// Exposes `SessionManager::remove_session` to the frontend.
/// Returns the removed session config, or `None` if it was not found.
#[tauri::command]
pub async fn remove_session(
    state: State<'_, SessionManager>,
    db: State<'_, Arc<Database>>,
    session_id: u32,
) -> Result<Option<SessionConfig>, String> {
    let result = state.remove_session(session_id);

    // Write-through: mark as ended in SQLite (don't delete, just mark Done)
    if result.is_some() {
        if let Err(e) = db.mark_session_ended(session_id) {
            log::warn!("Failed to mark session {} ended in SQLite: {}", session_id, e);
        }
    }

    Ok(result)
}

/// Renames a session. Pass `None` to clear the custom name.
#[tauri::command]
pub async fn rename_session(
    state: State<'_, SessionManager>,
    db: State<'_, Arc<Database>>,
    session_id: u32,
    name: Option<String>,
) -> Result<bool, String> {
    let result = state.rename_session(session_id, name.clone());

    // Write-through to SQLite
    if result {
        if let Err(e) = db.rename_session(session_id, name.as_deref()) {
            log::warn!("Failed to rename session {} in SQLite: {}", session_id, e);
        }
    }

    Ok(result)
}

/// Hides or unhides a session from the sidebar.
#[tauri::command]
pub async fn hide_session(
    state: State<'_, SessionManager>,
    db: State<'_, Arc<Database>>,
    session_id: u32,
    hidden: bool,
) -> Result<bool, String> {
    let result = state.set_session_hidden(session_id, hidden);

    // Write-through to SQLite
    if result {
        if let Err(e) = db.set_session_hidden(session_id, hidden) {
            log::warn!("Failed to set hidden for session {} in SQLite: {}", session_id, e);
        }
    }

    Ok(result)
}

/// Associates a Claude session UUID with a session.
#[tauri::command]
pub async fn set_session_claude_uuid(
    state: State<'_, SessionManager>,
    db: State<'_, Arc<Database>>,
    session_id: u32,
    uuid: String,
) -> Result<bool, String> {
    let result = state.set_claude_session_uuid(session_id, uuid.clone());

    // Write-through to SQLite
    if result {
        if let Err(e) = db.update_session_claude_uuid(session_id, &uuid) {
            log::warn!("Failed to set claude_uuid for session {} in SQLite: {}", session_id, e);
        }
    }

    Ok(result)
}

/// Gets all sessions for a specific project.
#[tauri::command]
pub async fn get_sessions_for_project(
    state: State<'_, SessionManager>,
    project_path: String,
) -> Result<Vec<SessionConfig>, String> {
    let canonical = std::fs::canonicalize(&project_path)
        .map_err(|e| format!("Invalid project path '{}': {}", project_path, e))?
        .to_string_lossy()
        .into_owned();

    Ok(state.get_sessions_for_project(&canonical))
}

/// Removes all sessions for a project (used when closing a project tab).
/// Also kills the associated PTY sessions and cleans up MCP/plugin state.
#[tauri::command]
pub async fn remove_sessions_for_project(
    state: State<'_, SessionManager>,
    db: State<'_, Arc<Database>>,
    process_manager: State<'_, ProcessManager>,
    mcp_manager: State<'_, McpManager>,
    status_server: State<'_, Arc<StatusServer>>,
    plugin_manager: State<'_, PluginManager>,
    project_path: String,
) -> Result<Vec<SessionConfig>, String> {
    let canonical = std::fs::canonicalize(&project_path)
        .map_err(|e| format!("Invalid project path '{}': {}", project_path, e))?
        .to_string_lossy()
        .into_owned();

    let removed = state.remove_sessions_for_project(&canonical);

    // Write-through: mark removed sessions as ended in SQLite
    for session in &removed {
        if let Err(e) = db.mark_session_ended(session.id) {
            log::warn!("Failed to mark session {} ended in SQLite: {}", session.id, e);
        }
    }

    // Clean up MCP, plugin, and PTY state for each removed session
    for session in &removed {
        // Clean up in-memory MCP and plugin state
        mcp_manager.remove_session(&canonical, session.id);
        plugin_manager.remove_session(&canonical, session.id);

        // Unregister session from status server
        status_server.unregister_session(session.id).await;

        // Clean up .mcp.json entry (use worktree_path if set, otherwise project_path)
        let working_dir = session
            .worktree_path
            .as_deref()
            .unwrap_or(&session.project_path);
        if let Err(e) =
            mcp_config_writer::remove_session_mcp_config(Path::new(working_dir), session.id).await
        {
            log::warn!(
                "Failed to remove MCP config for session {}: {}",
                session.id,
                e
            );
        }

        // Fire-and-forget kill -- log errors but don't fail the removal
        if let Err(e) = process_manager.kill_session(session.id).await {
            log::warn!("Failed to kill PTY for session {}: {}", session.id, e);
        }
    }

    log::debug!(
        "Removed {} sessions for project {}",
        removed.len(),
        canonical
    );

    Ok(removed)
}
