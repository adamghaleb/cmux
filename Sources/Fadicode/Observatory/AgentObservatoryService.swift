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
    var activeSince: Date?
}

/// Singleton service that aggregates agent state from all open terminals.
///
/// # Gate 2 (upstream: PR#6798)
///
/// The observatory's per-agent state used to be a blend of the overlay's
/// text-derived lifecycle phase and an `isQuestion` flag set by scraping the
/// screen for "Enter to select". Both are gone. `AgentSessionRegistry` is the
/// authority: `working` / `needsInput` / `idle` / `ended` come straight from
/// it, and only the completion CELEBRATION phase (a fork-specific visual) is
/// still read off the overlay lifecycle.
@MainActor
final class AgentObservatoryService: ObservableObject {
    static let shared = AgentObservatoryService()

    /// All detected agents across all tabs/panes.
    @Published private(set) var agents: [AgentSnapshot] = []

    /// Summary stats.
    @Published private(set) var stats: ObservatoryStats = .empty

    /// Registrations keyed by panel UUID.
    private var registrations: [UUID: PanelRegistration] = [:]

    /// Subscription to the deterministic session authority.
    /// upstream: PR#6798
    private var registryCancellable: AnyCancellable?

    private init() {
        registryCancellable = AgentSessionRegistry.shared.$stateBySurfaceID
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildSnapshots()
            }
    }

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

        // Question events no longer feed STATE — `needsInput` is a session
        // state owned by AgentSessionRegistry, and the pill is presentation.
        // upstream: PR#6798

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

    private func handleActivityUpdate(panelId: UUID, summary: String?) {
        registrations[panelId]?.activitySummary = summary
        rebuildSnapshots()
    }

    // MARK: - Snapshot Building

    private func rebuildSnapshots() {
        var newAgents: [AgentSnapshot] = []

        let registry = AgentSessionRegistry.shared

        for (_, reg) in registrations {
            // Identity and state both come from the deterministic binding.
            // upstream: PR#6798
            let agentType = AgentDetector.detect(surfaceID: reg.panelId)
            let sessionState = registry.state(surfaceID: reg.panelId)

            let agentState: AgentState
            if case .completing(let tier, let since) = reg.lastState {
                // The celebration window is a fork visual, not a session state,
                // and it outlives the session's return to idle by design.
                agentState = .completing(tier: tier, since: since)
            } else {
                switch sessionState {
                case .needsInput:
                    agentState = .waitingForInput
                case .working(let since):
                    agentState = .active(since: since)
                case .idle, .ended, nil:
                    agentState = .idle
                }
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
                isQuestion: sessionState?.needsAttention ?? false
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
