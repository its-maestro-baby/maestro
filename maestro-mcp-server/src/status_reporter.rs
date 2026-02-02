//! HTTP-based status reporting to Maestro.
//!
//! Reports agent status via HTTP POST to the Maestro application's
//! status endpoint. This replaces the previous file-based approach
//! to eliminate race conditions and provide real-time updates.

use serde::Serialize;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum StatusError {
    #[error("HTTP request failed: {0}")]
    HttpError(#[from] reqwest::Error),
}

/// Payload sent to Maestro's status endpoint.
#[derive(Debug, Serialize)]
pub struct StatusPayload {
    pub session_id: u32,
    pub instance_id: String,
    pub state: String,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub needs_input_prompt: Option<String>,
    pub timestamp: String,
}

/// Reports status to Maestro via HTTP POST.
pub struct StatusReporter {
    client: reqwest::Client,
    status_url: Option<String>,
    session_id: Option<u32>,
    instance_id: Option<String>,
}

impl StatusReporter {
    pub fn new(
        status_url: Option<String>,
        session_id: Option<u32>,
        instance_id: Option<String>,
    ) -> Self {
        Self {
            client: reqwest::Client::new(),
            status_url,
            session_id,
            instance_id,
        }
    }

    /// Report status to Maestro.
    ///
    /// Returns Ok(()) if the status was successfully reported, or if
    /// no status URL is configured (graceful degradation).
    pub async fn report_status(
        &self,
        state: &str,
        message: &str,
        needs_input_prompt: Option<String>,
    ) -> Result<(), StatusError> {
        let status_url = match &self.status_url {
            Some(url) => url,
            None => return Ok(()), // Graceful degradation if not configured
        };

        let session_id = self.session_id.unwrap_or(0);
        let instance_id = self
            .instance_id
            .clone()
            .unwrap_or_else(|| "unknown".to_string());

        let payload = StatusPayload {
            session_id,
            instance_id,
            state: state.to_string(),
            message: message.to_string(),
            needs_input_prompt,
            timestamp: chrono::Utc::now().to_rfc3339(),
        };

        // Send HTTP POST to Maestro's status endpoint
        eprintln!(
            "[maestro-mcp-server] Sending status to {}: session_id={}, state={}, message={}",
            status_url, payload.session_id, payload.state, payload.message
        );

        let response = self.client
            .post(status_url)
            .json(&payload)
            .timeout(std::time::Duration::from_secs(5))
            .send()
            .await?;

        eprintln!(
            "[maestro-mcp-server] Status response: {}",
            response.status()
        );

        Ok(())
    }
}
