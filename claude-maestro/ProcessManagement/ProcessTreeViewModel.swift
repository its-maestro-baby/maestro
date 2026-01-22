import Foundation
import Combine

/// View model for the process tree display
@MainActor
public class ProcessTreeViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var rootProcesses: [ProcessNodeViewModel] = []
    @Published public var flatList: [ProcessInfoViewModel] = []
    @Published public var isRefreshing = false
    @Published public var lastRefresh: Date?
    @Published public var filterMode: FilterMode = .maestroOnly
    @Published public var searchText: String = ""
    @Published public var sortOrder: SortOrder = .byPid

    // MARK: - Filter & Sort Options

    public enum FilterMode: String, CaseIterable {
        case all = "All"
        case maestroOnly = "Maestro Only"
        case bySession = "By Session"
    }

    public enum SortOrder: String, CaseIterable {
        case byPid = "PID"
        case byName = "Name"
        case byCpu = "CPU"
        case byMemory = "Memory"
    }

    // MARK: - Dependencies

    private let processTree: ProcessTree
    private let registry: ProcessRegistry
    private var refreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    /// Sessions to filter by (when filterMode is .bySession)
    public var selectedSessions: Set<Int> = []

    // MARK: - Initialization

    public init(processTree: ProcessTree, registry: ProcessRegistry) {
        self.processTree = processTree
        self.registry = registry

        // Set up auto-refresh
        setupAutoRefresh()

        // Set up search debouncing
        $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.refresh() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Refresh

    public func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true

        let currentUid = getuid()

        // Get all processes
        var allProcesses = await processTree.getAllProcesses(includeSystem: filterMode == .all)

        // Apply filters
        allProcesses = await applyFilters(allProcesses)

        // Get managed PIDs for highlighting
        let managedPids = Set(await registry.allPids)

        // Build flat list
        flatList = allProcesses
            .sorted(by: sortComparator)
            .map { info in
                ProcessInfoViewModel(
                    info: info,
                    isManagedByMaestro: managedPids.contains(info.pid),
                    isCurrentUser: info.uid == currentUid
                )
            }

        // Build tree structure
        rootProcesses = buildTreeViewModels(from: allProcesses, managedPids: managedPids)

        lastRefresh = Date()
        isRefreshing = false
    }

    public func startAutoRefresh(interval: TimeInterval = 2.0) {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Actions

    public func killProcess(_ pid: pid_t) async -> Bool {
        Darwin.kill(pid, SIGTERM) == 0
    }

    public func killProcessGroup(_ pgid: pid_t) async -> Bool {
        Darwin.killpg(pgid, SIGTERM) == 0
    }

    public func forceKillProcess(_ pid: pid_t) async -> Bool {
        Darwin.kill(pid, SIGKILL) == 0
    }

    public func toggleExpanded(_ nodeId: pid_t) {
        toggleExpandedRecursive(in: &rootProcesses, nodeId: nodeId)
    }

    public func expandAll() {
        setExpandedRecursive(in: &rootProcesses, expanded: true)
    }

    public func collapseAll() {
        setExpandedRecursive(in: &rootProcesses, expanded: false)
    }

    // MARK: - Private Helpers

    private func setupAutoRefresh() {
        // Start with a 2-second refresh interval
        startAutoRefresh(interval: 2.0)
    }

    private func applyFilters(_ processes: [ProcessInfo]) async -> [ProcessInfo] {
        var filtered = processes

        // Apply filter mode
        switch filterMode {
        case .all:
            break // No filtering
        case .maestroOnly:
            let managedPids = Set(await registry.allPids)
            let managedPgids = Set(processes.filter { managedPids.contains($0.pid) }.map { $0.pgid })

            // Include managed processes and their group members
            filtered = processes.filter {
                managedPids.contains($0.pid) || managedPgids.contains($0.pgid)
            }
        case .bySession:
            if !selectedSessions.isEmpty {
                var sessionPids: Set<pid_t> = []
                for sessionId in selectedSessions {
                    let pids = await registry.getProcesses(forSession: sessionId).map { $0.pid }
                    sessionPids.formUnion(pids)
                }
                filtered = processes.filter { sessionPids.contains($0.pid) }
            }
        }

        // Apply search filter
        if !searchText.isEmpty {
            let lowercased = searchText.lowercased()
            filtered = filtered.filter {
                $0.name.lowercased().contains(lowercased) ||
                ($0.path?.lowercased().contains(lowercased) ?? false) ||
                String($0.pid).contains(searchText)
            }
        }

        return filtered
    }

    private var sortComparator: (ProcessInfo, ProcessInfo) -> Bool {
        switch sortOrder {
        case .byPid:
            return { $0.pid < $1.pid }
        case .byName:
            return { $0.name.lowercased() < $1.name.lowercased() }
        case .byCpu:
            return { $0.pid < $1.pid } // Would need CPU stats
        case .byMemory:
            return { $0.pid < $1.pid } // Would need memory stats
        }
    }

    private func buildTreeViewModels(from processes: [ProcessInfo], managedPids: Set<pid_t>) -> [ProcessNodeViewModel] {
        let byPid = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        let byPpid = Dictionary(grouping: processes) { $0.ppid }

        // Find root processes (parent not in our list)
        let rootPids = processes
            .filter { byPid[$0.ppid] == nil }
            .map { $0.pid }

        func buildNode(pid: pid_t) -> ProcessNodeViewModel? {
            guard let info = byPid[pid] else { return nil }
            let children = (byPpid[pid] ?? []).compactMap { buildNode(pid: $0.pid) }

            return ProcessNodeViewModel(
                info: info,
                children: children,
                isManagedByMaestro: managedPids.contains(pid)
            )
        }

        return rootPids.compactMap { buildNode(pid: $0) }
    }

    private func toggleExpandedRecursive(in nodes: inout [ProcessNodeViewModel], nodeId: pid_t) {
        for i in nodes.indices {
            if nodes[i].id == nodeId {
                nodes[i].isExpanded.toggle()
                return
            }
            toggleExpandedRecursive(in: &nodes[i].children, nodeId: nodeId)
        }
    }

    private func setExpandedRecursive(in nodes: inout [ProcessNodeViewModel], expanded: Bool) {
        for i in nodes.indices {
            nodes[i].isExpanded = expanded
            setExpandedRecursive(in: &nodes[i].children, expanded: expanded)
        }
    }
}

