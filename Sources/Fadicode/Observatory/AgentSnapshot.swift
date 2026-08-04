import Foundation

// MARK: - Agent Types

/// Type of AI agent detected in a terminal.
enum AgentType: String, Sendable {
    case claudeCode = "Claude Code"
    case codex = "Codex"
    case aider = "Aider"
    case opencode = "OpenCode"
    case unknown = "Agent"
    case none = "Terminal"
}

/// Current state of an agent in a terminal.
enum AgentState: Equatable, Sendable {
    case idle
    case active(since: Date)
    case completing(tier: TaskTier, since: Date)
    case waitingForInput
    case error

    static func == (lhs: AgentState, rhs: AgentState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.active, .active): return true
        case (.completing(let lt, _), .completing(let rt, _)): return lt == rt
        case (.waitingForInput, .waitingForInput): return true
        case (.error, .error): return true
        default: return false
        }
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var isWaiting: Bool {
        if case .waitingForInput = self { return true }
        return false
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }
}

// MARK: - Agent Snapshot

/// A point-in-time snapshot of an agent running in a terminal panel.
struct AgentSnapshot: Identifiable, Sendable {
    let id: UUID                    // panel UUID
    let workspaceId: UUID
    let workspaceTitle: String
    let workspaceColor: String?     // hex color from workspace badge
    let projectDirectory: String
    let projectName: String         // last path component

    // Agent detection
    let agentType: AgentType
    let state: AgentState
    let activeSince: Date?

    // Terminal content hints
    let lastLine: String?
    let activitySummary: String?
    let isQuestion: Bool

    /// Duration string for active/completing states.
    var durationString: String? {
        let since: Date?
        switch state {
        case .active(let d): since = d
        case .completing(_, let d): since = d
        default: since = activeSince
        }
        guard let start = since else { return nil }
        let interval = Date().timeIntervalSince(start)
        if interval < 60 { return "\(Int(interval))s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        return "\(Int(interval / 3600))h \(Int((interval.truncatingRemainder(dividingBy: 3600)) / 60))m"
    }
}

// MARK: - Observatory Stats

/// Aggregate stats across all observed terminals.
struct ObservatoryStats: Equatable, Sendable {
    let totalTerminals: Int
    let activeAgents: Int
    let waitingForInput: Int
    let completingAgents: Int
    let idleTerminals: Int

    static let empty = ObservatoryStats(
        totalTerminals: 0,
        activeAgents: 0,
        waitingForInput: 0,
        completingAgents: 0,
        idleTerminals: 0
    )
}
