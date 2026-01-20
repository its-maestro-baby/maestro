import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

/**
 * Represents a system process listening on a TCP port.
 */
export interface SystemProcess {
  pid: number;
  command: string;
  port: number;
  address: string;   // '*', 'localhost', '127.0.0.1', etc.
  user: string;
  managed: boolean;  // true if started by MCP
}

/**
 * Scans for all TCP listeners on the system using lsof.
 * Provides real-time visibility into what's using ports.
 */
export class PortScanner {
  private pollInterval: NodeJS.Timeout | null = null;
  private cachedProcesses: SystemProcess[] = [];
  private onChange: ((processes: SystemProcess[]) => void) | null = null;
  private managedPids: Set<number> = new Set();

  /**
   * Create a new PortScanner.
   * @param onChange Callback invoked when the list of processes changes
   */
  constructor(onChange?: (processes: SystemProcess[]) => void) {
    this.onChange = onChange || null;
  }

  /**
   * Start periodic scanning for TCP listeners.
   * @param intervalMs How often to scan (default: 3000ms)
   */
  start(intervalMs: number = 3000): void {
    if (this.pollInterval) {
      return; // Already running
    }

    // Do an immediate scan
    this.scan().catch(() => {});

    // Then poll at interval
    this.pollInterval = setInterval(() => {
      this.scan().catch(() => {});
    }, intervalMs);
  }

  /**
   * Stop periodic scanning.
   */
  stop(): void {
    if (this.pollInterval) {
      clearInterval(this.pollInterval);
      this.pollInterval = null;
    }
  }

  /**
   * Register a PID as managed by MCP.
   */
  registerManagedPid(pid: number): void {
    this.managedPids.add(pid);
  }

  /**
   * Unregister a PID from MCP management.
   */
  unregisterManagedPid(pid: number): void {
    this.managedPids.delete(pid);
  }

  /**
   * Get the current cached list of processes.
   */
  getCachedProcesses(): SystemProcess[] {
    return [...this.cachedProcesses];
  }

  /**
   * Scan for all TCP listeners using lsof.
   * Returns structured data about each listening process.
   */
  async scan(): Promise<SystemProcess[]> {
    try {
      // lsof -iTCP -sTCP:LISTEN -P -n
      // -iTCP: only TCP connections
      // -sTCP:LISTEN: only listening sockets
      // -P: show port numbers instead of service names
      // -n: don't resolve hostnames
      const { stdout } = await execAsync('lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null', {
        timeout: 5000,
      });

      const processes = this.parseLsofOutput(stdout);

      // Check if anything changed
      const changed = this.hasChanged(processes);

      // Update cache
      this.cachedProcesses = processes;

      // Notify if changed
      if (changed && this.onChange) {
        this.onChange(processes);
      }

      return processes;
    } catch (error) {
      // If lsof fails, return cached data (graceful degradation)
      // This can happen if lsof isn't installed or permission denied
      return this.cachedProcesses;
    }
  }

  /**
   * Parse lsof output into structured SystemProcess objects.
   *
   * Example lsof output:
   * COMMAND   PID   USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
   * node    42992 jackwakem   22u  IPv4 0x...      0t0  TCP *:3000 (LISTEN)
   * python3 19102 jackwakem    3u  IPv4 0x...      0t0  TCP 127.0.0.1:8000 (LISTEN)
   */
  private parseLsofOutput(output: string): SystemProcess[] {
    const lines = output.trim().split('\n');

    if (lines.length < 2) {
      return [];
    }

    // Skip header line
    const dataLines = lines.slice(1);
    const processes: SystemProcess[] = [];
    const seenPorts = new Set<number>(); // Deduplicate by port

    for (const line of dataLines) {
      const parsed = this.parseLsofLine(line);
      if (parsed && !seenPorts.has(parsed.port)) {
        seenPorts.add(parsed.port);
        processes.push(parsed);
      }
    }

    // Sort by port number
    return processes.sort((a, b) => a.port - b.port);
  }

  /**
   * Parse a single lsof output line.
   */
  private parseLsofLine(line: string): SystemProcess | null {
    // Split by whitespace, but handle the NAME column specially
    // Format: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
    const parts = line.trim().split(/\s+/);

    if (parts.length < 9) {
      return null;
    }

    const command = parts[0];
    const pid = parseInt(parts[1], 10);
    const user = parts[2];

    // NAME is the last column: "*:3000" or "127.0.0.1:8000" or "localhost:8080"
    const name = parts[parts.length - 1].replace('(LISTEN)', '').trim();

    // Parse address:port from NAME
    const colonIndex = name.lastIndexOf(':');
    if (colonIndex === -1) {
      return null;
    }

    const address = name.substring(0, colonIndex) || '*';
    const port = parseInt(name.substring(colonIndex + 1), 10);

    if (isNaN(pid) || isNaN(port)) {
      return null;
    }

    // Normalize address for display
    let displayAddress = address;
    if (address === '*' || address === '0.0.0.0' || address === '[::]') {
      displayAddress = '*';
    } else if (address === '127.0.0.1' || address === '[::1]') {
      displayAddress = 'localhost';
    }

    return {
      pid,
      command,
      port,
      address: displayAddress,
      user,
      managed: this.managedPids.has(pid),
    };
  }

  /**
   * Check if the process list has changed from cached.
   */
  private hasChanged(newProcesses: SystemProcess[]): boolean {
    if (newProcesses.length !== this.cachedProcesses.length) {
      return true;
    }

    // Compare by port:pid pairs
    const oldKeys = new Set(this.cachedProcesses.map(p => `${p.port}:${p.pid}`));
    const newKeys = new Set(newProcesses.map(p => `${p.port}:${p.pid}`));

    if (oldKeys.size !== newKeys.size) {
      return true;
    }

    for (const key of newKeys) {
      if (!oldKeys.has(key)) {
        return true;
      }
    }

    return false;
  }

  /**
   * Filter processes to only show relevant ports.
   * @param includeAllPorts If true, return all ports. Otherwise filter to dev range + common services.
   */
  filterRelevantPorts(processes: SystemProcess[], includeAllPorts: boolean = false): SystemProcess[] {
    if (includeAllPorts) {
      return processes;
    }

    // Dev port range: 3000-3099
    // Common services: 5432 (postgres), 3306 (mysql), 6379 (redis), 8000-8999, 5000-5999
    return processes.filter(p => {
      // Dev ports
      if (p.port >= 3000 && p.port <= 3099) return true;
      // Common web dev ports
      if (p.port >= 8000 && p.port <= 8999) return true;
      if (p.port >= 5000 && p.port <= 5999) return true;
      // Database ports
      if (p.port === 5432 || p.port === 3306 || p.port === 6379 || p.port === 27017) return true;
      // MCP managed processes always included
      if (p.managed) return true;
      return false;
    });
  }
}
