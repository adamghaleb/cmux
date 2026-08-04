import Foundation

// upstream: PR#6798 — Sources/Mobile/AgentChat/AgentChatSessionRecord.swift
//
// One agent session the app knows about: hook-derived identity, surface
// binding, transcript location, live state, and a monotonic version.
//
// Narrowed vs upstream: no title, no hook-store `Entry` adoption helpers (this
// fork has no on-disk hook store — the socket is the only ingress), no chat
// descriptor. Everything that carries STATE semantics is transcribed as-is.
struct AgentSessionRecord: Sendable, Equatable {

    /// The agent's own session identifier, or a synthesized pending id for a
    /// session discovered before any hook fired.
    let sessionID: String

    /// Which agent runtime owns the session.
    let agentKind: AgentKind

    /// Hosting surface UUID string — the binding key. Upstream principle 7:
    /// bind on a durable surface identity, never the volatile workspace id.
    var surfaceID: String?

    /// Owning workspace UUID string. A mutable ATTRIBUTE, never the identity.
    var workspaceID: String?

    /// The session's working directory, when known.
    var workingDirectory: String?

    /// Absolute transcript JSONL path, as REPORTED by the agent. Never guessed
    /// from a newest-file-by-mtime scan — that was the heuristic upstream
    /// deleted.
    var transcriptPath: String?

    /// Live activity state.
    var state: AgentSessionState

    /// Whether `state` has been established by the agent's hook lifecycle.
    /// Process-table discovery proves presence and identity, but not idleness —
    /// so an observed-only session must not claim authority over a hook-derived
    /// state.
    /// upstream: PR#6798 — AgentChatSessionRecord.hasHookLifecycleState
    var hasHookLifecycleState: Bool = false

    /// When the record entered `.ended`. Best-effort process observations
    /// sampled before this instant must not revive it after a hook or the exit
    /// watcher ended it.
    /// upstream: PR#6798 — AgentChatSessionRecord.endedAt
    var endedAt: Date?

    /// Timestamp of the most recent hook or transcript activity.
    var lastActivityAt: Date

    /// The agent process id. Owned by whatever set it last; the exit watcher
    /// is re-armed on every change.
    var pid: Int?

    /// Monotonic revision stamped by the registry on every change. Consumers
    /// reconcile best-effort pushes against authoritative reads by this number.
    /// Owned by the registry; mutators never set it directly.
    var version: Int = 0

    init(
        sessionID: String,
        agentKind: AgentKind,
        surfaceID: String? = nil,
        workspaceID: String? = nil,
        workingDirectory: String? = nil,
        transcriptPath: String? = nil,
        state: AgentSessionState = .idle,
        hasHookLifecycleState: Bool = false,
        endedAt: Date? = nil,
        lastActivityAt: Date = Date(),
        pid: Int? = nil,
        version: Int = 0
    ) {
        self.sessionID = sessionID
        self.agentKind = agentKind
        self.surfaceID = surfaceID
        self.workspaceID = workspaceID
        self.workingDirectory = workingDirectory
        self.transcriptPath = transcriptPath
        self.state = state
        self.hasHookLifecycleState = hasHookLifecycleState
        self.endedAt = endedAt
        self.lastActivityAt = lastActivityAt
        self.pid = pid
        self.version = version
    }

    /// Applies a state the agent's own hook lifecycle established. This is the
    /// authoritative path; it outranks every observation.
    /// upstream: PR#6798 — AgentChatSessionRecord.setHookLifecycleState
    mutating func setHookLifecycleState(_ nextState: AgentSessionState) {
        state = nextState
        hasHookLifecycleState = true
    }

    /// The process table proved the agent is alive but said nothing about what
    /// it is doing, so idle is a floor, not an assertion.
    /// upstream: PR#6798 — AgentChatSessionRecord.setProcessObservedIdle
    mutating func setProcessObservedIdle() {
        state = .idle
        hasHookLifecycleState = false
    }

    /// The transcript showed a completed assistant turn while we still believed
    /// the agent was working. Corrects a stuck `working`; a later hook remains
    /// authoritative and can move it back.
    /// upstream: PR#6798 — AgentChatSessionRecord.setTranscriptObservedIdle
    mutating func setTranscriptObservedIdle() {
        state = .idle
        hasHookLifecycleState = false
    }

    /// The surface UUID, when the binding key parses.
    var surfaceUUID: UUID? {
        guard let surfaceID else { return nil }
        return UUID(uuidString: surfaceID)
    }
}
