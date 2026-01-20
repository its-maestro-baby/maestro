import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';
/**
 * Manages log capture and retrieval for managed processes.
 * Keeps a rolling buffer of recent log entries per session.
 * Also persists logs to disk for the Swift app to read.
 */
export class LogManager {
    logs = new Map(); // sessionId -> logs
    maxEntriesPerSession;
    logsDir;
    constructor(maxEntriesPerSession = 1000) {
        this.maxEntriesPerSession = maxEntriesPerSession;
        // Set up logs directory in Application Support
        this.logsDir = path.join(os.homedir(), 'Library', 'Application Support', 'Claude Maestro', 'logs');
        this.ensureLogsDirExists();
    }
    /**
     * Ensure the logs directory exists.
     */
    ensureLogsDirExists() {
        try {
            if (!fs.existsSync(this.logsDir)) {
                fs.mkdirSync(this.logsDir, { recursive: true });
            }
        }
        catch (error) {
            console.error('Failed to create logs directory:', error);
        }
    }
    /**
     * Get the log file path for a session.
     */
    getLogFilePath(sessionId) {
        return path.join(this.logsDir, `session-${sessionId}.log`);
    }
    /**
     * Append log entry to the file for a session.
     */
    appendToFile(sessionId, stream, data) {
        try {
            const filePath = this.getLogFilePath(sessionId);
            const timestamp = new Date().toISOString();
            const prefix = stream === 'stderr' ? '[ERR]' : '[OUT]';
            const logLine = `${timestamp} ${prefix} ${data}\n`;
            fs.appendFileSync(filePath, logLine);
        }
        catch (error) {
            // Silently ignore file write errors to not disrupt the main process
        }
    }
    /**
     * Append a log entry for a session.
     */
    append(sessionId, stream, data) {
        if (!this.logs.has(sessionId)) {
            this.logs.set(sessionId, []);
        }
        const sessionLogs = this.logs.get(sessionId);
        // Split by newlines and create entries for each line
        const lines = data.split('\n').filter(line => line.length > 0);
        for (const line of lines) {
            sessionLogs.push({
                timestamp: new Date(),
                stream,
                data: line,
            });
            // Also persist to file for Swift app to read
            this.appendToFile(sessionId, stream, line);
        }
        // Trim to max entries (in-memory only, file keeps growing)
        while (sessionLogs.length > this.maxEntriesPerSession) {
            sessionLogs.shift();
        }
    }
    /**
     * Get recent log entries for a session.
     */
    getLogs(sessionId, options = {}) {
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
    getLogsAsString(sessionId, options = {}) {
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
    clear(sessionId) {
        this.logs.delete(sessionId);
        // Also delete the log file
        try {
            const filePath = this.getLogFilePath(sessionId);
            if (fs.existsSync(filePath)) {
                fs.unlinkSync(filePath);
            }
        }
        catch (error) {
            // Silently ignore file delete errors
        }
    }
    /**
     * Clear all logs.
     */
    clearAll() {
        // Clear all log files
        try {
            const files = fs.readdirSync(this.logsDir);
            for (const file of files) {
                if (file.startsWith('session-') && file.endsWith('.log')) {
                    fs.unlinkSync(path.join(this.logsDir, file));
                }
            }
        }
        catch (error) {
            // Silently ignore file delete errors
        }
        this.logs.clear();
    }
    /**
     * Get log count for a session.
     */
    getLogCount(sessionId) {
        return this.logs.get(sessionId)?.length || 0;
    }
}
//# sourceMappingURL=LogManager.js.map