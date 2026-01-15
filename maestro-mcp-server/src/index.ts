#!/usr/bin/env node

import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { createServer } from './server.js';

/**
 * Maestro MCP Server
 *
 * This server manages development server processes for Claude Maestro.
 * It runs as a subprocess of Maestro and communicates via stdio.
 *
 * Available tools:
 * - start_dev_server: Start a dev server for a session
 * - stop_dev_server: Stop a running dev server
 * - restart_dev_server: Restart a dev server
 * - get_server_status: Get status of dev servers
 * - get_server_logs: Get recent logs from a dev server
 * - list_available_ports: List available ports in range
 * - detect_project_type: Detect project type and suggest run command
 */

async function main() {
  const server = createServer();
  const transport = new StdioServerTransport();

  await server.connect(transport);

  // Keep the server running
  // The server will handle stdin/stdout communication
}

main().catch((error) => {
  // Log errors to stderr (not stdout, which is for MCP protocol)
  console.error('Maestro MCP Server error:', error);
  process.exit(1);
});
