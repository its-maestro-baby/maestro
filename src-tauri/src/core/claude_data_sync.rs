//! Background task that syncs Claude Code data from `~/.claude/` into SQLite.
//!
//! Runs on a configurable interval (default 30s) and performs incremental
//! sync of history, project sessions, memory, and plans.

use std::io::{BufRead, Seek, SeekFrom};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use directories::BaseDirs;
use serde::Deserialize;
use serde_json::Value;
use tokio::time;

use super::database::Database;

/// Background sync task for Claude Code data.
pub struct ClaudeDataSyncTask;

impl ClaudeDataSyncTask {
    /// Start the background sync loop on a tokio task.
    pub fn start(db: Arc<Database>, interval: Duration) {
        tauri::async_runtime::spawn(async move {
            // Initial delay to let the app finish startup
            time::sleep(Duration::from_secs(5)).await;

            log::info!("Claude data sync task started (interval: {:?})", interval);

            // Run initial sync immediately
            if let Err(e) = Self::sync_all(&db).await {
                log::warn!("Initial Claude data sync failed: {}", e);
            }

            let mut ticker = time::interval(interval);
            ticker.tick().await; // consume first tick (already synced above)

            loop {
                ticker.tick().await;
                if let Err(e) = Self::sync_all(&db).await {
                    log::warn!("Claude data sync failed: {}", e);
                }
            }
        });
    }

    /// Trigger a manual sync (called from IPC command).
    pub async fn sync_all(db: &Database) -> Result<(), String> {
        let claude_dir = Self::claude_dir().ok_or("Could not determine ~/.claude/ path")?;

        if !claude_dir.exists() {
            return Ok(());
        }

        // Run each sync step independently — don't let one failure stop others
        if let Err(e) = Self::sync_history(db, &claude_dir) {
            log::warn!("History sync error: {}", e);
        }

        if let Err(e) = Self::sync_plans(db, &claude_dir) {
            log::warn!("Plans sync error: {}", e);
        }

        // Project-specific syncs run for all known project dirs
        if let Err(e) = Self::sync_project_data(db, &claude_dir) {
            log::warn!("Project data sync error: {}", e);
        }

        Ok(())
    }

    fn claude_dir() -> Option<PathBuf> {
        BaseDirs::new().map(|dirs| dirs.home_dir().join(".claude"))
    }

    // -----------------------------------------------------------------------
    // History sync (incremental by byte offset)
    // -----------------------------------------------------------------------

    fn sync_history(db: &Database, claude_dir: &PathBuf) -> Result<(), String> {
        let history_path = claude_dir.join("history.jsonl");
        if !history_path.exists() {
            return Ok(());
        }

        let file_len = std::fs::metadata(&history_path)
            .map(|m| m.len())
            .unwrap_or(0);

        // Get the last sync offset
        let last_offset: u64 = db
            .get_sync_state("history_jsonl_offset")?
            .and_then(|v| v.parse().ok())
            .unwrap_or(0);

        // If file is smaller than last offset, it was likely rotated
        let seek_offset = if file_len < last_offset { 0 } else { last_offset };

        let file = std::fs::File::open(&history_path)
            .map_err(|e| format!("Failed to open history.jsonl: {e}"))?;
        let mut reader = std::io::BufReader::new(file);
        reader.seek(SeekFrom::Start(seek_offset))
            .map_err(|e| format!("Failed to seek: {e}"))?;

        let mut entries = Vec::new();
        let mut line = String::new();

        loop {
            line.clear();
            let bytes_read = reader.read_line(&mut line)
                .map_err(|e| format!("Failed to read line: {e}"))?;
            if bytes_read == 0 {
                break;
            }

            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            #[derive(Deserialize)]
            struct HistoryLine {
                #[serde(default)]
                display: String,
                #[serde(default)]
                timestamp: f64,
                project: Option<String>,
                #[serde(default, rename = "sessionId")]
                session_id: Option<String>,
            }

            if let Ok(entry) = serde_json::from_str::<HistoryLine>(trimmed) {
                if !entry.display.is_empty() && entry.timestamp > 0.0 {
                    entries.push((
                        entry.display,
                        entry.timestamp,
                        entry.project,
                        entry.session_id,
                    ));
                }
            }
        }

        // Get current position
        let new_offset = reader.stream_position().unwrap_or(file_len);

        if !entries.is_empty() {
            let count = db.upsert_history_entries(&entries)?;
            if count > 0 {
                log::debug!("Synced {} new history entries", count);
            }
        }

        db.set_sync_state("history_jsonl_offset", &new_offset.to_string())?;
        Ok(())
    }

