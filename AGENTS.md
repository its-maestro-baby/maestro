# AGENTS.md - Maestro Coding Guidelines

## Build Commands

### Frontend
```bash
npm install                    # Install dependencies
npm run dev                    # Start Vite dev server
npm run build                  # TypeScript compile + Vite build
npm run preview                # Preview production build
```

### Backend
```bash
cargo build --release -p maestro-mcp-server    # Build MCP server
npm run tauri dev                               # Run Tauri app in dev mode
npm run tauri build                             # Build production app
```

### Full Build
```bash
npm install
cargo build --release -p maestro-mcp-server
npm run tauri dev
```

## Test Commands

### Run All Tests
```bash
npm run test                   # Run all Vitest tests once
npm run test:watch             # Run tests in watch mode
```

### Run Single Test
```bash
npx vitest run src/components/path/Component.test.tsx
npx vitest run -t "test name pattern"
npx vitest run --reporter=verbose  # Verbose output
```

### Run Tests Related to Changed Files
```bash
npx vitest run --changed
```

## Lint & Format

### TypeScript/React (Biome)
```bash
npx @biomejs/biome check .                    # Check linting
npx @biomejs/biome format .                   # Check formatting
npx @biomejs/biome check --write .            # Fix linting and format
npx @biomejs/biome check --write src/file.tsx # Fix specific file
```

### Rust (Clippy & rustfmt)
```bash
cargo clippy                    # Run Clippy linter
cargo clippy --fix              # Auto-fix Clippy warnings
cargo fmt                       # Format all Rust code
cargo fmt -- src-tauri/src/file.rs  # Format specific file
```

## Code Style Guidelines

### TypeScript/React
- **Formatter**: Biome with 100 char line width, 2-space indent
- **Quotes**: Double quotes for strings
- **Trailing commas**: Always use trailing commas
- **Imports**: Group by 1) React/libraries 2) Tauri APIs 3) Local components 4) Relative paths
- **Types**: Use explicit types for function parameters and return types
- **Components**: PascalCase, one component per file, use functional components with hooks
- **Variables/Functions**: camelCase
- **Constants**: UPPER_SNAKE_CASE
- **Interfaces**: Prefix with component name (e.g., `ButtonProps`)

### Rust
- **Naming**: snake_case for functions/variables, PascalCase for types/structs
- **Error handling**: Use `thiserror` for custom errors, `?` operator for propagation
- **Async**: Mark Tauri commands with `#[tauri::command]` and use `async fn`
- **Comments**: Document public APIs with `///`, use `//` for internal notes
- **Organization**: One module per file, export in `mod.rs`
- **Serialization**: Use `serde` with `#[derive(Serialize, Deserialize)]`

### Testing
- **Frontend**: Vitest + React Testing Library + happy-dom
- **Test naming**: Descriptive, e.g., "renders button with correct text"
- **Mocking**: Use `vi.fn()` and `vi.mock()` for Tauri APIs
- **Backend**: Tests embedded in source files with `#[cfg(test)]`
- **Coverage**: Tests in `__tests__/` folders or `*.test.tsx` files

## Project Structure

```
src/                           # React/TypeScript frontend
├── components/               # UI components
│   ├── Component.tsx
│   └── __tests__/Component.test.tsx
├── hooks/                    # Custom React hooks
├── lib/                      # Utility libraries
├── stores/                   # Zustand state stores
└── types/                    # TypeScript definitions

src-tauri/                    # Tauri Rust backend
└── src/
    ├── commands/            # Tauri command handlers (IPC)
    └── core/                # Core business logic
```

## Naming Conventions

- **React components**: `MyComponent.tsx` with `export function MyComponent()`
- **Hooks**: `useHookName.ts` with `export function useHookName()`
- **Stores**: `useStoreName.ts` with `interface StoreNameState`
- **Rust modules**: `snake_case.rs` with `pub fn command_name()`
- **Tests**: `ComponentName.test.tsx` alongside source or in `__tests__/`

## Error Handling

### TypeScript
```typescript
try {
  const result = await invoke("command", { arg });
} catch (error) {
  console.error("Contextual message:", error);
  setError(error instanceof Error ? error.message : "Unknown error");
}
```

### Rust
```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum MyError {
    #[error("Context: {0}")]
    Io(#[from] std::io::Error),
}

#[tauri::command]
pub async fn command() -> Result<T, String> {
  risky_op().await.map_err(|e| e.to_string())
}
```

## Common Patterns

### Tauri Command Invocation
```typescript
import { invoke } from "@tauri-apps/api/core";
const result = await invoke<ReturnType>("command_name", { arg: value });
```

### Zustand Store
```typescript
import { create } from "zustand";

interface StoreState {
  value: string;
  setValue: (v: string) => void;
}

export const useStore = create<StoreState>((set) => ({
  value: "",
  setValue: (v) => set({ value: v }),
}));
```

## Pre-commit Checklist

1. Run tests: `npm run test`
2. Check formatting: `npx @biomejs/biome check .`
3. Fix issues: `npx @biomejs/biome check --write .`
4. For Rust changes: `cargo clippy && cargo fmt`

## CI/Build Notes

- Frontend builds to `dist/` directory
- MCP server binary bundled at build time
- Tauri bundles frontend + Rust backend into native apps
- Node 18+ required, Rust 1.78+ required
