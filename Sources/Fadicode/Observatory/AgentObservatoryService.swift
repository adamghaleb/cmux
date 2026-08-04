import Foundation
import Combine

/// Registration info for a terminal panel in the observatory.
private struct PanelRegistration {
    let panelId: UUID
    let workspaceId: UUID
    let workspaceTitle: String
    let workspaceColor: String?
    let projectDirectory: String
    let lifecycleManager: LifecycleManager
    let readContent: (() -> String)?
    var cancellables: Set<AnyCancellable> = []

    // Cached state
    var lastState: LifecycleState = .idle
    var lastLine: String?
    var activitySummary: String?
    var isQuestion: Bool = false
    var activeSince: Date?
}

/// Singleton service that aggregates agent state from all open terminals.
/// Subscribes to each terminal's LifecycleManager via Combine and publishes
/// a unified array of AgentSnapshots.
@MainActor
final class AgentObservatoryService: ObservableObject {
    static let shared = AgentObservatoryService()

    /// All detected agents across all tabs/panes.
    @Published private(set) var agents: [AgentSnapshot] = []

    /// Summary stats.
    @Published private(set) var stats: ObservatoryStats = .empty

    /// Registrations keyed by panel UUID.
    private var registrations: [UUID: PanelRegistration] = [:]

    private init() {}

    // MARK: - Registration

    /// Register a terminal panel for observatory tracking.
    /// Called by FadiCodeOverlayHost when a terminal surface is created.
    func register(
        panelId: UUID,
        workspaceId: UUID,
        workspaceTitle: String,
        workspaceColor: String?,
        projectDirectory: String,
        lifecycleManager: LifecycleManager,
        readContent: (() -> String)?
    ) {
        var reg = PanelRegistration(
            panelId: panelId,
            workspaceId: workspaceId,
            workspaceTitle: workspaceTitle,
            workspaceColor: workspaceColor,
            projectDirectory: projectDirectory,
            lifecycleManager: lifecycleManager,
            readContent: readContent
        )

        // Subscribe to lifecycle state changes
        lifecycleManager.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.handleStateChange(panelId: panelId, state: newState)
            }
            .store(in: &reg.cancellables)

        // Subscribe to question events
        lifecycleManager.bus.onQuestionDetected()
            .sink { [weak self] _ in
                self?.handleQuestionDetected(panelId: panelId)
            }
            .store(in: &reg.cancellables)

        lifecycleManager.bus.onQuestionDismissed()
            .sink { [weak self] in
                self?.handleQuestionDismissed(panelId: panelId)
            }
            .store(in: &reg.cancellables)

        // Subscribe to activity updates
        lifecycleManager.bus.onActivityUpdate()
            .sink { [weak self] payload in
                self?.handleActivityUpdate(panelId: panelId, summary: payload.summary)
            }
            .store(in: &reg.cancellables)

