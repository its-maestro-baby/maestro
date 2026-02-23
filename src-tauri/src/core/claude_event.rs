//! Unified event types for the Claude Event Bus.
//!
//! Every event flowing through the system is represented as a [`ClaudeEvent`]
//! variant. The enum is serde-tagged so that JSON payloads carry an explicit
//! `"event_type"` discriminator, making frontend consumption straightforward.

use serde::{Deserialize, Serialize};

/// Token usage statistics reported by the Claude API.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct TokenUsage {
    pub input_tokens: u64,
    pub output_tokens: u64,
    pub cache_read_input_tokens: u64,
    pub cache_creation_input_tokens: u64,
}

/// A single event emitted by, or on behalf of, a Claude Code session.
///
/// Variants are internally tagged via `event_type` so the serialized JSON
/// always contains `{ "event_type": "VariantName", ... }`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event_type")]
pub enum ClaudeEvent {
    /// A new Claude Code session has started.
    SessionStarted {
        session_id: u32,
        timestamp: String,
    },

    /// A Claude Code session has ended.
    SessionEnded {
        session_id: u32,
        timestamp: String,
    },

    /// The user sent a message to the assistant.
    UserMessage {
        session_id: u32,
        message: String,
        timestamp: String,
    },

    /// The assistant produced a (possibly partial) response.
    AssistantMessage {
        session_id: u32,
        message: String,
        timestamp: String,
    },

    /// A tool invocation has started.
    ToolUseStarted {
        session_id: u32,
        tool_use_id: String,
        tool_name: String,
        timestamp: String,
    },

    /// A tool invocation has completed.
    ToolUseCompleted {
        session_id: u32,
        tool_use_id: String,
        tool_name: String,
        success: bool,
        timestamp: String,
    },

    /// A file was edited by the assistant.
    FileEdited {
        session_id: u32,
        file_path: String,
        timestamp: String,
    },

    /// A new file was created by the assistant.
    FileCreated {
        session_id: u32,
        file_path: String,
        timestamp: String,
    },

    /// A sub-agent was spawned.
    SubagentSpawned {
        session_id: u32,
        subagent_id: String,
        timestamp: String,
    },

    /// A sub-agent finished its work.
    SubagentCompleted {
        session_id: u32,
        subagent_id: String,
        success: bool,
        timestamp: String,
    },

    /// A status/state change reported by the session.
    StatusUpdate {
        session_id: u32,
        state: String,
        message: String,
        timestamp: String,
    },

    /// Cumulative token usage for a session.
    TokenUsageUpdate {
        session_id: u32,
        usage: TokenUsage,
        timestamp: String,
    },
}

impl ClaudeEvent {
    /// Returns the `session_id` carried by every event variant.
    pub fn session_id(&self) -> u32 {
        match self {
            ClaudeEvent::SessionStarted { session_id, .. }
            | ClaudeEvent::SessionEnded { session_id, .. }
            | ClaudeEvent::UserMessage { session_id, .. }
            | ClaudeEvent::AssistantMessage { session_id, .. }
            | ClaudeEvent::ToolUseStarted { session_id, .. }
            | ClaudeEvent::ToolUseCompleted { session_id, .. }
            | ClaudeEvent::FileEdited { session_id, .. }
            | ClaudeEvent::FileCreated { session_id, .. }
            | ClaudeEvent::SubagentSpawned { session_id, .. }
            | ClaudeEvent::SubagentCompleted { session_id, .. }
            | ClaudeEvent::StatusUpdate { session_id, .. }
            | ClaudeEvent::TokenUsageUpdate { session_id, .. } => *session_id,
        }
    }

