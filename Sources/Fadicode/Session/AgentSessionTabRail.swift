import Foundation
import Combine

/// Mirrors the deterministic session state onto the tab / sidebar rails.
///
/// # Why this exists (upstream: PR#6798)
///
/// Gate 2's whole point is that "is the agent busy, and does it need me?" has
/// one trustworthy answer. That answer is worth nothing if you have to have the
/// surface on screen to see it. This projects the registry onto the rails the
/// daemon-seam work already built (ADR-0004, orchestrator #26/#27): the
/// per-workspace sidebar status map, using the same `.auto` provenance
/// discipline — the rail is machine-owned, so it never fights a name or colour
/// the user set by hand.
///
/// One entry per workspace, keyed `agent`, showing the highest-priority state
/// across that workspace's surfaces. Needs-input outranks working outranks
/// idle, which is upstream's own selection order.
@MainActor
final class AgentSessionTabRail {

    static let shared = AgentSessionTabRail()

    /// Status key this rail owns. Machine-owned: nothing else may write it.
    static let statusKey = "agent"

    private var cancellable: AnyCancellable?
    /// Workspaces we last wrote an entry into, so a workspace that goes quiet
    /// gets its entry cleared instead of keeping a stale one.
    private var lastWrittenWorkspaceIDs: Set<UUID> = []

    private init() {}

    /// Whether `start()` has taken effect. Read by the DEBUG state readout so a
    /// verification harness can tell "the rail is quiet" from "the rail was
    /// never started".
    var isRunning: Bool { cancellable != nil }

    /// Begins mirroring. Idempotent.
    func start() {
        guard cancellable == nil else { return }
        cancellable = AgentSessionRegistry.shared.$stateBySurfaceID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] states in
                self?.apply(states)
            }
    }

    private func apply(_ states: [UUID: AgentSessionState]) {
        guard let app = AppDelegate.shared else { return }

        // Fold per-surface states up to per-workspace, keeping the most
        // attention-worthy one.
        var byWorkspace: [UUID: (workspace: Workspace, state: AgentSessionState)] = [:]
        for (surfaceID, state) in states {
            guard let resolved = app.workspaceContainingPanel(panelId: surfaceID) else { continue }
            let workspace = resolved.workspace
            if let existing = byWorkspace[workspace.id],
               AgentSessionState.selectionPriority(existing.state)
                <= AgentSessionState.selectionPriority(state) {
                continue
            }
            byWorkspace[workspace.id] = (workspace, state)
        }

        var written: Set<UUID> = []
        for (workspaceID, entry) in byWorkspace {
            guard let descriptor = Self.railEntry(for: entry.state) else { continue }
            entry.workspace.statusEntries[Self.statusKey] = descriptor
            written.insert(workspaceID)
        }

        // Clear rails we own that no longer have anything to say.
        for staleID in lastWrittenWorkspaceIDs.subtracting(written) {
            guard let resolved = byWorkspace[staleID]?.workspace
                    ?? app.tabManagerFor(tabId: staleID)?.tabs.first(where: { $0.id == staleID })
            else { continue }
            resolved.statusEntries.removeValue(forKey: Self.statusKey)
        }
        lastWrittenWorkspaceIDs = written
    }

    /// The rail entry for a state, or nil when the state is not worth a rail.
    ///
    /// `idle` deliberately shows nothing: a rail that is always lit is a rail
    /// nobody reads. `ended` shows nothing for the same reason — the session
    /// is retained in the registry (upstream principle 6), it just stops
    /// claiming attention.
    private static func railEntry(for state: AgentSessionState) -> SidebarStatusEntry? {
        switch state {
        case .needsInput:
            return SidebarStatusEntry(
                key: statusKey,
                value: String(localized: "agent.rail.needsInput", defaultValue: "Needs you"),
                icon: "questionmark.circle.fill",
                color: "#F5A623",
                priority: 100
            )
        case .working:
            return SidebarStatusEntry(
                key: statusKey,
                value: String(localized: "agent.rail.working", defaultValue: "Working"),
                icon: "circle.fill",
                color: "#3DDC84",
                priority: 90
            )
        case .idle, .ended:
            return nil
        }
    }
}
