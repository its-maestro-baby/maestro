import { create } from "zustand";
import type { SessionConfig } from "@/stores/useSessionStore";

export interface ResumeRequest {
  sessionConfig: SessionConfig;
}

interface ResumeRequestState {
  pendingResume: ResumeRequest | null;
  requestResume: (session: SessionConfig) => void;
  consumeResume: () => ResumeRequest | null;
}

export const useResumeRequestStore = create<ResumeRequestState>((set, get) => ({
  pendingResume: null,

  requestResume: (session: SessionConfig) => {
    set({ pendingResume: { sessionConfig: session } });
  },

  consumeResume: () => {
    const current = get().pendingResume;
    if (current) {
      set({ pendingResume: null });
    }
    return current;
  },
}));
