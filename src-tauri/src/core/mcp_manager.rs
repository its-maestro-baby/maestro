//! MCP (Model Context Protocol) server discovery and session state management.
//!
//! This module parses `.mcp.json` files at project roots to discover configured
//! MCP servers, and tracks which servers are enabled per session.

use dashmap::DashMap;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;

/// Configuration for an MCP server as read from `.mcp.json`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "lowercase")]
pub enum McpServerType {
    /// Standard I/O based MCP server (command + args + env).
    Stdio {
        command: String,
        #[serde(default)]
        args: Vec<String>,
        #[serde(default)]
        env: HashMap<String, String>,
    },
    /// HTTP-based MCP server.
    Http { url: String },
}

/// A named MCP server configuration.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpServerConfig {
    /// Server name (the key from mcpServers object).
    pub name: String,
    /// Server type and connection details.
    #[serde(flatten)]
    pub server_type: McpServerType,
}

/// Raw structure of `.mcp.json` file.
#[derive(Debug, Deserialize)]
struct McpJsonFile {
    #[serde(rename = "mcpServers", default)]
    mcp_servers: HashMap<String, McpServerEntry>,
}

/// A single entry in the mcpServers object.
#[derive(Debug, Deserialize)]
struct McpServerEntry {
    #[serde(rename = "type")]
    server_type: String,
    #[serde(default)]
    command: Option<String>,
    #[serde(default)]
    args: Option<Vec<String>>,
    #[serde(default)]
    env: Option<HashMap<String, String>>,
    #[serde(default)]
    url: Option<String>,
}

/// Session-specific key for enabled servers lookup.
type SessionKey = (String, u32); // (project_path, session_id)

/// Manages MCP server discovery and per-session enabled state.
///
/// Thread-safe via `DashMap` — can be accessed from multiple async tasks.
pub struct McpManager {
    /// Cached MCP servers per project path (canonicalized).
    project_servers: DashMap<String, Vec<McpServerConfig>>,
    /// Enabled server names per (project_path, session_id).
    session_enabled: DashMap<SessionKey, Vec<String>>,
}

impl McpManager {
    /// Creates a new MCP manager with empty caches.
    pub fn new() -> Self {
        Self {
            project_servers: DashMap::new(),
            session_enabled: DashMap::new(),
        }
    }

    /// Parses the `.mcp.json` file at the given project path.
    ///
    /// Returns an empty vec if the file doesn't exist or can't be parsed.
    fn parse_mcp_config(project_path: &str) -> Vec<McpServerConfig> {
        let mcp_path = Path::new(project_path).join(".mcp.json");

        let content = match std::fs::read_to_string(&mcp_path) {
            Ok(c) => c,
            Err(_) => return Vec::new(),
        };

        let parsed: McpJsonFile = match serde_json::from_str(&content) {
            Ok(p) => p,
            Err(e) => {
                log::warn!("Failed to parse .mcp.json at {:?}: {}", mcp_path, e);
                return Vec::new();
            }
        };

        parsed
            .mcp_servers
            .into_iter()
            .filter_map(|(name, entry)| {
                let server_type = match entry.server_type.as_str() {
                    "stdio" => {
                        let command = entry.command?;
                        McpServerType::Stdio {
                            command,
                            args: entry.args.unwrap_or_default(),
                            env: entry.env.unwrap_or_default(),
                        }
                    }
                    "http" => {
                        let url = entry.url?;
                        McpServerType::Http { url }
                    }
                    other => {
                        log::warn!("Unknown MCP server type '{}' for server '{}'", other, name);
                        return None;
                    }
                };

                Some(McpServerConfig { name, server_type })
            })
            .collect()
    }

    /// Gets the MCP servers for a project, parsing `.mcp.json` if not cached.
    ///
    /// The project_path should be canonicalized for consistent caching.
    pub fn get_project_servers(&self, project_path: &str) -> Vec<McpServerConfig> {
        // Return cached if available
        if let Some(servers) = self.project_servers.get(project_path) {
            return servers.clone();
        }

        // Parse and cache
        let servers = Self::parse_mcp_config(project_path);
        self.project_servers.insert(project_path.to_string(), servers.clone());
        servers
    }

    /// Refreshes the cached servers for a project by re-parsing `.mcp.json`.
    pub fn refresh_project_servers(&self, project_path: &str) -> Vec<McpServerConfig> {
        let servers = Self::parse_mcp_config(project_path);
        self.project_servers.insert(project_path.to_string(), servers.clone());
        servers
    }

    /// Gets the enabled server names for a session.
    ///
    /// If not explicitly set, returns all available servers as enabled by default.
    pub fn get_session_enabled(&self, project_path: &str, session_id: u32) -> Vec<String> {
        let key = (project_path.to_string(), session_id);

        if let Some(enabled) = self.session_enabled.get(&key) {
            return enabled.clone();
        }

        // Default: all servers enabled
        self.get_project_servers(project_path)
            .into_iter()
            .map(|s| s.name)
            .collect()
    }

    /// Sets the enabled server names for a session.
    pub fn set_session_enabled(&self, project_path: &str, session_id: u32, enabled: Vec<String>) {
        let key = (project_path.to_string(), session_id);
        self.session_enabled.insert(key, enabled);
    }

    /// Removes session-enabled state when a session is closed.
    pub fn remove_session(&self, project_path: &str, session_id: u32) {
        let key = (project_path.to_string(), session_id);
        self.session_enabled.remove(&key);
    }

    /// Counts enabled MCP servers for a session.
    pub fn get_enabled_count(&self, project_path: &str, session_id: u32) -> usize {
        self.get_session_enabled(project_path, session_id).len()
    }
}

impl Default for McpManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_empty_project() {
        let manager = McpManager::new();
        let servers = manager.get_project_servers("/nonexistent/path");
        assert!(servers.is_empty());
    }
}
