//! Writes session-specific plugin configuration for Claude CLI.
//!
//! This module handles registering installed plugins in the session's
//! `.claude/settings.local.json` file so Claude CLI can discover them.
//! Plugins installed via the marketplace are registered here to enable
//! all their components (skills, commands, agents, hooks, MCP servers).

use std::path::Path;

use serde_json::{json, Value};

/// Plugin entry format for settings.local.json.
#[derive(Debug, Clone)]
struct PluginEntry {
    path: String,
    enabled: bool,
}

/// Merges new plugin entries with an existing settings.local.json file.
///
/// This function preserves user-defined settings while updating the plugins array.
fn merge_with_existing(
    settings_path: &Path,
    new_plugins: Vec<PluginEntry>,
) -> Result<Value, String> {
    let mut config: Value = if settings_path.exists() {
        let content = std::fs::read_to_string(settings_path)
            .map_err(|e| format!("Failed to read existing settings.local.json: {}", e))?;

        serde_json::from_str(&content)
            .map_err(|e| format!("Failed to parse existing settings.local.json: {}", e))?
    } else {
        json!({})
    };

    // Build the plugins array
    let plugins_array: Vec<Value> = new_plugins
        .into_iter()
        .map(|p| {
            json!({
                "path": p.path,
                "enabled": p.enabled
            })
        })
        .collect();

    // Set the plugins array (replaces any existing plugins array)
    config["plugins"] = json!(plugins_array);

    Ok(config)
}

/// Writes enabled plugins to the session's .claude/settings.local.json.
///
/// This function:
/// 1. Creates the .claude directory if it doesn't exist
/// 2. Builds plugin entries from the provided paths
/// 3. Merges with any existing settings.local.json (preserving other settings)
/// 4. Writes the final config
///
/// # Arguments
///
/// * `working_dir` - Directory where `.claude/settings.local.json` will be written
/// * `enabled_plugin_paths` - Paths to enabled plugin directories
pub async fn write_session_plugin_config(
    working_dir: &Path,
    enabled_plugin_paths: &[String],
) -> Result<(), String> {
    // Create .claude directory if needed
    let claude_dir = working_dir.join(".claude");
    if !claude_dir.exists() {
        tokio::fs::create_dir_all(&claude_dir)
            .await
            .map_err(|e| format!("Failed to create .claude directory: {}", e))?;
    }

    // Build plugin entries
    let plugins: Vec<PluginEntry> = enabled_plugin_paths
        .iter()
        .map(|path| PluginEntry {
            path: path.clone(),
            enabled: true,
        })
        .collect();

    // Merge with existing settings
    let settings_path = claude_dir.join("settings.local.json");
    let final_config = merge_with_existing(&settings_path, plugins)?;

    // Write the file
    let content = serde_json::to_string_pretty(&final_config)
        .map_err(|e| format!("Failed to serialize plugin config: {}", e))?;

    tokio::fs::write(&settings_path, content)
        .await
        .map_err(|e| format!("Failed to write settings.local.json: {}", e))?;

    log::debug!(
        "Wrote session plugin config to {:?} with {} plugins",
        settings_path,
        enabled_plugin_paths.len()
    );

    Ok(())
}

