# Plan: Ollama-First Integration

## Goal
Streamline Maestro to focus on **Ollama** as the primary local LLM provider, replacing generic OpenLLM/LiteLLM modes with a polished, dynamic Ollama experience.

## Tasks

### 1. Codebase Cleanup
- [ ] Remove `OpenLLM` and `LiteLLM` from `AiMode` enum in `src-tauri/src/core/session_manager.rs`.
- [ ] Remove `OpenLLM` and `LiteLLM` from `AiMode` type in `src/lib/terminal.ts`.
- [ ] Remove related CLI configurations from `AI_CLI_CONFIG`.
- [ ] Clean up `CliSettingsModal.tsx` and `Sidebar.tsx` to remove redundant tabs and status counters.

### 2. Dynamic Model Discovery
- [ ] Create `src/lib/ollama.ts` to handle API communication with the local Ollama daemon.
- [ ] Implement `fetchInstalledModels()` to query `http://localhost:11434/api/tags`.

### 3. UI Refactor (Pre-Launch)
- [ ] Modify `PreLaunchCard.tsx`:
    - Replace the text input for "Model" with a searchable dropdown.
    - Populate dropdown with results from `fetchInstalledModels()`.
    - Default to the last used model or the largest available model.

### 4. Verification
- [ ] Verify `ollama run <selected_model>` launches correctly.
- [ ] Ensure the Maestro MCP server still connects correctly to provide status updates if the model supports tool-calling.
