import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { PortManager } from './managers/PortManager.js';
import { LogManager } from './managers/LogManager.js';
import { ProcessManager } from './managers/ProcessManager.js';
import { detectProjectType } from './utils/projectDetection.js';
// Input schemas using zod
const StartServerSchema = z.object({
    session_id: z.number().describe('Maestro session ID'),
    command: z.string().describe('Command to run (e.g., "npm run dev")'),
    working_directory: z.string().describe('Directory to run in'),
    port: z.number().optional().describe('Preferred port (optional, auto-assigned if not provided)'),
});
const StopServerSchema = z.object({
    session_id: z.number().describe('Session ID of server to stop'),
});
const RestartServerSchema = z.object({
    session_id: z.number().describe('Session ID to restart'),
});
const GetStatusSchema = z.object({
    session_id: z.number().optional().describe('Session ID to check (optional, lists all if omitted)'),
});
const GetLogsSchema = z.object({
    session_id: z.number().describe('Session ID'),
    lines: z.number().optional().default(50).describe('Number of recent lines (default 50)'),
    stream: z.enum(['stdout', 'stderr', 'all']).optional().default('all').describe('Which stream'),
});
const ListPortsSchema = z.object({
    count: z.number().optional().default(5).describe('Number of ports to return (default 5)'),
});
const DetectProjectSchema = z.object({
    directory: z.string().describe('Project directory to analyze'),
});
/**
 * Create and configure the MCP server.
 */
export function createServer() {
    const portManager = new PortManager();
    const logManager = new LogManager();
    const processManager = new ProcessManager(portManager, logManager);
    const server = new McpServer({
        name: 'maestro-process-manager',
        version: '1.0.0',
    });
    // Tool: start_dev_server
    server.tool('start_dev_server', 'Start a development server for the current project', StartServerSchema.shape, async (args) => {
        try {
            const managed = await processManager.startProcess({
                sessionId: args.session_id,
                command: args.command,
                workingDirectory: args.working_directory,
                port: args.port,
            });
            return {
                content: [
                    {
                        type: 'text',
                        text: JSON.stringify({
                            success: true,
                            message: `Dev server started for session ${args.session_id}`,
                            pid: managed.pid,
                            port: managed.port,
                            status: managed.status,
                        }, null, 2),
                    },
                ],
            };
        }
        catch (error) {
            return {
                content: [
                    {
                        type: 'text',
                        text: JSON.stringify({
                            success: false,
                            error: error instanceof Error ? error.message : String(error),
                        }, null, 2),
                    },
                ],
                isError: true,
            };
        }
    });
    // Tool: stop_dev_server
    server.tool('stop_dev_server', 'Stop a running development server', StopServerSchema.shape, async (args) => {
        try {
            await processManager.stopProcess(args.session_id);
            return {
                content: [
                    {
                        type: 'text',
                        text: JSON.stringify({
                            success: true,
                            message: `Dev server stopped for session ${args.session_id}`,
                        }, null, 2),
                    },
                ],
            };
        }
        catch (error) {
            return {
                content: [
                    {
                        type: 'text',
                        text: JSON.stringify({
                            success: false,
                            error: error instanceof Error ? error.message : String(error),
                        }, null, 2),
                    },
                ],
                isError: true,
            };
        }
    });
    // Tool: restart_dev_server
    server.tool('restart_dev_server', 'Restart a development server (stop + start with same config)', RestartServerSchema.shape, async (args) => {
        try {
            const managed = await processManager.restartProcess(args.session_id);
            return {
                content: [
                    {
                        type: 'text',
                        text: JSON.stringify({
                            success: true,
                            message: `Dev server restarted for session ${args.session_id}`,
                            pid: managed.pid,
                            port: managed.port,
                            status: managed.status,
                        }, null, 2),
                    },
                ],
            };
        }
        catch (error) {
            return {
                content: [
                    {
                        type: 'text',
                        text: JSON.stringify({
                            success: false,
                            error: error instanceof Error ? error.message : String(error),
                        }, null, 2),
                    },
                ],
                isError: true,
            };
        }
    });
    // Tool: get_server_status
    server.tool('get_server_status', 'Get status of a dev server (running, stopped, error, port, URL)', GetStatusSchema.shape, async (args) => {
        if (args.session_id !== undefined) {
            const status = processManager.getStatus(args.session_id);
            if (!status) {
                return {
                    content: [
                        {
                            type: 'text',
                            text: JSON.stringify({
                                success: false,
                                error: `No process found for session ${args.session_id}`,
                            }, null, 2),
                        },
                    ],
                };
            }
            return {
                content: [
                    {
                        type: 'text',
                        text: JSON.stringify({
                            success: true,
                            status,
                        }, null, 2),
                    },
                ],
            };
        }
        // Return all statuses
        const statuses = processManager.getAllStatuses();
        return {
            content: [
                {
                    type: 'text',
                    text: JSON.stringify({
                        success: true,
                        servers: statuses,
                        total: statuses.length,
                    }, null, 2),
                },
            ],
        };
    });
    // Tool: get_server_logs
    server.tool('get_server_logs', 'Get recent output logs from a dev server', GetLogsSchema.shape, async (args) => {
        const logs = logManager.getLogsAsString(args.session_id, {
            lines: args.lines,
            stream: args.stream,
            includeTimestamps: false,
        });
        return {
            content: [
                {
                    type: 'text',
                    text: logs || '(no logs available)',
                },
            ],
        };
    });
    // Tool: list_available_ports
    server.tool('list_available_ports', 'Get available ports in the Maestro-managed range (3000-3099)', ListPortsSchema.shape, async (args) => {
        const ports = await portManager.getAvailablePorts(args.count);
        return {
            content: [
                {
                    type: 'text',
                    text: JSON.stringify({
                        available_ports: ports,
                        range: '3000-3099',
                    }, null, 2),
                },
            ],
        };
    });
    // Tool: detect_project_type
    server.tool('detect_project_type', 'Detect project type and suggest run command based on config files', DetectProjectSchema.shape, async (args) => {
        const info = detectProjectType(args.directory);
        return {
            content: [
                {
                    type: 'text',
                    text: JSON.stringify({
                        project_type: info.type,
                        suggested_command: info.suggestedCommand,
                        config_files_found: info.configFiles,
                    }, null, 2),
                },
            ],
        };
    });
    // Handle cleanup on server shutdown
    process.on('SIGTERM', async () => {
        await processManager.cleanup();
        process.exit(0);
    });
    process.on('SIGINT', async () => {
        await processManager.cleanup();
        process.exit(0);
    });
    return server;
}
//# sourceMappingURL=server.js.map