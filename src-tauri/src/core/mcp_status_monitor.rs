//! MCP status file monitoring for agent state updates.
//!
//! Polls `/tmp/maestro/agents/<project_hash>/` for agent state JSON files
//! written by the maestro-status MCP server. Emits `session-status-changed`
//! events to the frontend when agent states change.
//!
//! Supports multiple projects simultaneously - each project is tracked
//! independently so sessions in different projects don't interfere.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tauri::{AppHandle, Emitter};
use tokio::sync::RwLock;

/// Agent status states as reported via the maestro_status MCP tool.
/// Must match the Swift `AgentStatusState` enum for compatibility.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgentStatusState {
    Idle,
    Working,
    NeedsInput,
    Finished,
    Error,
}

/// Agent state as written to JSON files by the MCP server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentState {
    #[serde(rename = "agentId")]
    pub agent_id: String,
    pub state: AgentStatusState,
    pub message: String,
    #[serde(rename = "needsInputPrompt")]
    pub needs_input_prompt: Option<String>,
    pub timestamp: String,
}

impl AgentState {
    /// Extract session ID from agent ID (e.g., "agent-1" -> Some(1))
    pub fn session_id(&self) -> Option<u32> {
        self.agent_id
            .strip_prefix("agent-")
            .and_then(|s| s.parse().ok())
    }
}

/// Payload emitted to the frontend for status changes.
/// Includes project_path to allow frontend filtering by project.
#[derive(Debug, Clone, Serialize)]
struct SessionStatusPayload {
    session_id: u32,
    project_path: String,
    status: String,
    message: String,
    needs_input_prompt: Option<String>,
}

/// Monitors agent state files and emits events on status changes.
/// Supports tracking multiple projects simultaneously.
pub struct McpStatusMonitor {
    /// Base directory for agent state files.
    base_state_dir: PathBuf,
    /// Active projects being monitored: project_path -> (hash, previous_states).
    /// Each project maintains its own previous states for change detection.
    active_projects: Arc<RwLock<HashMap<String, ProjectMonitorState>>>,
    /// Flag to stop the polling loop.
    running: Arc<RwLock<bool>>,
}

/// State tracked per project for change detection.
struct ProjectMonitorState {
    /// SHA256 hash (first 12 hex chars) of the project path.
    hash: String,
    /// Previous agent states keyed by agent ID.
    previous_states: HashMap<String, AgentStatusState>,
}

impl McpStatusMonitor {
    /// Creates a new monitor with the default base directory.
    pub fn new() -> Self {
        Self {
            base_state_dir: PathBuf::from("/tmp/maestro/agents"),
            active_projects: Arc::new(RwLock::new(HashMap::new())),
            running: Arc::new(RwLock::new(false)),
        }
    }

    /// Generate a stable hash for a project path.
    /// Uses first 12 characters of SHA256 hex for uniqueness.
    /// Must match Swift `MaestroStateMonitor.generateProjectHash`.
    pub fn generate_project_hash(project_path: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(project_path.as_bytes());
        let result = hasher.finalize();
        // Take first 6 bytes = 12 hex characters
        hex::encode(&result[..6])
    }

    /// Add a project to be monitored.
    /// Does nothing if the project is already being monitored.
    pub async fn add_project(&self, project_path: &str) {
        let mut projects = self.active_projects.write().await;
        if projects.contains_key(project_path) {
            log::debug!("Project already being monitored: {}", project_path);
            return;
        }

        let hash = Self::generate_project_hash(project_path);
        log::debug!(
            "Adding project to MCP monitor: {} -> hash {}",
            project_path,
            hash
        );

        projects.insert(
            project_path.to_string(),
            ProjectMonitorState {
                hash,
                previous_states: HashMap::new(),
            },
        );
    }

    /// Remove a project from monitoring.
    /// Does nothing if the project wasn't being monitored.
    pub async fn remove_project(&self, project_path: &str) {
        let mut projects = self.active_projects.write().await;
        if projects.remove(project_path).is_some() {
            log::debug!("Removed project from MCP monitor: {}", project_path);
        }
    }

    /// Remove a session's status file to prevent stale status from polluting new sessions.
    /// Call this when a session is killed.
    pub async fn remove_session_status(&self, project_path: &str, session_id: u32) {
        let hash = Self::generate_project_hash(project_path);
        let status_file = self.base_state_dir.join(&hash).join(format!("agent-{}.json", session_id));

        if let Err(e) = tokio::fs::remove_file(&status_file).await {
            // Only log if it's not a "file not found" error
            if e.kind() != std::io::ErrorKind::NotFound {
                log::warn!("Failed to remove status file {:?}: {}", status_file, e);
            }
        } else {
            log::debug!("Removed status file for session {} in project {}", session_id, project_path);
        }

        // Also clear from previous_states so we don't keep emitting for a dead session
        let mut projects = self.active_projects.write().await;
        if let Some(project_state) = projects.get_mut(project_path) {
            project_state.previous_states.remove(&format!("agent-{}", session_id));
        }
    }

