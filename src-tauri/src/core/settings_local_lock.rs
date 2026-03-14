//! Shared lock and atomic write utilities for `.claude/settings.local.json`.
//!
//! Multiple modules (plugin_config_writer, hook_config_writer) perform
//! read-modify-write on the same settings.local.json file. Without
//! synchronization, concurrent writes corrupt the file (shorter write
//! leaves trailing bytes from a longer concurrent write).
//!
//! This module provides:
//! - Per-directory tokio mutex to serialize all settings.local.json operations
//! - Atomic write via temp file + rename (prevents partial writes)
//! - JSON validation before writing (defense in depth)

use std::path::{Path, PathBuf};
use std::sync::{Arc, LazyLock};

use dashmap::DashMap;
use tokio::sync::Mutex;

/// Per-directory lock map to serialize concurrent settings.local.json
/// read-modify-write operations.
static DIR_LOCKS: LazyLock<DashMap<PathBuf, Arc<Mutex<()>>>> = LazyLock::new(DashMap::new);

/// Acquire a per-directory lock for atomic settings.local.json operations.
pub fn dir_lock(dir: &Path) -> Arc<Mutex<()>> {
    DIR_LOCKS
        .entry(dir.to_path_buf())
        .or_insert_with(|| Arc::new(Mutex::new(())))
        .value()
        .clone()
}

/// Write content to a file atomically: write to a temp file in the same
/// directory, then rename. This prevents partial writes from corrupting
/// the file if the process is interrupted.
pub async fn atomic_write(path: &Path, content: &str) -> Result<(), String> {
    let parent = path.parent().ok_or("No parent directory")?;
    let temp_path = parent.join(format!(
        ".settings.local.json.tmp.{}",
        std::process::id()
    ));

    tokio::fs::write(&temp_path, content)
        .await
        .map_err(|e| format!("Failed to write temp file: {}", e))?;

    tokio::fs::rename(&temp_path, path)
        .await
        .map_err(|e| {
            // Clean up temp file on rename failure
            let _ = std::fs::remove_file(&temp_path);
            format!("Failed to rename temp file: {}", e)
        })?;

    Ok(())
}

/// Validate that content is valid JSON. Returns Ok(()) if valid,
/// Err with details if invalid. Call this before writing to catch
/// serialization bugs early.
pub fn validate_json(content: &str) -> Result<(), String> {
    serde_json::from_str::<serde_json::Value>(content)
        .map(|_| ())
        .map_err(|e| format!("JSON validation failed: {}", e))
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[tokio::test]
    async fn test_atomic_write_creates_file() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.json");

        atomic_write(&path, r#"{"key": "value"}"#).await.unwrap();

        let content = std::fs::read_to_string(&path).unwrap();
        assert_eq!(content, r#"{"key": "value"}"#);
    }

    #[tokio::test]
    async fn test_atomic_write_no_temp_file_left() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.json");

        atomic_write(&path, r#"{"key": "value"}"#).await.unwrap();

        let entries: Vec<_> = std::fs::read_dir(dir.path())
            .unwrap()
            .filter_map(|e| e.ok())
            .collect();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].file_name(), "test.json");
    }

    #[tokio::test]
    async fn test_atomic_write_overwrites_existing() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.json");

        // Write a longer file first
        std::fs::write(&path, r#"{"long": "content that is very long indeed"}"#).unwrap();

        // Overwrite with shorter content
        atomic_write(&path, r#"{"short": 1}"#).await.unwrap();

        let content = std::fs::read_to_string(&path).unwrap();
        assert_eq!(content, r#"{"short": 1}"#);
    }

    #[tokio::test]
    async fn test_concurrent_atomic_writes_produce_valid_json() {
        let dir = tempdir().unwrap();
        let path = dir.path().join("test.json");
        let dir_path = dir.path().to_path_buf();

        // Write initial file
        std::fs::write(&path, r#"{"initial": true}"#).unwrap();

        // Launch 10 concurrent locked write operations
        let mut handles = vec![];
        for i in 0..10u32 {
            let dp = dir_path.clone();
            handles.push(tokio::spawn(async move {
                let lock = dir_lock(&dp);
                let _guard = lock.lock().await;

                let file_path = dp.join("test.json");
                let content = format!(r#"{{"writer": {}}}"#, i);
                atomic_write(&file_path, &content).await.unwrap();
            }));
        }

        for h in handles {
            h.await.unwrap();
        }

        // Final file must be valid JSON
        let final_content = std::fs::read_to_string(&path).unwrap();
        let parsed: serde_json::Value = serde_json::from_str(&final_content)
            .expect("final file should be valid JSON");
        assert!(parsed.get("writer").is_some());
    }

    #[test]
    fn test_validate_json_valid() {
        assert!(validate_json(r#"{"key": "value"}"#).is_ok());
        assert!(validate_json(r#"{"nested": {"a": [1, 2, 3]}}"#).is_ok());
    }

    #[test]
    fn test_validate_json_invalid() {
        assert!(validate_json(r#"{"unclosed": true"#).is_err());
        assert!(validate_json(r#"not json at all"#).is_err());
        // Simulates the exact corruption pattern: valid JSON + trailing garbage
        assert!(validate_json(
            r#"{"key": "value"}extra garbage here"#
        ).is_err());
    }

    #[test]
    fn test_dir_lock_same_dir_returns_same_lock() {
        let dir = tempdir().unwrap();
        let lock1 = dir_lock(dir.path());
        let lock2 = dir_lock(dir.path());
        assert!(Arc::ptr_eq(&lock1, &lock2));
    }

    #[test]
    fn test_dir_lock_different_dirs_return_different_locks() {
        let dir1 = tempdir().unwrap();
        let dir2 = tempdir().unwrap();
        let lock1 = dir_lock(dir1.path());
        let lock2 = dir_lock(dir2.path());
        assert!(!Arc::ptr_eq(&lock1, &lock2));
    }
}
