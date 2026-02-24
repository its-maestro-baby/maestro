use std::sync::Arc;
use tauri::State;

use crate::core::hook_config_writer;
use crate::core::StatusServer;

#[tauri::command]
pub async fn write_session_hooks_config(
    server: State<'_, Arc<StatusServer>>,
    working_dir: String,
    session_id: u32,
) -> Result<(), String> {
    let path = std::path::Path::new(&working_dir);
    hook_config_writer::write_session_hooks_config(
        path,
        session_id,
        server.port(),
        server.instance_id(),
    )
    .await
}

#[tauri::command]
pub async fn remove_session_hooks_config(working_dir: String) -> Result<(), String> {
    let path = std::path::Path::new(&working_dir);
    hook_config_writer::remove_session_hooks_config(path).await
}
