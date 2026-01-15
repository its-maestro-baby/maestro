import type { LogEntry } from '../types.js';

/**
 * Manages log capture and retrieval for managed processes.
 * Keeps a rolling buffer of recent log entries per session.
 */
export class LogManager {
  private logs: Map<number, LogEntry[]> = new Map(); // sessionId -> logs
  private readonly maxEntriesPerSession: number;

  constructor(maxEntriesPerSession = 1000) {
    this.maxEntriesPerSession = maxEntriesPerSession;
  }

  /**
   * Append a log entry for a session.
   */
  append(sessionId: number, stream: 'stdout' | 'stderr', data: string): void {
    if (!this.logs.has(sessionId)) {
      this.logs.set(sessionId, []);
    }

    const sessionLogs = this.logs.get(sessionId)!;

    // Split by newlines and create entries for each line
    const lines = data.split('\n').filter(line => line.length > 0);
    for (const line of lines) {
      sessionLogs.push({
        timestamp: new Date(),
        stream,
        data: line,
      });
    }

    // Trim to max entries
    while (sessionLogs.length > this.maxEntriesPerSession) {
      sessionLogs.shift();
    }
  }

  /**
   * Get recent log entries for a session.
   */
  getLogs(
    sessionId: number,
    options: {
      lines?: number;
      stream?: 'stdout' | 'stderr' | 'all';
    } = {}
  ): LogEntry[] {
    const { lines = 50, stream = 'all' } = options;
    const sessionLogs = this.logs.get(sessionId) || [];

    let filtered = sessionLogs;
    if (stream !== 'all') {
      filtered = sessionLogs.filter(entry => entry.stream === stream);
    }

    // Return last N entries
    return filtered.slice(-lines);
  }

  /**
   * Get logs as formatted string.
   */
  getLogsAsString(
    sessionId: number,
    options: {
      lines?: number;
      stream?: 'stdout' | 'stderr' | 'all';
      includeTimestamps?: boolean;
    } = {}
  ): string {
    const { includeTimestamps = false, ...restOptions } = options;
    const entries = this.getLogs(sessionId, restOptions);

    return entries
      .map(entry => {
        if (includeTimestamps) {
          const time = entry.timestamp.toISOString();
          const prefix = entry.stream === 'stderr' ? '[ERR]' : '[OUT]';
          return `${time} ${prefix} ${entry.data}`;
        }
        return entry.data;
      })
      .join('\n');
  }

  /**
   * Clear logs for a session.
   */
  clear(sessionId: number): void {
    this.logs.delete(sessionId);
  }

  /**
   * Clear all logs.
   */
  clearAll(): void {
    this.logs.clear();
  }

  /**
   * Get log count for a session.
   */
  getLogCount(sessionId: number): number {
    return this.logs.get(sessionId)?.length || 0;
  }
}