    // -----------------------------------------------------------------------
    // Plans sync
    // -----------------------------------------------------------------------

    fn sync_plans(db: &Database, claude_dir: &PathBuf) -> Result<(), String> {
        let plans_dir = claude_dir.join("plans");
        if !plans_dir.exists() {
            // Clean up any stale plans in DB
            db.delete_plans_not_in(&[])?;
            return Ok(());
        }

        let entries = std::fs::read_dir(&plans_dir)
            .map_err(|e| format!("Failed to read plans dir: {e}"))?;

        let mut filenames = Vec::new();
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_file() {
                let filename = entry.file_name().to_string_lossy().to_string();
                let metadata = std::fs::metadata(&path).ok();
                let size_bytes = metadata.as_ref().map(|m| m.len() as i64).unwrap_or(0);
                let modified_at = metadata
                    .and_then(|m| m.modified().ok())
                    .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                    .map(|d| d.as_secs_f64());

                db.upsert_plan(&filename, size_bytes, modified_at)?;
                filenames.push(filename);
            }
        }

        // Remove plans that no longer exist on disk
        db.delete_plans_not_in(&filenames)?;

        Ok(())
    }

    // -----------------------------------------------------------------------
    // Project data sync (sessions, memory)
    // -----------------------------------------------------------------------

    fn sync_project_data(db: &Database, claude_dir: &PathBuf) -> Result<(), String> {
        let projects_dir = claude_dir.join("projects");
        if !projects_dir.exists() {
            return Ok(());
        }

        let entries = std::fs::read_dir(&projects_dir)
            .map_err(|e| format!("Failed to read projects dir: {e}"))?;

        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_dir() {
                continue;
            }

            let dir_name = entry.file_name().to_string_lossy().to_string();
            // The dir_name is like "-Users-jc-Documents-project", convert back
            let project_path = if dir_name.starts_with('-') {
                format!("/{}", &dir_name[1..].replace('-', "/"))
            } else {
                dir_name.replace('-', "/")
            };

            // Sync memory
            let memory_path = path.join("memory").join("MEMORY.md");
            if memory_path.exists() {
                if let Ok(content) = std::fs::read_to_string(&memory_path) {
                    let _ = db.upsert_project_memory(&project_path, &content);
                }
            }

            // Sync sessions in this project directory
            if let Err(e) = Self::sync_project_sessions(db, &path, &project_path) {
                log::debug!("Failed to sync sessions for {}: {}", project_path, e);
            }
        }

        Ok(())
    }

    fn sync_project_sessions(
        db: &Database,
        project_dir: &PathBuf,
        project_path: &str,
    ) -> Result<(), String> {
        let entries = std::fs::read_dir(project_dir)
            .map_err(|e| format!("Failed to read project dir: {e}"))?;

        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().to_string();

            // Skip non-session entries
            if name.starts_with('.') || name == "memory" {
                continue;
            }

            let (session_uuid, transcript_path) = if path.is_dir() {
                // Session directory — look for transcript .jsonl files inside
                let transcript = Self::find_transcript_in_dir(&path);
                (name.clone(), transcript)
            } else if path.is_file() && name.ends_with(".jsonl") {
                let uuid = name.trim_end_matches(".jsonl").to_string();
                (uuid, Some(path.clone()))
            } else {
                continue;
            };

            // Parse transcript for enrichment data
            let enrichment = transcript_path
                .as_ref()
                .and_then(|tp| Self::parse_transcript_enrichment(tp));

            let (first_message, model, total_input, total_output, files_count, tools, subagent_count) =
                enrichment.unwrap_or_default();

            let tools_json = if tools.is_empty() {
                None
            } else {
                Some(serde_json::to_string(&tools).unwrap_or_default())
            };

            // Count subagents from dir if available
            let subagent_count = if path.is_dir() {
                let subagent_dir = path.join("subagents");
                if subagent_dir.exists() {
                    std::fs::read_dir(&subagent_dir)
                        .map(|e| e.count() as i64)
                        .unwrap_or(subagent_count)
                } else {
                    subagent_count
                }
            } else {
                subagent_count
            };

            db.upsert_claude_session(
                &session_uuid,
                project_path,
                first_message.as_deref(),
                model.as_deref(),
                transcript_path
                    .as_ref()
                    .map(|p| p.to_string_lossy().to_string())
                    .as_deref(),
                total_input,
                total_output,
                files_count,
                tools_json.as_deref(),
                subagent_count,
                None, // history_display linked separately
                None, // history_timestamp linked separately
            )?;
        }

        Ok(())
    }

    fn find_transcript_in_dir(dir: &PathBuf) -> Option<PathBuf> {
        std::fs::read_dir(dir).ok()?.flatten().find_map(|e| {
            let p = e.path();
            if p.is_file() && p.extension().map_or(false, |ext| ext == "jsonl") {
                Some(p)
            } else {
                None
            }
        })
    }

    /// Parse a transcript file and extract enrichment data.
    /// Returns (first_message, model, total_input_tokens, total_output_tokens, files_count, tools_used, subagent_count).
    fn parse_transcript_enrichment(
        path: &PathBuf,
    ) -> Option<(Option<String>, Option<String>, i64, i64, i64, Vec<String>, i64)> {
        let file = std::fs::File::open(path).ok()?;
        let reader = std::io::BufReader::new(file);

        let mut first_message: Option<String> = None;
        let mut model: Option<String> = None;
        let mut total_input_tokens: i64 = 0;
        let mut total_output_tokens: i64 = 0;
        let mut files_modified = std::collections::HashSet::new();
        let mut tools_used = std::collections::HashSet::new();
        let mut subagent_count: i64 = 0;

        // Limit how many lines we parse to avoid blocking on large transcripts
        let max_lines = 500;
        let mut line_count = 0;

        for line in reader.lines() {
            if line_count >= max_lines {
                break;
            }
            line_count += 1;

            let line = match line {
                Ok(l) => l,
                Err(_) => continue,
            };

            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            let obj: Value = match serde_json::from_str(trimmed) {
                Ok(v) => v,
                Err(_) => continue,
            };

            let msg_type = obj.get("type").and_then(|v| v.as_str()).unwrap_or("");

            match msg_type {
                "user" => {
                    if first_message.is_none() {
                        // Extract first user message text
                        let text = obj
                            .get("message")
                            .and_then(|m| m.get("content"))
                            .and_then(|c| c.as_array())
                            .map(|blocks| {
                                blocks
                                    .iter()
                                    .filter_map(|b| {
                                        if b.get("type").and_then(|t| t.as_str()) == Some("text") {
                                            b.get("text").and_then(|t| t.as_str())
                                        } else {
                                            None
                                        }
                                    })
                                    .collect::<Vec<_>>()
                                    .join("\n")
                            });

                        if let Some(text) = text {
                            if !text.is_empty() {
                                // Truncate to ~200 chars for preview (char-safe)
                                let preview = if text.chars().count() > 200 {
                                    let end: String = text.chars().take(200).collect();
                                    format!("{}...", end)
                                } else {
                                    text
                                };
                                first_message = Some(preview);
                            }
                        }
                    }
                }
                "assistant" => {
                    let message = obj.get("message");

                    // Capture model
                    if model.is_none() {
                        model = message
                            .and_then(|m| m.get("model"))
                            .and_then(|v| v.as_str())
                            .map(|s| s.to_string());
                    }

                    // Accumulate token usage
                    if let Some(usage) = message.and_then(|m| m.get("usage")) {
                        total_input_tokens += usage
                            .get("input_tokens")
                            .and_then(|v| v.as_i64())
                            .unwrap_or(0);
                        total_output_tokens += usage
                            .get("output_tokens")
                            .and_then(|v| v.as_i64())
                            .unwrap_or(0);
                    }

                    // Collect tool usage and file modifications
                    if let Some(blocks) = message
                        .and_then(|m| m.get("content"))
                        .and_then(|c| c.as_array())
                    {
                        for block in blocks {
                            if block.get("type").and_then(|t| t.as_str()) != Some("tool_use") {
                                continue;
                            }

                            let tool_name = block
                                .get("name")
                                .and_then(|v| v.as_str())
                                .unwrap_or("");

                            if !tool_name.is_empty() {
                                tools_used.insert(tool_name.to_string());
                            }

                            let input = block.get("input");

                            match tool_name {
                                "Edit" | "Write" => {
                                    if let Some(fp) = input
                                        .and_then(|i| i.get("file_path"))
                                        .and_then(|v| v.as_str())
                                    {
                                        files_modified.insert(fp.to_string());
                                    }
                                }
                                "Task" => {
                                    subagent_count += 1;
                                }
                                _ => {}
                            }
                        }
                    }
                }
                _ => {}
            }
        }

        Some((
            first_message,
            model,
            total_input_tokens,
            total_output_tokens,
            files_modified.len() as i64,
            tools_used.into_iter().collect(),
            subagent_count,
        ))
    }
}