    /// Check if a project is currently being monitored.
    pub async fn is_monitoring_project(&self, project_path: &str) -> bool {
        self.active_projects.read().await.contains_key(project_path)
    }

    /// Get the number of projects currently being monitored.
    pub async fn active_project_count(&self) -> usize {
        self.active_projects.read().await.len()
    }

    /// Start the polling loop. Should be spawned as an async task.
    pub async fn start_polling(self: Arc<Self>, app: AppHandle) {
        // Mark as running
        *self.running.write().await = true;
        log::info!("Starting MCP status monitor polling");

        loop {
            // Check if we should stop
            if !*self.running.read().await {
                log::info!("MCP status monitor stopped");
                break;
            }

            // Poll all active projects
            if !self.active_projects.read().await.is_empty() {
                self.poll_all_projects(&app).await;
            }

            // Wait 500ms before next poll
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }
    }

    /// Stop the polling loop.
    pub async fn stop(&self) {
        *self.running.write().await = false;
    }

    /// Poll all active projects and emit events for changes.
    async fn poll_all_projects(&self, app: &AppHandle) {
        // Get a snapshot of active projects to iterate over
        let project_paths: Vec<String> = self
            .active_projects
            .read()
            .await
            .keys()
            .cloned()
            .collect();

        for project_path in project_paths {
            self.poll_project(&project_path, app).await;
        }
    }

    /// Poll a single project's state files and emit events for changes.
    async fn poll_project(&self, project_path: &str, app: &AppHandle) {
        // Get the hash for this project
        let hash = {
            let projects = self.active_projects.read().await;
            match projects.get(project_path) {
                Some(state) => state.hash.clone(),
                None => return, // Project was removed while iterating
            }
        };

        let state_dir = self.base_state_dir.join(&hash);

        // Read directory contents
        let entries = match tokio::fs::read_dir(&state_dir).await {
            Ok(entries) => entries,
            Err(_) => return, // Directory doesn't exist yet, that's fine
        };

        let mut entries = entries;
        let mut current_states: HashMap<String, AgentState> = HashMap::new();

        while let Ok(Some(entry)) = entries.next_entry().await {
            let path = entry.path();

            // Only process .json files
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }

            // Read and parse the file
            let content = match tokio::fs::read_to_string(&path).await {
                Ok(c) => c,
                Err(_) => continue,
            };

            let agent_state: AgentState = match serde_json::from_str(&content) {
                Ok(s) => s,
                Err(e) => {
                    log::warn!("Failed to parse agent state file {:?}: {}", path, e);
                    continue;
                }
            };

            current_states.insert(agent_state.agent_id.clone(), agent_state);
        }

        // Compare with previous states and emit events for changes
        let mut projects = self.active_projects.write().await;
        let project_state = match projects.get_mut(project_path) {
            Some(state) => state,
            None => return, // Project was removed while we were reading
        };

        for (agent_id, agent_state) in &current_states {
            let prev_state = project_state.previous_states.get(agent_id);
            let changed = prev_state.map_or(true, |s| *s != agent_state.state);

            if changed {
                if let Some(session_id) = agent_state.session_id() {
                    // Map MCP state to session status string
                    let status = match agent_state.state {
                        AgentStatusState::Idle => "Idle",
                        AgentStatusState::Working => "Working",
                        AgentStatusState::NeedsInput => "NeedsInput",
                        AgentStatusState::Finished => "Done",
                        AgentStatusState::Error => "Error",
                    };

                    let payload = SessionStatusPayload {
                        session_id,
                        project_path: project_path.to_string(),
                        status: status.to_string(),
                        message: agent_state.message.clone(),
                        needs_input_prompt: agent_state.needs_input_prompt.clone(),
                    };

                    log::info!(
                        "Emitting status for session {} project='{}' status={}",
                        session_id,
                        project_path,
                        status
                    );

                    if let Err(e) = app.emit("session-status-changed", &payload) {
                        log::warn!("Failed to emit session-status-changed event: {}", e);
                    }
                }
            }
        }

        // Update previous states for this project
        project_state.previous_states = current_states
            .into_iter()
            .map(|(k, v)| (k, v.state))
            .collect();
    }
}

impl Default for McpStatusMonitor {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_project_hash() {
        // Test that hash is 12 hex characters
        let hash = McpStatusMonitor::generate_project_hash("/Users/test/project");
        assert_eq!(hash.len(), 12);
        assert!(hash.chars().all(|c| c.is_ascii_hexdigit()));
    }

    #[test]
    fn test_hash_consistency() {
        // Same path should produce same hash
        let hash1 = McpStatusMonitor::generate_project_hash("/Users/test/project");
        let hash2 = McpStatusMonitor::generate_project_hash("/Users/test/project");
        assert_eq!(hash1, hash2);
    }

    #[test]
    fn test_different_paths_different_hashes() {
        let hash1 = McpStatusMonitor::generate_project_hash("/Users/test/project1");
        let hash2 = McpStatusMonitor::generate_project_hash("/Users/test/project2");
        assert_ne!(hash1, hash2);
    }
}
