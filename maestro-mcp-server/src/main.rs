//! MCP Server for Claude Maestro status reporting.
//!
//! This server implements the Model Context Protocol (MCP) over stdio,
//! providing the `maestro_status` tool that reports agent status to
//! the Maestro application via HTTP POST.

mod mcp_protocol;
mod status_reporter;

use mcp_protocol::McpServer;
use std::env;

#[tokio::main]
async fn main() {
    // Read configuration from environment variables
    let status_url = env::var("MAESTRO_STATUS_URL").ok();
    let session_id: Option<u32> = env::var("MAESTRO_SESSION_ID")
        .ok()
        .and_then(|s| s.parse().ok());
    let instance_id = env::var("MAESTRO_INSTANCE_ID").ok();

    // Log configuration for debugging (to stderr so it doesn't interfere with MCP protocol)
    eprintln!(
        "[maestro-mcp-server] Starting with config: status_url={:?}, session_id={:?}, instance_id={:?}",
        status_url, session_id, instance_id
    );

    // Create and run the MCP server
    let server = McpServer::new(status_url, session_id, instance_id);

    if let Err(e) = server.run().await {
        eprintln!("[maestro-mcp-server] Error: {}", e);
        std::process::exit(1);
    }
}
