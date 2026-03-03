/**
 * Zustand store for Claude Code session data browsing.
 * Now backed by SQLite via the database IPC commands.
 */

import { create } from "zustand";
import {
  dbGetHistory,
  dbGetProjectMemory,
  dbGetPlans,
  dbTriggerSync,
  type DbHistoryEntry,
  type DbPlanRow,
} from "@/lib/database";

// Re-export types for backward compatibility
export type { DbHistoryEntry as HistoryEntry } from "@/lib/database";
export type { DbPlanRow as PlanSummary } from "@/lib/database";

interface ClaudeDataState {
  history: DbHistoryEntry[];
  memory: string | null;
  plans: DbPlanRow[];
  isLoading: boolean;
  error: string | null;

  fetchHistory: (projectPath?: string, limit?: number) => Promise<void>;
  fetchMemory: (projectPath: string) => Promise<void>;
  fetchPlans: () => Promise<void>;
  fetchAll: (projectPath: string) => Promise<void>;
  triggerSync: () => Promise<void>;
}

export const useClaudeDataStore = create<ClaudeDataState>()((set) => ({
  history: [],
  memory: null,
  plans: [],
  isLoading: false,
  error: null,

  fetchHistory: async (projectPath?: string, limit = 50) => {
    try {
      const result = await dbGetHistory(projectPath, limit, 0);
      set({ history: result.items });
    } catch (err) {
      console.error("Failed to fetch Claude history:", err);
      set({ error: String(err) });
    }
  },

  fetchMemory: async (projectPath: string) => {
    try {
      const memory = await dbGetProjectMemory(projectPath);
      set({ memory });
    } catch (err) {
      console.error("Failed to fetch Claude memory:", err);
      set({ error: String(err) });
    }
  },

  fetchPlans: async () => {
    try {
      const result = await dbGetPlans(50, 0);
      set({ plans: result.items });
    } catch (err) {
      console.error("Failed to fetch Claude plans:", err);
      set({ error: String(err) });
    }
  },

  fetchAll: async (projectPath: string) => {
    set({ isLoading: true, error: null });
    try {
      const [historyResult, memory, plansResult] = await Promise.all([
        dbGetHistory(projectPath, 50, 0),
        dbGetProjectMemory(projectPath),
        dbGetPlans(50, 0),
      ]);
      set({
        history: historyResult.items,
        memory,
        plans: plansResult.items,
        isLoading: false,
      });
    } catch (err) {
      console.error("Failed to fetch Claude data:", err);
      set({ isLoading: false, error: String(err) });
    }
  },

  triggerSync: async () => {
    try {
      await dbTriggerSync();
    } catch (err) {
      console.error("Failed to trigger sync:", err);
    }
  },
}));
