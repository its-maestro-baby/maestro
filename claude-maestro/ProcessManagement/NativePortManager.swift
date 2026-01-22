import Foundation
import Darwin

/// Port allocation information
public struct PortAllocation: Sendable {
    public let port: UInt16
    public let sessionId: Int
    public let allocatedAt: Date

    public init(port: UInt16, sessionId: Int, allocatedAt: Date = Date()) {
        self.port = port
        self.sessionId = sessionId
        self.allocatedAt = allocatedAt
    }
}

/// Information about a listening port
public struct ListeningPort: Sendable, Identifiable {
    public var id: UInt16 { port }
    public let port: UInt16
    public let address: String
    public let pid: pid_t?
    public let processName: String?
    public let isManaged: Bool

    public init(port: UInt16, address: String, pid: pid_t? = nil, processName: String? = nil, isManaged: Bool = false) {
        self.port = port
        self.address = address
        self.pid = pid
        self.processName = processName
        self.isManaged = isManaged
    }
}

/// Native socket-based port management
/// Replaces lsof-based port checking with direct socket tests
public actor NativePortManager {

    /// Port range for dev servers
    public static let devPortRange: ClosedRange<UInt16> = 3000...3099

    /// Additional commonly used dev ports
    public static let commonDevPorts: Set<UInt16> = Set(
        Array(8000...8099) + Array(5000...5099)
    ).union([4200, 4000, 9000, 9090])

    private var allocations: [UInt16: PortAllocation] = [:]
    private var sessionPorts: [Int: UInt16] = [:]

    public init() {}

    // MARK: - Port Availability

    /// Check if a port is available for binding
    /// - Parameter port: Port number to check
    /// - Returns: True if port is available
    public func isPortAvailable(_ port: UInt16) -> Bool {
        // Try to create and bind a socket
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }

        defer { close(sock) }

        // Allow port reuse (helps with quick restarts)
        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Set up address structure
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        // Try to bind
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return result == 0
    }

    /// Find the next available port in the dev range
    /// - Parameter preferredPort: Optional preferred port to try first
    /// - Returns: Available port number, or nil if range is exhausted
    public func findAvailablePort(preferredPort: UInt16? = nil) -> UInt16? {
        // Try preferred port first
        if let preferred = preferredPort,
           Self.devPortRange.contains(preferred),
           allocations[preferred] == nil,
           isPortAvailable(preferred) {
            return preferred
        }

        // Search through the range
        for port in Self.devPortRange {
            if allocations[port] == nil && isPortAvailable(port) {
                return port
            }
        }

        return nil
    }

    /// Get multiple available ports
    /// - Parameter count: Number of ports to find
    /// - Returns: Array of available ports
    public func findAvailablePorts(count: Int = 5) -> [UInt16] {
        var ports: [UInt16] = []

        for port in Self.devPortRange {
            guard ports.count < count else { break }
            if allocations[port] == nil && isPortAvailable(port) {
                ports.append(port)
            }
        }

        return ports
    }

    // MARK: - Port Allocation

    /// Allocate a port for a session
    /// - Parameters:
    ///   - sessionId: Session requesting the port
    ///   - preferredPort: Optional preferred port
    /// - Returns: Allocated port, or nil if no ports available
    public func allocatePort(for sessionId: Int, preferredPort: UInt16? = nil) -> UInt16? {
        // If session already has a port, return it
        if let existingPort = sessionPorts[sessionId] {
            return existingPort
        }

        // Find available port
        guard let port = findAvailablePort(preferredPort: preferredPort) else {
            return nil
        }

        // Record allocation
        let allocation = PortAllocation(port: port, sessionId: sessionId)
        allocations[port] = allocation
        sessionPorts[sessionId] = port

        return port
    }

    /// Release a port allocation
    /// - Parameter port: Port to release
    public func releasePort(_ port: UInt16) {
        if let allocation = allocations.removeValue(forKey: port) {
            sessionPorts.removeValue(forKey: allocation.sessionId)
        }
    }

    /// Release all ports for a session
    /// - Parameter sessionId: Session ID
    public func releasePortsForSession(_ sessionId: Int) {
        if let port = sessionPorts.removeValue(forKey: sessionId) {
            allocations.removeValue(forKey: port)
        }
    }

    /// Get the port allocated to a session
    /// - Parameter sessionId: Session ID
    /// - Returns: Allocated port or nil
    public func getPort(for sessionId: Int) -> UInt16? {
        sessionPorts[sessionId]
    }

    /// Get all current allocations
    public var allAllocations: [PortAllocation] {
        Array(allocations.values)
    }

    // MARK: - Port Scanning

    /// Scan for listening ports in the dev range
    /// - Parameter processTree: ProcessTree instance for process name lookup
    /// - Returns: Array of ListeningPort info
    public func scanListeningPorts(processTree: ProcessTree) async -> [ListeningPort] {
        var listening: [ListeningPort] = []

        // Check all ports in dev range and common dev ports
        let portsToCheck = Set(Self.devPortRange).union(Self.commonDevPorts)

        for port in portsToCheck.sorted() {
            if !isPortAvailable(port) {
                // Port is in use - try to find which process
                let pid = findProcessUsingPort(port)
                let processName: String?
                if let pid = pid {
                    processName = await processTree.getProcessInfo(pid: pid)?.name
                } else {
                    processName = nil
                }

                let isManaged = allocations[port] != nil

                listening.append(ListeningPort(
                    port: port,
                    address: "localhost",
                    pid: pid,
                    processName: processName,
                    isManaged: isManaged
                ))
            }
        }

        return listening
    }

    /// Find which process is using a port (uses netstat/lsof as fallback)
    /// This is expensive - use sparingly
    private func findProcessUsingPort(_ port: UInt16) -> pid_t? {
        // Note: There's no direct Darwin API to map port -> pid without lsof/netstat
        // We could parse /proc on Linux but on macOS we need external tools
        // For now, return nil - the scan will still show the port is in use

        // Future: Could use private SPI or parse lsof output
        return nil
    }

    // MARK: - Managed Port Tracking

    /// Register a managed process on a port (for process we started)
    /// - Parameters:
    ///   - port: Port number
    ///   - pid: Process ID using the port
    ///   - sessionId: Associated session
    public func registerManagedPort(_ port: UInt16, pid: pid_t, sessionId: Int) {
        let allocation = PortAllocation(port: port, sessionId: sessionId)
        allocations[port] = allocation
        sessionPorts[sessionId] = port
    }

    /// Check if a port is managed by us
    /// - Parameter port: Port to check
    /// - Returns: True if port was allocated by this manager
    public func isManaged(_ port: UInt16) -> Bool {
        allocations[port] != nil
    }

    /// Get session ID for a managed port
    /// - Parameter port: Port to check
    /// - Returns: Session ID or nil if not managed
    public func getSession(for port: UInt16) -> Int? {
        allocations[port]?.sessionId
    }
}

// MARK: - Port Range Extensions

public extension NativePortManager {
    /// Check if port is in the dev server range
    static func isDevPort(_ port: UInt16) -> Bool {
        devPortRange.contains(port) || commonDevPorts.contains(port)
    }

    /// Get count of available ports in dev range
    func availablePortCount() -> Int {
        var count = 0
        for port in Self.devPortRange {
            if allocations[port] == nil && isPortAvailable(port) {
                count += 1
            }
        }
        return count
    }
}
