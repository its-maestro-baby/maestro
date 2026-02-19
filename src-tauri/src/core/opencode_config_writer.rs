//! Writes session-specific `opencode.json` configuration for the OpenCode CLI.
//!
//! OpenCode uses a different MCP config format than Claude:
//! - **Filename:** `opencode.json` (not `.mcp.json`)
//! - **Root key:** `mcp` with server names directly (not `mcpServers`)
//! - **Server type:** `"local"` (not `"stdio"`)
//! - **Command:** Array of strings `["binary", "arg1", ...]` (not separate command/args)
//! - **Environment:** `environment` key (not `env`)
//!
//! This module merges Maestro's session-specific server configuration into the
//! `mcp` section while preserving all other OpenCode config (agents, models, etc.).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock};

use dashmap::DashMap;
use serde_json::{json, Value};
use tokio::sync::Mutex;

use super::mcp_config_writer::find_maestro_mcp_path;
use super::mcp_manager::{McpServerConfig, McpServerType};
use crate::commands::mcp::McpCustomServer;

/// Per-directory lock map to serialize concurrent opencode.json read-modify-write operations.
static DIR_LOCKS: LazyLock<DashMap<PathBuf, Arc<Mutex<()>>>> = LazyLock::new(DashMap::new);

/// Acquire a per-directory lock for atomic opencode.json operations.
fn dir_lock(dir: &Path) -> Arc<Mutex<()>> {
    DIR_LOCKS
        .entry(dir.to_path_buf())
        .or_insert_with(|| Arc::new(Mutex::new(())))
        .value()
        .clone()
}

/// Write content to a file atomically: write to a temp file in the same directory, then rename.
async fn atomic_write(path: &Path, content: &str) -> Result<(), String> {
    let parent = path.parent().ok_or("No parent directory")?;
    let temp_path = parent.join(format!(
        ".opencode.json.tmp.{}",
        std::process::id()
    ));

    tokio::fs::write(&temp_path, content)
        .await
        .map_err(|e| format!("Failed to write temp file: {}", e))?;

    tokio::fs::rename(&temp_path, path)
        .await
        .map_err(|e| {
            let _ = std::fs::remove_file(&temp_path);
            format!("Failed to rename temp file: {}", e)
        })?;

    Ok(())
}

/// Converts an McpServerConfig to the OpenCode JSON format.
///
/// OpenCode format differences:
/// - `"local"` type instead of `"stdio"`
/// - `command` is an array: `["binary", "arg1", "arg2"]`
/// - `environment` instead of `env`
/// - HTTP servers use `"remote"` type with `url`
fn server_config_to_opencode_json(config: &McpServerConfig) -> Value {
    match &config.server_type {
        McpServerType::Stdio { command, args, env } => {
            // OpenCode command is a single array: [command, ...args]
            let mut cmd_array: Vec<String> = vec![command.clone()];
            cmd_array.extend(args.iter().cloned());

            let mut obj = json!({
                "type": "local",
                "command": cmd_array,
            });
            if !env.is_empty() {
                obj["environment"] = json!(env);
            }
            obj
        }
        McpServerType::Http { url } => {
            json!({
                "type": "remote",
                "url": url
            })
        }
    }
}

/// Converts a custom MCP server to the OpenCode JSON format.
fn custom_server_to_opencode_json(server: &McpCustomServer) -> Value {
    // OpenCode command is a single array: [command, ...args]
    let mut cmd_array: Vec<String> = vec![server.command.clone()];
    cmd_array.extend(server.args.iter().cloned());

    let mut obj = json!({
        "type": "local",
        "command": cmd_array,
    });
    if !server.env.is_empty() {
        obj["environment"] = json!(server.env);
    }
    obj
}

/// Checks if a server entry is a Maestro-managed entry that should be removed on update.
fn should_remove_server(name: &str) -> bool {
    name == "maestro-status"
        || name.starts_with("maestro-status-")
        || (name.starts_with("maestro-") && name != "maestro-status")
        || name == "maestro"
}