        registrations[panelId] = reg
        rebuildSnapshots()
    }

    /// Unregister a terminal panel when it's destroyed.
    func unregister(panelId: UUID) {
        registrations.removeValue(forKey: panelId)
        rebuildSnapshots()
    }

    /// Update workspace metadata (title, color, directory) for a panel.
    func updateMetadata(
        panelId: UUID,
        workspaceTitle: String? = nil,
        workspaceColor: String? = nil,
        projectDirectory: String? = nil
    ) {
        guard var reg = registrations[panelId] else { return }
        if let title = workspaceTitle {
            reg = PanelRegistration(
                panelId: reg.panelId,
                workspaceId: reg.workspaceId,
                workspaceTitle: title,
                workspaceColor: workspaceColor ?? reg.workspaceColor,
                projectDirectory: projectDirectory ?? reg.projectDirectory,
                lifecycleManager: reg.lifecycleManager,
                readContent: reg.readContent,
                cancellables: reg.cancellables,
                lastState: reg.lastState,
                lastLine: reg.lastLine,
                activitySummary: reg.activitySummary,
                isQuestion: reg.isQuestion,
                activeSince: reg.activeSince
            )
            registrations[panelId] = reg
            rebuildSnapshots()
        }
    }

    /// Force a refresh of all snapshots (e.g., for content re-scan).
    func refresh() {
        for (panelId, reg) in registrations {
            if let readContent = reg.readContent {
                let content = readContent()
                let lastLine = extractLastMeaningfulLine(from: content)
                registrations[panelId]?.lastLine = lastLine
            }
        }
        rebuildSnapshots()
    }

    // MARK: - Event Handlers

    private func handleStateChange(panelId: UUID, state: LifecycleState) {
        guard var reg = registrations[panelId] else { return }
        reg.lastState = state

        switch state {
        case .active(let since):
            reg.activeSince = since
        case .idle:
            reg.activeSince = nil
            reg.activitySummary = nil
        case .completing:
            break
        }

        // Read content for agent detection on state change
        if let readContent = reg.readContent {
            let content = readContent()
            reg.lastLine = extractLastMeaningfulLine(from: content)
        }

        registrations[panelId] = reg
        rebuildSnapshots()
    }

    private func handleQuestionDetected(panelId: UUID) {
        registrations[panelId]?.isQuestion = true
        rebuildSnapshots()
    }

    private func handleQuestionDismissed(panelId: UUID) {
        registrations[panelId]?.isQuestion = false
        rebuildSnapshots()
    }

    private func handleActivityUpdate(panelId: UUID, summary: String?) {
        registrations[panelId]?.activitySummary = summary
        rebuildSnapshots()
    }

    // MARK: - Snapshot Building

    private func rebuildSnapshots() {
        var newAgents: [AgentSnapshot] = []

        for (_, reg) in registrations {
            let agentType: AgentType
            if let readContent = reg.readContent {
                agentType = AgentDetector.detectFromContent(readContent())
            } else {
                agentType = .none
            }

            let agentState: AgentState
            switch reg.lastState {
            case .idle:
                agentState = reg.isQuestion ? .waitingForInput : .idle
            case .active(let since):
                agentState = reg.isQuestion ? .waitingForInput : .active(since: since)
            case .completing(let tier, let since):
                agentState = .completing(tier: tier, since: since)
            }

            let projectName = (reg.projectDirectory as NSString).lastPathComponent

            let snapshot = AgentSnapshot(
                id: reg.panelId,
                workspaceId: reg.workspaceId,
                workspaceTitle: reg.workspaceTitle,
                workspaceColor: reg.workspaceColor,
                projectDirectory: reg.projectDirectory,
                projectName: projectName.isEmpty ? "~" : projectName,
                agentType: agentType,
                state: agentState,
                activeSince: reg.activeSince,
                lastLine: reg.lastLine,
                activitySummary: reg.activitySummary,
                isQuestion: reg.isQuestion
            )
            newAgents.append(snapshot)
        }

        // Sort: active first, then waiting, then completing, then idle
        newAgents.sort { a, b in
            func priority(_ s: AgentState) -> Int {
                switch s {
                case .waitingForInput: return 0
                case .active: return 1
                case .completing: return 2
                case .error: return 3
                case .idle: return 4
                }
            }
            return priority(a.state) < priority(b.state)
        }

        agents = newAgents
        stats = ObservatoryStats(
            totalTerminals: newAgents.count,
            activeAgents: newAgents.filter { $0.state.isActive }.count,
            waitingForInput: newAgents.filter { $0.state.isWaiting }.count,
            completingAgents: newAgents.filter {
                if case .completing = $0.state { return true }
                return false
            }.count,
            idleTerminals: newAgents.filter { $0.state.isIdle }.count
        )
    }

    // MARK: - Helpers

    private func extractLastMeaningfulLine(from content: String) -> String? {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        // Walk backwards to find a non-empty, non-whitespace line
        for line in lines.reversed().prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed.count > 2 {
                return String(trimmed.prefix(120))
            }
        }
        return nil
    }

    /// Group agents by project directory.
    var agentsByProject: [String: [AgentSnapshot]] {
        Dictionary(grouping: agents) { $0.projectName }
    }
}
