import "@testing-library/jest-dom/vitest";
import { vi } from "vitest";

// Stub localStorage with a proper in-memory implementation for happy-dom compatibility
const localStorageMap = new Map<string, string>();
vi.stubGlobal("localStorage", {
  getItem: (key: string) => localStorageMap.get(key) ?? null,
  setItem: (key: string, value: string) => localStorageMap.set(key, String(value)),
  removeItem: (key: string) => localStorageMap.delete(key),
  clear: () => localStorageMap.clear(),
  get length() { return localStorageMap.size; },
  key: (index: number) => [...localStorageMap.keys()][index] ?? null,
});

// Mock @tauri-apps/api/core
vi.mock("@tauri-apps/api/core", () => ({
  invoke: vi.fn(),
}));

// Mock @tauri-apps/plugin-dialog
vi.mock("@tauri-apps/plugin-dialog", () => ({
  open: vi.fn(),
}));

// Mock tauri-plugin-macos-permissions-api
vi.mock("tauri-plugin-macos-permissions-api", () => ({
  checkFullDiskAccessPermission: vi.fn().mockResolvedValue(true),
  requestFullDiskAccessPermission: vi.fn().mockResolvedValue(undefined),
}));