/// Writes a session-specific `opencode.json` to the working directory.
///
/// This function:
/// 1. Creates the Maestro MCP server entry with HTTP-based status reporting
/// 2. Adds enabled discovered servers from the project's .mcp.json
/// 3. Adds enabled custom servers (user-defined, global)
/// 4. Merges with any existing `opencode.json` (preserving all non-MCP config)
/// 5. Writes the final config to the working directory
pub async fn write_opencode_mcp_config(
    working_dir: &Path,
    session_id: u32,
    status_url: &str,
    instance_id: &str,
    enabled_servers: &[McpServerConfig],
    custom_servers: &[McpCustomServer],
) -> Result<(), String> {
    let mut mcp_servers: HashMap<String, Value> = HashMap::new();

    // Add Maestro MCP server with HTTP-based status reporting.
    if let Some(mcp_path) = find_maestro_mcp_path() {
        log::info!(
            "Found maestro-mcp-server at {:?}, adding maestro-status entry for OpenCode session {}",
            mcp_path,
            session_id
        );

        mcp_servers.insert(
            "maestro-status".to_string(),
            json!({
                "type": "local",
                "command": [mcp_path.to_string_lossy()],
                "environment": {
                    "MAESTRO_SESSION_ID": session_id.to_string(),
                    "MAESTRO_STATUS_URL": status_url,
                    "MAESTRO_INSTANCE_ID": instance_id
                }
            }),
        );
    } else {
        log::warn!(
            "maestro-mcp-server binary not found, maestro_status tool will not be available for OpenCode"
        );
    }

    // Add enabled discovered servers
    for server in enabled_servers {
        mcp_servers.insert(server.name.clone(), server_config_to_opencode_json(server));
    }

    // Add enabled custom servers
    for server in custom_servers {
        mcp_servers.insert(server.name.clone(), custom_server_to_opencode_json(server));
    }

    // Acquire per-directory lock
    let lock = dir_lock(working_dir);
    let _guard = lock.lock().await;

    let config_path = working_dir.join("opencode.json");

    // Read existing opencode.json or start fresh
    let mut config: Value = if config_path.exists() {
        let content = tokio::fs::read_to_string(&config_path)
            .await
            .map_err(|e| format!("Failed to read existing opencode.json: {}", e))?;

        serde_json::from_str(&content)
            .map_err(|e| format!("Failed to parse existing opencode.json: {}", e))?
    } else {
        json!({})
    };

    // Ensure mcp section exists (servers go directly under "mcp", not "mcp.servers")
    if config.get("mcp").is_none() {
        config["mcp"] = json!({});
    }

    // Remove existing Maestro entries from mcp
    if let Some(mcp) = config["mcp"].as_object_mut() {
        let to_remove: Vec<String> = mcp
            .keys()
            .filter(|k| should_remove_server(k))
            .cloned()
            .collect();

        for key in to_remove {
            mcp.remove(&key);
            log::debug!("Removed existing '{}' from opencode.json", key);
        }
    }

    // Add new servers directly under mcp
    if let Some(mcp) = config["mcp"].as_object_mut() {
        for (name, server_config) in mcp_servers {
            log::info!("Adding server '{}' to opencode.json for session {}", name, session_id);
            mcp.insert(name, server_config);
        }
    }

    // Write atomically
    let content = serde_json::to_string_pretty(&config)
        .map_err(|e| format!("Failed to serialize OpenCode config: {}", e))?;

    atomic_write(&config_path, &content).await?;

    log::debug!(
        "Wrote OpenCode session {} MCP config to {:?}",
        session_id,
        config_path
    );

    Ok(())
}

