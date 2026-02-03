//! Tauri commands for font detection.

use crate::core::{detect_available_fonts, is_font_available, AvailableFont};

/// Returns a list of available terminal-suitable fonts on the system.
///
/// Fonts are returned in priority order: Nerd Fonts first, then standard
/// monospace fonts. Each font includes metadata about whether it's a
/// Nerd Font variant.
#[tauri::command]
pub fn get_available_fonts() -> Vec<AvailableFont> {
    detect_available_fonts()
}

/// Checks if a specific font family is available on the system.
///
/// This is useful for checking if a user's preferred font is installed
/// before attempting to use it.
#[tauri::command]
pub fn check_font_available(family: String) -> bool {
    is_font_available(&family)
}