/// Removes the plugins array from the session's .claude/settings.local.json.
///
/// This should be called when a session is killed to clean up the plugin config.
/// The function preserves other settings in the file.
///
/// # Arguments
///
/// * `working_dir` - Directory containing the `.claude/settings.local.json` file
pub async fn remove_session_plugin_config(working_dir: &Path) -> Result<(), String> {
    let settings_path = working_dir.join(".claude/settings.local.json");
    if !settings_path.exists() {
        return Ok(());
    }

    let content = tokio::fs::read_to_string(&settings_path)
        .await
        .map_err(|e| format!("Failed to read settings.local.json: {}", e))?;

    let mut config: Value = serde_json::from_str(&content)
        .map_err(|e| format!("Failed to parse settings.local.json: {}", e))?;

    // Remove the plugins array
    if let Some(obj) = config.as_object_mut() {
        if obj.remove("plugins").is_some() {
            log::debug!("Removed plugins config from {:?}", settings_path);
        }
    }

    // If the config is now empty, delete the file
    if config.as_object().map(|o| o.is_empty()).unwrap_or(false) {
        tokio::fs::remove_file(&settings_path)
            .await
            .map_err(|e| format!("Failed to delete empty settings.local.json: {}", e))?;
        log::debug!("Deleted empty settings.local.json at {:?}", settings_path);
    } else {
        // Otherwise, write the updated config
        let output = serde_json::to_string_pretty(&config)
            .map_err(|e| format!("Failed to serialize config: {}", e))?;

        tokio::fs::write(&settings_path, output)
            .await
            .map_err(|e| format!("Failed to write settings.local.json: {}", e))?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_write_session_plugin_config_creates_directory_and_file() {
        let dir = tempdir().unwrap();
        let plugins = vec![
            "/Users/test/.claude/plugins/plugin-a".to_string(),
            "/Users/test/.claude/plugins/plugin-b".to_string(),
        ];

        let result = write_session_plugin_config(dir.path(), &plugins).await;
        assert!(result.is_ok());

        let settings_path = dir.path().join(".claude/settings.local.json");
        assert!(settings_path.exists());

        let content = std::fs::read_to_string(&settings_path).unwrap();
        let config: Value = serde_json::from_str(&content).unwrap();

        let plugins_array = config["plugins"].as_array().unwrap();
        assert_eq!(plugins_array.len(), 2);
        assert_eq!(
            plugins_array[0]["path"],
            "/Users/test/.claude/plugins/plugin-a"
        );
        assert_eq!(plugins_array[0]["enabled"], true);
    }

    #[tokio::test]
    async fn test_write_preserves_other_settings() {
        let dir = tempdir().unwrap();
        let claude_dir = dir.path().join(".claude");
        std::fs::create_dir_all(&claude_dir).unwrap();

        // Write existing settings
        let existing = json!({
            "someOtherSetting": "value",
            "plugins": [
                {"path": "/old/plugin", "enabled": false}
            ]
        });
        std::fs::write(
            claude_dir.join("settings.local.json"),
            serde_json::to_string(&existing).unwrap(),
        )
        .unwrap();

        // Write new plugins
        let plugins = vec!["/new/plugin".to_string()];
        write_session_plugin_config(dir.path(), &plugins)
            .await
            .unwrap();

        let content = std::fs::read_to_string(claude_dir.join("settings.local.json")).unwrap();
        let config: Value = serde_json::from_str(&content).unwrap();

        // Other settings should be preserved
        assert_eq!(config["someOtherSetting"], "value");

        // Plugins should be replaced
        let plugins_array = config["plugins"].as_array().unwrap();
        assert_eq!(plugins_array.len(), 1);
        assert_eq!(plugins_array[0]["path"], "/new/plugin");
    }

    #[tokio::test]
    async fn test_remove_session_plugin_config() {
        let dir = tempdir().unwrap();
        let claude_dir = dir.path().join(".claude");
        std::fs::create_dir_all(&claude_dir).unwrap();

        // Write settings with plugins and other settings
        let existing = json!({
            "someOtherSetting": "value",
            "plugins": [
                {"path": "/test/plugin", "enabled": true}
            ]
        });
        std::fs::write(
            claude_dir.join("settings.local.json"),
            serde_json::to_string(&existing).unwrap(),
        )
        .unwrap();

        remove_session_plugin_config(dir.path()).await.unwrap();

        let content = std::fs::read_to_string(claude_dir.join("settings.local.json")).unwrap();
        let config: Value = serde_json::from_str(&content).unwrap();

        // Plugins should be removed
        assert!(config.get("plugins").is_none());
        // Other settings should be preserved
        assert_eq!(config["someOtherSetting"], "value");
    }

    #[tokio::test]
    async fn test_remove_deletes_empty_file() {
        let dir = tempdir().unwrap();
        let claude_dir = dir.path().join(".claude");
        std::fs::create_dir_all(&claude_dir).unwrap();

        // Write settings with only plugins
        let existing = json!({
            "plugins": [
                {"path": "/test/plugin", "enabled": true}
            ]
        });
        std::fs::write(
            claude_dir.join("settings.local.json"),
            serde_json::to_string(&existing).unwrap(),
        )
        .unwrap();

        remove_session_plugin_config(dir.path()).await.unwrap();

        // File should be deleted since it would be empty
        assert!(!claude_dir.join("settings.local.json").exists());
    }

    #[tokio::test]
    async fn test_remove_handles_missing_file() {
        let dir = tempdir().unwrap();
        // No .claude directory or settings file exists
        let result = remove_session_plugin_config(dir.path()).await;
        assert!(result.is_ok());
    }
}