/// Removes Maestro server entries from `opencode.json`.
///
/// Preserves all other configuration. The function is idempotent.
pub async fn remove_opencode_mcp_config(working_dir: &Path, session_id: u32) -> Result<(), String> {
    let config_path = working_dir.join("opencode.json");
    if !config_path.exists() {
        return Ok(());
    }

    let lock = dir_lock(working_dir);
    let _guard = lock.lock().await;

    let content = tokio::fs::read_to_string(&config_path)
        .await
        .map_err(|e| format!("Failed to read opencode.json: {}", e))?;

    let mut config: Value = serde_json::from_str(&content)
        .map_err(|e| format!("Failed to parse opencode.json: {}", e))?;

    if let Some(mcp) = config.get_mut("mcp").and_then(|s| s.as_object_mut()) {
        let to_remove: Vec<String> = mcp
            .keys()
            .filter(|k| should_remove_server(k))
            .cloned()
            .collect();

        for key in &to_remove {
            if mcp.remove(key).is_some() {
                log::debug!(
                    "Removed '{}' from opencode.json (session {})",
                    key,
                    session_id
                );
            }
        }
    }

    let output = serde_json::to_string_pretty(&config)
        .map_err(|e| format!("Failed to serialize config: {}", e))?;

    atomic_write(&config_path, &output).await?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_write_opencode_mcp_config_creates_file() {
        let dir = tempdir().unwrap();
        let result = write_opencode_mcp_config(
            dir.path(),
            1,
            "http://127.0.0.1:9900/status",
            "test-instance-id",
            &[],
            &[],
        )
        .await;

        assert!(result.is_ok());
        assert!(dir.path().join("opencode.json").exists());

        let content = std::fs::read_to_string(dir.path().join("opencode.json")).unwrap();
        let config: Value = serde_json::from_str(&content).unwrap();

        // Verify servers go directly under mcp (not mcp.servers)
        assert!(config["mcp"].is_object());
        assert!(config["mcp"]["servers"].is_null(), "should not have mcp.servers nesting");
    }

    #[tokio::test]
    async fn test_write_preserves_existing_config() {
        let dir = tempdir().unwrap();
        let config_path = dir.path().join("opencode.json");

        // Write an existing config with non-MCP settings and a user server
        let existing = json!({
            "provider": "anthropic",
            "model": "claude-sonnet-4-20250514",
            "mcp": {
                "user-server": {
                    "type": "local",
                    "command": ["/usr/bin/user-server"]
                }
            }
        });
        std::fs::write(&config_path, serde_json::to_string_pretty(&existing).unwrap()).unwrap();

        let result = write_opencode_mcp_config(
            dir.path(),
            1,
            "http://127.0.0.1:9900/status",
            "test-instance-id",
            &[],
            &[],
        )
        .await;

        assert!(result.is_ok());

        let content = std::fs::read_to_string(&config_path).unwrap();
        let config: Value = serde_json::from_str(&content).unwrap();

        // Non-MCP config should be preserved
        assert_eq!(config["provider"], "anthropic");
        assert_eq!(config["model"], "claude-sonnet-4-20250514");

        // User server should be preserved directly under mcp
        assert!(config["mcp"]["user-server"].is_object());
    }

    #[tokio::test]
    async fn test_maestro_entry_uses_correct_format() {
        let dir = tempdir().unwrap();
        let result = write_opencode_mcp_config(
            dir.path(),
            1,
            "http://127.0.0.1:9900/status",
            "test-instance-id",
            &[],
            &[],
        )
        .await;

        assert!(result.is_ok());

        let content = std::fs::read_to_string(dir.path().join("opencode.json")).unwrap();
        let config: Value = serde_json::from_str(&content).unwrap();

        // maestro-status should be directly under mcp
        let entry = &config["mcp"]["maestro-status"];
        if !entry.is_null() {
            // command should be an array
            assert!(entry["command"].is_array(), "command should be an array");
            // type should be "local"
            assert_eq!(entry["type"], "local");
            // env key should be "environment" not "env"
            assert!(entry["env"].is_null(), "should use 'environment' not 'env'");
            assert!(entry["environment"].is_object());
        }
    }

    #[tokio::test]
    async fn test_server_config_command_array() {
        use super::super::mcp_manager::{McpServerSource, McpServerType};

        let config = McpServerConfig {
            name: "test".to_string(),
            server_type: McpServerType::Stdio {
                command: "npx".to_string(),
                args: vec!["-y".to_string(), "@some/server".to_string()],
                env: {
                    let mut env = HashMap::new();
                    env.insert("KEY".to_string(), "value".to_string());
                    env
                },
            },
            source: McpServerSource::Project,
        };

        let json = server_config_to_opencode_json(&config);
        assert_eq!(json["type"], "local");
        // command should be ["npx", "-y", "@some/server"]
        let cmd = json["command"].as_array().unwrap();
        assert_eq!(cmd.len(), 3);
        assert_eq!(cmd[0], "npx");
        assert_eq!(cmd[1], "-y");
        assert_eq!(cmd[2], "@some/server");
        // env key should be "environment"
        assert_eq!(json["environment"]["KEY"], "value");
        assert!(json["env"].is_null());
    }

    #[tokio::test]
    async fn test_remove_opencode_mcp_config() {
        let dir = tempdir().unwrap();
        let config_path = dir.path().join("opencode.json");

        // Write a config with maestro-status and user server directly under mcp
        let existing = json!({
            "provider": "anthropic",
            "mcp": {
                "maestro-status": {
                    "type": "local",
                    "command": ["/usr/bin/maestro-mcp-server"],
                    "environment": { "MAESTRO_SESSION_ID": "1" }
                },
                "user-server": {
                    "type": "local",
                    "command": ["/usr/bin/user-server"]
                }
            }
        });
        std::fs::write(&config_path, serde_json::to_string_pretty(&existing).unwrap()).unwrap();

        let result = remove_opencode_mcp_config(dir.path(), 1).await;
        assert!(result.is_ok());

        let content = std::fs::read_to_string(&config_path).unwrap();
        let config: Value = serde_json::from_str(&content).unwrap();

        // maestro-status should be removed
        assert!(config["mcp"]["maestro-status"].is_null());
        // user server should be preserved
        assert!(config["mcp"]["user-server"].is_object());
        // non-MCP config should be preserved
        assert_eq!(config["provider"], "anthropic");
    }

    #[tokio::test]
    async fn test_remove_noop_when_no_file() {
        let dir = tempdir().unwrap();
        let result = remove_opencode_mcp_config(dir.path(), 1).await;
        assert!(result.is_ok());
    }

    #[test]
    fn test_should_remove_server() {
        assert!(should_remove_server("maestro-status"));
        assert!(should_remove_server("maestro-status-1"));
        assert!(should_remove_server("maestro-2"));
        assert!(should_remove_server("maestro"));
        assert!(!should_remove_server("user-server"));
        assert!(!should_remove_server("some-other-server"));
    }
}
