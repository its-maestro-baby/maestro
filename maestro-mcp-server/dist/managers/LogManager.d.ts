import type { LogEntry } from '../types.js';
/**
 * Manages log capture and retrieval for managed processes.
 * Keeps a rolling buffer of recent log entries per session.
 */
export declare class LogManager {
    private logs;
    private readonly maxEntriesPerSession;
    constructor(maxEntriesPerSession?: number);
    /**
     * Append a log entry for a session.
     */
    append(sessionId: number, stream: 'stdout' | 'stderr', data: string): void;
    /**
     * Get recent log entries for a session.
     */
    getLogs(sessionId: number, options?: {
        lines?: number;
        stream?: 'stdout' | 'stderr' | 'all';
    }): LogEntry[];
    /**
     * Get logs as formatted string.
     */
    getLogsAsString(sessionId: number, options?: {
        lines?: number;
        stream?: 'stdout' | 'stderr' | 'all';
        includeTimestamps?: boolean;
    }): string;
    /**
     * Clear logs for a session.
     */
    clear(sessionId: number): void;
    /**
     * Clear all logs.
     */
    clearAll(): void;
    /**
     * Get log count for a session.
     */
    getLogCount(sessionId: number): number;
}
//# sourceMappingURL=LogManager.d.ts.map