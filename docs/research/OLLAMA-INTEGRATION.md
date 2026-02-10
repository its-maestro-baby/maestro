# Ollama Integration & API Documentation

## Overview
Ollama is a lightweight, extensible framework for running large language models (LLMs) locally. It serves as the primary engine for "OpenLLAMA" and other open-source models in Maestro.

## Local API (Port 11434)
Ollama runs a background daemon that exposes a REST API.

### 1. List Local Models (Dynamic Discovery)
Used to populate the model selection dropdown in Maestro.
- **Endpoint:** `GET /api/tags`
- **Response:**
  ```json
  {
    "models": [
      { "name": "deepseek-r1:70b", "size": 42000000000, ... },
      { "name": "llama3:latest", ... }
    ]
  }
  ```

### 2. Chat Interaction
Used for programmatic control (if not using the CLI).
- **Endpoint:** `POST /api/chat`
- **Capability:** Supports streaming and tool-calling.

## "Premium" Configuration
To get a high-performance ("Premium") experience with local models:
1. **Flash Attention:** Ensure `OLLAMA_FLASH_ATTENTION=1` is set in the environment.
2. **GPU Orchestration:** Ollama automatically detects CUDA (Nvidia) or Metal (Apple Silicon). For "Premium" speed, the model layers should fit entirely in VRAM.
3. **Quantization:** Use `K_M` or `Q4_0` quantizations for the best balance of speed and logic.
4. **Modelfiles:** We can create custom `.maestro` modelfiles that define a "System Prompt" specifically for coding tasks, which Ollama will use to keep the model focused.

## CLI Usage
Maestro uses the CLI for the interactive terminal experience:
- **Command:** `ollama run <model_name>`
- **Behavior:** Starts an interactive REPL session within the PTY.
