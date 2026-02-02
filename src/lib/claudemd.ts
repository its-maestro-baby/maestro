import { invoke } from "@tauri-apps/api/core";

/** Status of CLAUDE.md file at project root */
export interface ClaudeMdStatus {
  exists: boolean;
  path: string;
  content: string | null;
}

/** Check if CLAUDE.md exists at project root */
export async function checkClaudeMd(projectPath: string): Promise<ClaudeMdStatus> {
  return invoke<ClaudeMdStatus>("check_claude_md", { projectPath });
}

/** Read CLAUDE.md content */
export async function readClaudeMd(projectPath: string): Promise<string> {
  return invoke<string>("read_claude_md", { projectPath });
}

/** Write CLAUDE.md content (creates or updates) */
export async function writeClaudeMd(projectPath: string, content: string): Promise<void> {
  return invoke<void>("write_claude_md", { projectPath, content });
}