    /// Returns a deduplication key unique to this event's identity.
    ///
    /// Two events with the same dedup key represent the same logical
    /// occurrence and one may safely be dropped. The key encodes the
    /// variant discriminator together with any fields that distinguish
    /// one occurrence from another (e.g. `tool_use_id`, `file_path`).
    pub fn dedup_key(&self) -> String {
        match self {
            ClaudeEvent::SessionStarted { session_id, timestamp } => {
                format!("SessionStarted:{session_id}:{timestamp}")
            }
            ClaudeEvent::SessionEnded { session_id, timestamp } => {
                format!("SessionEnded:{session_id}:{timestamp}")
            }
            ClaudeEvent::UserMessage { session_id, timestamp, .. } => {
                format!("UserMessage:{session_id}:{timestamp}")
            }
            ClaudeEvent::AssistantMessage { session_id, timestamp, .. } => {
                format!("AssistantMessage:{session_id}:{timestamp}")
            }
            ClaudeEvent::ToolUseStarted { session_id, tool_use_id, .. } => {
                format!("ToolUseStarted:{session_id}:{tool_use_id}")
            }
            ClaudeEvent::ToolUseCompleted { session_id, tool_use_id, .. } => {
                format!("ToolUseCompleted:{session_id}:{tool_use_id}")
            }
            ClaudeEvent::FileEdited { session_id, file_path, timestamp } => {
                format!("FileEdited:{session_id}:{file_path}:{timestamp}")
            }
            ClaudeEvent::FileCreated { session_id, file_path, timestamp } => {
                format!("FileCreated:{session_id}:{file_path}:{timestamp}")
            }
            ClaudeEvent::SubagentSpawned { session_id, subagent_id, .. } => {
                format!("SubagentSpawned:{session_id}:{subagent_id}")
            }
            ClaudeEvent::SubagentCompleted { session_id, subagent_id, .. } => {
                format!("SubagentCompleted:{session_id}:{subagent_id}")
            }
            ClaudeEvent::StatusUpdate { session_id, timestamp, .. } => {
                format!("StatusUpdate:{session_id}:{timestamp}")
            }
            ClaudeEvent::TokenUsageUpdate { session_id, timestamp, .. } => {
                format!("TokenUsageUpdate:{session_id}:{timestamp}")
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dedup_key_uniqueness() {
        let a = ClaudeEvent::ToolUseStarted {
            session_id: 1,
            tool_use_id: "tool_aaa".into(),
            tool_name: "Read".into(),
            timestamp: "2026-02-24T00:00:00Z".into(),
        };
        let b = ClaudeEvent::ToolUseStarted {
            session_id: 1,
            tool_use_id: "tool_bbb".into(),
            tool_name: "Read".into(),
            timestamp: "2026-02-24T00:00:00Z".into(),
        };
        assert_ne!(a.dedup_key(), b.dedup_key());
    }

    #[test]
    fn test_dedup_key_same_event() {
        let a = ClaudeEvent::ToolUseStarted {
            session_id: 1,
            tool_use_id: "tool_aaa".into(),
            tool_name: "Read".into(),
            timestamp: "2026-02-24T00:00:00Z".into(),
        };
        let b = ClaudeEvent::ToolUseStarted {
            session_id: 1,
            tool_use_id: "tool_aaa".into(),
            tool_name: "Read".into(),
            timestamp: "2026-02-24T00:00:00Z".into(),
        };
        assert_eq!(a.dedup_key(), b.dedup_key());
    }

    #[test]
    fn test_session_id_extraction() {
        let events: Vec<ClaudeEvent> = vec![
            ClaudeEvent::SessionStarted { session_id: 1, timestamp: "t".into() },
            ClaudeEvent::SessionEnded { session_id: 2, timestamp: "t".into() },
            ClaudeEvent::UserMessage { session_id: 3, message: "hi".into(), timestamp: "t".into() },
            ClaudeEvent::AssistantMessage { session_id: 4, message: "hello".into(), timestamp: "t".into() },
            ClaudeEvent::ToolUseStarted { session_id: 5, tool_use_id: "x".into(), tool_name: "y".into(), timestamp: "t".into() },
            ClaudeEvent::ToolUseCompleted { session_id: 6, tool_use_id: "x".into(), tool_name: "y".into(), success: true, timestamp: "t".into() },
            ClaudeEvent::FileEdited { session_id: 7, file_path: "/a".into(), timestamp: "t".into() },
            ClaudeEvent::FileCreated { session_id: 8, file_path: "/b".into(), timestamp: "t".into() },
            ClaudeEvent::SubagentSpawned { session_id: 9, subagent_id: "s".into(), timestamp: "t".into() },
            ClaudeEvent::SubagentCompleted { session_id: 10, subagent_id: "s".into(), success: true, timestamp: "t".into() },
            ClaudeEvent::StatusUpdate { session_id: 11, state: "working".into(), message: "m".into(), timestamp: "t".into() },
            ClaudeEvent::TokenUsageUpdate { session_id: 12, usage: TokenUsage { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0 }, timestamp: "t".into() },
        ];
        for (i, event) in events.iter().enumerate() {
            assert_eq!(event.session_id(), (i as u32) + 1);
        }
    }

    #[test]
    fn test_serialize_deserialize_roundtrip() {
        let original = ClaudeEvent::AssistantMessage {
            session_id: 42,
            message: "Hello, world!".into(),
            timestamp: "2026-02-24T12:00:00Z".into(),
        };
        let json = serde_json::to_string(&original).expect("serialize");
        let recovered: ClaudeEvent = serde_json::from_str(&json).expect("deserialize");

        assert_eq!(recovered.session_id(), 42);
        if let ClaudeEvent::AssistantMessage { message, .. } = &recovered {
            assert_eq!(message, "Hello, world!");
        } else {
            panic!("wrong variant after roundtrip");
        }
    }

    #[test]
    fn test_tagged_serialization() {
        let event = ClaudeEvent::ToolUseStarted {
            session_id: 1,
            tool_use_id: "abc".into(),
            tool_name: "Read".into(),
            timestamp: "2026-02-24T00:00:00Z".into(),
        };
        let json = serde_json::to_string(&event).expect("serialize");
        assert!(
            json.contains(r#""event_type":"ToolUseStarted""#),
            "JSON should contain tagged event_type field, got: {json}"
        );
    }
}
