import { spawn, type ChildProcess } from 'child_process';
import type { ManagedProcess, ProcessStatus, StartServerOptions, ServerStatus } from '../types.js';
import { PortManager } from './PortManager.js';
import { LogManager } from './LogManager.js';

// Regex patterns to detect server URLs in output
const URL_PATTERNS = [
  /https?:\/\/localhost:\d+/gi,
  /https?:\/\/127\.0\.0\.1:\d+/gi,
  /https?:\/\/0\.0\.0\.0:\d+/gi,
  /Local:\s+(https?:\/\/[^\s]+)/gi, // Vite style
  /ready on\s+(https?:\/\/[^\s]+)/gi, // Next.js style
  /listening on\s+(https?:\/\/[^\s]+)/gi, // Express style
  /Server running at\s+(https?:\/\/[^\s]+)/gi,
];

/**
 * Manages dev server processes.
 * Handles starting, stopping, and monitoring of processes.
 */
export class ProcessManager {
  private processes: Map<number, ManagedProcess> = new Map();
  private childProcesses: Map<number, ChildProcess> = new Map();
  private portManager: PortManager;
  private logManager: LogManager;

  constructor(portManager: PortManager, logManager: LogManager) {
    this.portManager = portManager;
    this.logManager = logManager;
  }

  /**
   * Start a dev server for a session.
   */
  async startProcess(options: StartServerOptions): Promise<ManagedProcess> {
    const { sessionId, command, workingDirectory, port: preferredPort, env } = options;

    // Check if already running
    const existing = this.processes.get(sessionId);
    if (existing && (existing.status === 'running' || existing.status === 'starting')) {
      throw new Error(`Session ${sessionId} already has a running process`);
    }

    // Allocate port
    const port = await this.portManager.assignPort(sessionId, preferredPort);

    // Create managed process record
    const managed: ManagedProcess = {
      sessionId,
      pid: 0, // Will be set after spawn
      command,
      workingDirectory,
      port,
      status: 'starting',
      detectedUrl: null,
      startedAt: new Date(),
      stoppedAt: null,
      exitCode: null,
    };

    // Build environment with PORT variable
    const processEnv = {
      ...process.env,
      ...env,
      PORT: String(port),
    };

    // Parse command into executable and args
    const shell = process.env.SHELL || '/bin/zsh';

    // Spawn the process
    const child = spawn(shell, ['-l', '-c', command], {
      cwd: workingDirectory,
      env: processEnv,
      detached: false,
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    if (child.pid) {
      managed.pid = child.pid;
    }

    // Store references
    this.processes.set(sessionId, managed);
    this.childProcesses.set(sessionId, child);

    // Handle stdout
    child.stdout?.on('data', (data: Buffer) => {
      const text = data.toString();
      this.logManager.append(sessionId, 'stdout', text);
      this.detectServerUrl(sessionId, text);

      // If we detect a URL, mark as running
      if (managed.status === 'starting' && managed.detectedUrl) {
        managed.status = 'running';
      }
    });

    // Handle stderr
    child.stderr?.on('data', (data: Buffer) => {
      const text = data.toString();
      this.logManager.append(sessionId, 'stderr', text);
    });

    // Handle process exit
    child.on('exit', (code, signal) => {
      managed.status = code === 0 ? 'stopped' : 'error';
      managed.exitCode = code;
      managed.stoppedAt = new Date();
      this.childProcesses.delete(sessionId);
      this.portManager.releasePort(sessionId);
    });

    // Handle errors
    child.on('error', (error) => {
      managed.status = 'error';
      managed.stoppedAt = new Date();
      this.logManager.append(sessionId, 'stderr', `Process error: ${error.message}`);
      this.childProcesses.delete(sessionId);
      this.portManager.releasePort(sessionId);
    });

    // After a short delay, assume running if not already detected
    setTimeout(() => {
      if (managed.status === 'starting' && this.childProcesses.has(sessionId)) {
        managed.status = 'running';
        if (!managed.detectedUrl && managed.port) {
          managed.detectedUrl = `http://localhost:${managed.port}`;
        }
      }
    }, 3000);

    return managed;
  }

  /**
   * Stop a running process.
   */
  async stopProcess(sessionId: number): Promise<void> {
    const child = this.childProcesses.get(sessionId);
    const managed = this.processes.get(sessionId);

    if (!child || !managed) {
      throw new Error(`No process found for session ${sessionId}`);
    }

    if (managed.status === 'stopped' || managed.status === 'error') {
      throw new Error(`Process for session ${sessionId} is already stopped`);
    }

    // Send SIGTERM first
    child.kill('SIGTERM');

    // Wait a bit, then force kill if needed
    await new Promise<void>((resolve) => {
      const timeout = setTimeout(() => {
        if (this.childProcesses.has(sessionId)) {
          child.kill('SIGKILL');
        }
        resolve();
      }, 5000);

      child.once('exit', () => {
        clearTimeout(timeout);
        resolve();
      });
    });

    managed.status = 'stopped';
    managed.stoppedAt = new Date();
    this.portManager.releasePort(sessionId);
  }

  /**
   * Restart a process.
   */
  async restartProcess(sessionId: number): Promise<ManagedProcess> {
    const managed = this.processes.get(sessionId);
    if (!managed) {
      throw new Error(`No process found for session ${sessionId}`);
    }

    // Stop if running
    if (this.childProcesses.has(sessionId)) {
      await this.stopProcess(sessionId);
    }

    // Clear old logs
    this.logManager.clear(sessionId);

    // Start with same config
    return this.startProcess({
      sessionId: managed.sessionId,
      command: managed.command,
      workingDirectory: managed.workingDirectory,
      port: managed.port || undefined,
    });
  }

  /**
   * Get status of a process.
   */
  getStatus(sessionId: number): ServerStatus | null {
    const managed = this.processes.get(sessionId);
    if (!managed) {
      return null;
    }

    const uptime = managed.stoppedAt
      ? null
      : Math.floor((Date.now() - managed.startedAt.getTime()) / 1000);

    return {
      sessionId: managed.sessionId,
      status: managed.status,
      pid: managed.pid || null,
      port: managed.port,
      url: managed.detectedUrl,
      startedAt: managed.startedAt.toISOString(),
      uptime,
    };
  }

  /**
   * Get status of all processes.
   */
  getAllStatuses(): ServerStatus[] {
    const statuses: ServerStatus[] = [];
    for (const sessionId of this.processes.keys()) {
      const status = this.getStatus(sessionId);
      if (status) {
        statuses.push(status);
      }
    }
    return statuses;
  }

  /**
   * Check if a session has a running process.
   */
  isRunning(sessionId: number): boolean {
    const managed = this.processes.get(sessionId);
    return managed?.status === 'running' || managed?.status === 'starting';
  }

  /**
   * Detect server URL from output.
   */
  private detectServerUrl(sessionId: number, text: string): void {
    const managed = this.processes.get(sessionId);
    if (!managed || managed.detectedUrl) {
      return;
    }

    for (const pattern of URL_PATTERNS) {
      const match = pattern.exec(text);
      if (match) {
        // Some patterns capture in group 1
        managed.detectedUrl = match[1] || match[0];
        return;
      }
      // Reset regex lastIndex for global patterns
      pattern.lastIndex = 0;
    }
  }

  /**
   * Cleanup all processes (for shutdown).
   */
  async cleanup(): Promise<void> {
    const stopPromises = Array.from(this.childProcesses.keys()).map(sessionId =>
      this.stopProcess(sessionId).catch(() => {})
    );
    await Promise.all(stopPromises);
  }
}
