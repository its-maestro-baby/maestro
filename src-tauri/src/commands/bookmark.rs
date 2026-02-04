//! Tauri commands for security-scoped bookmark management

use crate::core::bookmark_manager::{BookmarkEntry, BookmarkManager};
use tauri::State;

/// Create a security-scoped bookmark for a path (called after file dialog selection)
#[tauri::command]
pub async fn create_bookmark(
    manager: State<'_, BookmarkManager>,
    path: String,
) -> Result<BookmarkEntry, String> {
    manager.create_bookmark(&path)
}

/// Start accessing a bookmarked path (call before file operations)
#[tauri::command]
pub async fn start_bookmark_access(
    manager: State<'_, BookmarkManager>,
    path: String,
) -> Result<String, String> {
    if let Some(entry) = manager.get_bookmark(&path) {
        let resolved = manager.start_access(&entry)?;
        Ok(resolved.to_string_lossy().to_string())
    } else {
        Err(format!("No bookmark found for path: {}", path))
    }
}

/// Stop accessing a bookmarked path (call when done with file operations)
#[tauri::command]
pub async fn stop_bookmark_access(
    manager: State<'_, BookmarkManager>,
    path: String,
) -> Result<(), String> {
    manager.stop_access(&path);
    Ok(())
}

/// Check if path needs a bookmark (external/network drive)
#[tauri::command]
pub fn needs_bookmark(path: String) -> bool {
    BookmarkManager::is_external_or_network(&path)
}

/// Check if we have a valid bookmark for a path
#[tauri::command]
pub fn has_bookmark(manager: State<'_, BookmarkManager>, path: String) -> bool {
    manager.has_bookmark(&path)
}

/// Get all stored bookmarks (for persistence to tauri-store)
#[tauri::command]
pub fn get_all_bookmarks(manager: State<'_, BookmarkManager>) -> Vec<BookmarkEntry> {
    manager.get_all_bookmarks()
}

/// Load bookmarks from storage (call on app startup)
#[tauri::command]
pub fn load_bookmarks(
    manager: State<'_, BookmarkManager>,
    entries: Vec<BookmarkEntry>,
) -> Result<(), String> {
    manager.load_from_store(entries);
    Ok(())
}

/// Remove a bookmark
#[tauri::command]
pub fn remove_bookmark(
    manager: State<'_, BookmarkManager>,
    path: String,
) -> Result<(), String> {
    manager.remove_bookmark(&path);
    Ok(())
}
