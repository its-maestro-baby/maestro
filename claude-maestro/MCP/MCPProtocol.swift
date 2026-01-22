import Foundation

// MARK: - JSON-RPC Types

/// JSON-RPC request
public struct MCPRequest: Codable {
    public let jsonrpc: String
    public let id: RequestId?
    public let method: String
    public let params: AnyCodable?

    public init(jsonrpc: String = "2.0", id: RequestId? = nil, method: String, params: AnyCodable? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
}

/// JSON-RPC response
public struct MCPResponse: Codable {
    public let jsonrpc: String
    public let id: RequestId?
    public let result: AnyCodable?
    public let error: MCPError?

    public init(id: RequestId?, result: AnyCodable? = nil, error: MCPError? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }

    public static func success(id: RequestId?, result: Any) -> MCPResponse {
        MCPResponse(id: id, result: AnyCodable(result))
    }

    public static func error(id: RequestId?, code: Int, message: String, data: Any? = nil) -> MCPResponse {
        MCPResponse(id: id, error: MCPError(code: code, message: message, data: data.map { AnyCodable($0) }))
    }
}

/// JSON-RPC error
public struct MCPError: Codable {
    public let code: Int
    public let message: String
    public let data: AnyCodable?

    public init(code: Int, message: String, data: AnyCodable? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard JSON-RPC error codes
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602
    public static let internalError = -32603
}

/// Request ID (can be string or number)
public enum RequestId: Codable, Hashable {
    case string(String)
    case number(Int)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            self = .number(int)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.typeMismatch(RequestId.self, DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Request ID must be string or number"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str):
            try container.encode(str)
        case .number(let num):
            try container.encode(num)
        }
    }
}

// MARK: - MCP Protocol Types

/// MCP initialize request params
public struct MCPInitializeParams: Codable {
    public let protocolVersion: String
    public let capabilities: MCPClientCapabilities
    public let clientInfo: MCPClientInfo

    public init(protocolVersion: String, capabilities: MCPClientCapabilities, clientInfo: MCPClientInfo) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.clientInfo = clientInfo
    }
}

/// MCP client capabilities
public struct MCPClientCapabilities: Codable {
    public let roots: RootsCapability?
    public let sampling: SamplingCapability?

    public init(roots: RootsCapability? = nil, sampling: SamplingCapability? = nil) {
        self.roots = roots
        self.sampling = sampling
    }

    public struct RootsCapability: Codable {
        public let listChanged: Bool?
    }

    public struct SamplingCapability: Codable {}
}

/// MCP client info
public struct MCPClientInfo: Codable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// MCP server capabilities
public struct MCPServerCapabilities: Codable {
    public let tools: ToolsCapability?

    public init(tools: ToolsCapability? = nil) {
        self.tools = tools
    }

    public struct ToolsCapability: Codable {
        public let listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }
}

/// MCP server info
public struct MCPServerInfo: Codable {
    public let name: String
    public let version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// MCP initialize result
public struct MCPInitializeResult: Codable {
    public let protocolVersion: String
    public let capabilities: MCPServerCapabilities
    public let serverInfo: MCPServerInfo

    public init(protocolVersion: String, capabilities: MCPServerCapabilities, serverInfo: MCPServerInfo) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }
}

// MARK: - Tool Types

/// MCP tool definition
public struct MCPToolDefinition: Codable {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema

    public init(name: String, description: String, inputSchema: JSONSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// JSON Schema for tool input
public struct JSONSchema: Codable {
    public let type: String
    public let properties: [String: PropertySchema]?
    public let required: [String]?

    public init(type: String = "object", properties: [String: PropertySchema]? = nil, required: [String]? = nil) {
        self.type = type
        self.properties = properties
        self.required = required
    }

    public struct PropertySchema: Codable {
        public let type: String
        public let description: String?
        public let `enum`: [String]?
        public let `default`: AnyCodable?

        public init(type: String, description: String? = nil, enum: [String]? = nil, default: AnyCodable? = nil) {
            self.type = type
            self.description = description
            self.enum = `enum`
            self.default = `default`
        }
    }
}

/// Tool call params
public struct MCPToolCallParams: Codable {
    public let name: String
    public let arguments: [String: AnyCodable]?

    public init(name: String, arguments: [String: AnyCodable]? = nil) {
        self.name = name
        self.arguments = arguments
    }
}

/// Tool call result
public struct MCPToolResult: Codable {
    public let content: [MCPContent]
    public let isError: Bool?

    public init(content: [MCPContent], isError: Bool? = nil) {
        self.content = content
        self.isError = isError
    }

    public static func text(_ text: String) -> MCPToolResult {
        MCPToolResult(content: [MCPContent(type: "text", text: text)])
    }

    public static func error(_ message: String) -> MCPToolResult {
        MCPToolResult(content: [MCPContent(type: "text", text: message)], isError: true)
    }
}

/// MCP content
public struct MCPContent: Codable {
    public let type: String
    public let text: String?

    public init(type: String, text: String? = nil) {
        self.type = type
        self.text = text
    }
}

// MARK: - Type-erased Codable

/// Type-erased Codable wrapper
public struct AnyCodable: Codable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self.value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            self.value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unable to decode value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unable to encode value")
            throw EncodingError.invalidValue(value, context)
        }
    }

    // Convenience accessors
    public var string: String? { value as? String }
    public var int: Int? { value as? Int }
    public var double: Double? { value as? Double }
    public var bool: Bool? { value as? Bool }
    public var array: [Any]? { value as? [Any] }
    public var dict: [String: Any]? { value as? [String: Any] }
}
