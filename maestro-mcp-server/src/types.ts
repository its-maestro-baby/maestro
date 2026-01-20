/**
 * Types for the Maestro MCP Server
 */

export interface ManagedProcess {
  sessionId: number;
  pid: number;
  command: string;
  workingDirectory: string;
  port: number | null;
  status: ProcessStatus;
  detectedUrl: string | null;
  startedAt: Date;
  stoppedAt: Date | null;
  exitCode: number | null;
}

export type ProcessStatus = 'starting' | 'running' | 'stopped' | 'error';

export interface StartServerOptions {
  sessionId: number;
  command: string;
  workingDirectory: string;
  port?: number;
  env?: Record<string, string>;
}

export interface ServerStatus {
  sessionId: number;
  status: ProcessStatus;
  pid: number | null;
  port: number | null;
  url: string | null;
  startedAt: string | null;
  uptime: number | null; // seconds
}

export interface LogEntry {
  timestamp: Date;
  stream: 'stdout' | 'stderr';
  data: string;
}

export interface ProjectInfo {
  type: ProjectType;
  suggestedCommand: string | null;
  configFiles: string[];
}

export type ProjectType =
  | 'nodejs'
  | 'rust'
  | 'swift'
  | 'python'
  | 'go'
  | 'makefile'
  | 'unknown';

/**
 * Represents a system process listening on a TCP port.
 * Used by PortScanner to detect all TCP listeners.
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
 * Status file format for IPC with Swift app.
 * Written by ProcessManager, read by MCPStatusWatcher.swift
 */
export interface StatusFile {
  servers: ServerStatus[];
  systemProcesses: SystemProcess[];
  updatedAt: string;
}