// MARK: - View Model Types

/// View model for a single process info row
public struct ProcessInfoViewModel: Identifiable {
    public let id: pid_t
    public let info: ProcessInfo
    public let isManagedByMaestro: Bool
    public let isCurrentUser: Bool

    public init(info: ProcessInfo, isManagedByMaestro: Bool, isCurrentUser: Bool) {
        self.id = info.pid
        self.info = info
        self.isManagedByMaestro = isManagedByMaestro
        self.isCurrentUser = isCurrentUser
    }

    public var displayName: String {
        info.name.isEmpty ? "unknown" : info.name
    }

    public var shortPath: String? {
        guard let path = info.path else { return nil }
        let components = path.split(separator: "/")
        if components.count > 3 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return path
    }
}

/// View model for a process tree node
public class ProcessNodeViewModel: Identifiable, ObservableObject {
    public let id: pid_t
    public let info: ProcessInfo
    @Published public var children: [ProcessNodeViewModel]
    @Published public var isExpanded: Bool
    public let isManagedByMaestro: Bool

    public init(info: ProcessInfo, children: [ProcessNodeViewModel] = [], isManagedByMaestro: Bool = false, isExpanded: Bool = true) {
        self.id = info.pid
        self.info = info
        self.children = children
        self.isExpanded = isExpanded
        self.isManagedByMaestro = isManagedByMaestro
    }

    public var hasChildren: Bool { !children.isEmpty }
    public var childCount: Int { children.count }

    /// Total count including all descendants
    public var totalCount: Int {
        1 + children.reduce(0) { $0 + $1.totalCount }
    }
}
