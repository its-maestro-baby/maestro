/**
 * Represents a system process listening on a TCP port.
 */
export interface SystemProcess {
    pid: number;
    command: string;
    port: number;
    address: string;
    user: string;
    managed: boolean;
}
/**
 * Scans for all TCP listeners on the system using lsof.
 * Provides real-time visibility into what's using ports.
 */
export declare class PortScanner {
    private pollInterval;
    private cachedProcesses;
    private onChange;
    private managedPids;
    /**
     * Create a new PortScanner.
     * @param onChange Callback invoked when the list of processes changes
     */
    constructor(onChange?: (processes: SystemProcess[]) => void);
    /**
     * Start periodic scanning for TCP listeners.
     * @param intervalMs How often to scan (default: 3000ms)
     */
    start(intervalMs?: number): void;
    /**
     * Stop periodic scanning.
     */
    stop(): void;
    /**
     * Register a PID as managed by MCP.
     */
    registerManagedPid(pid: number): void;
    /**
     * Unregister a PID from MCP management.
     */
    unregisterManagedPid(pid: number): void;
    /**
     * Get the current cached list of processes.
     */
    getCachedProcesses(): SystemProcess[];
    /**
     * Scan for all TCP listeners using lsof.
     * Returns structured data about each listening process.
     */
    scan(): Promise<SystemProcess[]>;
    /**
     * Parse lsof output into structured SystemProcess objects.
     *
     * Example lsof output:
     * COMMAND   PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
     * node    42992 jackwakem   22u  IPv4 0x...      0t0  TCP *:3000 (LISTEN)
     * python3 19102 jackwakem    3u  IPv4 0x...      0t0  TCP 127.0.0.1:8000 (LISTEN)
     */
    private parseLsofOutput;
    /**
     * Parse a single lsof output line.
     */
    private parseLsofLine;
    /**
     * Check if the process list has changed from cached.
     */
    private hasChanged;
    /**
     * Filter processes to only show relevant ports.
     * @param includeAllPorts If true, return all ports. Otherwise filter to dev range + common services.
     */
    filterRelevantPorts(processes: SystemProcess[], includeAllPorts?: boolean): SystemProcess[];
}
//# sourceMappingURL=PortScanner.d.ts.map