import Foundation

/// Represents the state of an agent as reported via the maestro-status MCP server.
/// This model matches the JSON schema written to /tmp/maestro/agents/
struct AgentState: Codable, Identifiable, Equatable, Sendable {
    var id: String { agentId }

    /// Unique identifier for the agent (e.g., "agent-1", "agent-2")
    let agentId: String

    /// Current state of the agent
    let state: AgentStatusState

    /// Brief description of what the agent is doing or waiting for
    let message: String

    /// When state is 'needs_input', the specific question or prompt for the user
    let needsInputPrompt: String?

    /// ISO 8601 timestamp when the state was reported
    let timestamp: Date

    /// Session ID extracted from agent ID (e.g., "agent-1" -> 1)
    var sessionId: Int? {
        guard agentId.hasPrefix("agent-") else { return nil }
        let idPart = agentId.dropFirst("agent-".count)
        return Int(idPart)
    }

    /// Whether this agent needs user input
    var needsInput: Bool {
        state == .needsInput
    }

    /// How long ago this state was reported
    var age: TimeInterval {
        Date().timeIntervalSince(timestamp)
    }

    /// Whether this state is considered stale (>5 minutes old)
    var isStale: Bool {
        age > 300 // 5 minutes
    }

    private enum CodingKeys: String, CodingKey {
        case agentId
        case state
        case message
        case needsInputPrompt
        case timestamp
    }

    init(agentId: String, state: AgentStatusState, message: String, needsInputPrompt: String? = nil, timestamp: Date = Date()) {
        self.agentId = agentId
        self.state = state
        self.message = message
        self.needsInputPrompt = needsInputPrompt
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agentId = try container.decode(String.self, forKey: .agentId)
        state = try container.decode(AgentStatusState.self, forKey: .state)
        message = try container.decode(String.self, forKey: .message)
        needsInputPrompt = try container.decodeIfPresent(String.self, forKey: .needsInputPrompt)

        // Parse ISO 8601 timestamp
        let timestampString = try container.decode(String.self, forKey: .timestamp)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: timestampString) {
            timestamp = date
        } else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: timestampString) {
                timestamp = date
            } else {
                throw DecodingError.dataCorruptedError(forKey: .timestamp, in: container, debugDescription: "Invalid ISO 8601 timestamp: \(timestampString)")
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(agentId, forKey: .agentId)
        try container.encode(state, forKey: .state)
        try container.encode(message, forKey: .message)
        try container.encodeIfPresent(needsInputPrompt, forKey: .needsInputPrompt)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try container.encode(formatter.string(from: timestamp), forKey: .timestamp)
    }
}

/// Agent status states as reported via the maestro_status MCP tool
enum AgentStatusState: String, Codable, CaseIterable, Sendable {
    /// Ready for work, not currently processing
    case idle

    /// Actively processing with semantic message
    case working

    /// Waiting for user input with specific prompt
    case needsInput = "needs_input"

    /// Task complete
    case finished

    /// Hit a blocker or encountered an error
    case error

    /// Display name for UI
    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .working: return "Working"
        case .needsInput: return "Needs Input"
        case .finished: return "Finished"
        case .error: return "Error"
        }
    }

    /// SF Symbol name for this state
    var systemImage: String {
        switch self {
        case .idle: return "circle"
        case .working: return "gear"
        case .needsInput: return "questionmark.circle.fill"
        case .finished: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
}
