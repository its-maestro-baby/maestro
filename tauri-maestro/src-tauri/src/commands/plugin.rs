//! IPC commands for plugin/skill discovery and session configuration.

use tauri::State;

use crate::core::plugin_manager::{PluginManager, ProjectPlugins};

/// Discovers and returns plugins/skills configured in the project's `.plugins.json`.
///
/// The project path is canonicalized before lookup. Results are cached.
#[tauri::command]
pub async fn get_project_plugins(
    state: State<'_, PluginManager>,
    project_path: String,
) -> Result<ProjectPlugins, String> {
    let canonical = std::fs::canonicalize(&project_path)
        .map_err(|e| format!("Invalid project path '{}': {}", project_path, e))?
        .to_string_lossy()
        .into_owned();

    Ok(state.get_project_plugins(&canonical))
}

/// Re-parses the `.plugins.json` file for a project, updating the cache.
#[tauri::command]
pub async fn refresh_project_plugins(
    state: State<'_, PluginManager>,
    project_path: String,
) -> Result<ProjectPlugins, String> {
    let canonical = std::fs::canonicalize(&project_path)
        .map_err(|e| format!("Invalid project path '{}': {}", project_path, e))?
        .to_string_lossy()
        .into_owned();

    Ok(state.refresh_project_plugins(&canonical))
}

/// Gets the enabled skill IDs for a specific session.
///
/// If not explicitly set, returns all available skills as enabled.
#[tauri::command]
pub async fn get_session_skills(
    state: State<'_, PluginManager>,
    project_path: String,
    session_id: u32,
) -> Result<Vec<String>, String> {
    let canonical = std::fs::canonicalize(&project_path)
        .map_err(|e| format!("Invalid project path '{}': {}", project_path, e))?
        .to_string_lossy()
        .into_owned();

    Ok(state.get_session_skills(&canonical, session_id))
}

/// Sets the enabled skill IDs for a specific session.
#[tauri::command]
pub async fn set_session_skills(
    state: State<'_, PluginManager>,
    project_path: String,
    session_id: u32,
    enabled: Vec<String>,
) -> Result<(), String> {
    let canonical = std::fs::canonicalize(&project_path)
        .map_err(|e| format!("Invalid project path '{}': {}", project_path, e))?
        .to_string_lossy()
        .into_owned();

    state.set_session_skills(&canonical, session_id, enabled);
    Ok(())
}

/// Gets the enabled plugin IDs for a specific session.
///
/// If not explicitly set, returns plugins where enabled_by_default is true.
#[tauri::command]
pub async fn get_session_plugins(
    state: State<'_, PluginManager>,
    project_path: String,
    session_id: u32,
) -> Result<Vec<String>, String> {
    let canonical = std::fs::canonicalize(&project_path)
        .map_err(|e| format!("Invalid project path '{}': {}", project_path, e))?
        .to_string_lossy()
        .into_owned();

    Ok(state.get_session_plugins(&canonical, session_id))
}

/// Sets the enabled plugin IDs for a specific session.
#[tauri::command]
pub async fn set_session_plugins(
    state: State<'_, PluginManager>,
    project_path: String,
    session_id: u32,
    enabled: Vec<String>,
) -> Result<(), String> {
    let canonical = std::fs::canonicalize(&project_path)
        .map_err(|e| format!("Invalid project path '{}': {}", project_path, e))?
        .to_string_lossy()
        .into_owned();

    state.set_session_plugins(&canonical, session_id, enabled);
    Ok(())
}

/// Returns the count of enabled skills for a session.
#[tauri::command]
pub async fn get_session_skills_count(
    state: State<'_, PluginManager>,
    project_path: String,
    session_id: u32,
) -> Result<usize, String> {
    let canonical = std::fs::canonicalize(&project_path)
        .map_err(|e| format!("Invalid project path '{}': {}", project_path, e))?
        .to_string_lossy()
        .into_owned();

    Ok(state.get_skills_count(&canonical, session_id))
}

/// Returns the count of enabled plugins for a session.
#[tauri::command]
pub async fn get_session_plugins_count(
    state: State<'_, PluginManager>,
    project_path: String,
    session_id: u32,
) -> Result<usize, String> {
    let canonical = std::fs::canonicalize(&project_path)
        .map_err(|e| format!("Invalid project path '{}': {}", project_path, e))?
        .to_string_lossy()
        .into_owned();

    Ok(state.get_plugins_count(&canonical, session_id))
}
