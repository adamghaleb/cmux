import Foundation

// upstream: PR#6798 — Packages/Shared/CmuxAgentChat/Sources/CmuxAgentChat/Model/ChatAgentState.swift
//
// Upstream's live-activity model for an agent session, transcribed verbatim in
// shape. Four states, no more:
//
//   idle            — the agent is alive and waiting for the user.
//   working(since:) — the agent has been doing something since that instant.
//   needsInput(_:)  — the agent is blocked on the user (question or permission).
//   ended           — the agent process is gone.
//
// Deliberately NOT invented here: a separate "thinking" state. The fork's pet
// had `working` and `thinking` as distinct states inferred from terminal text
// (spinner glyphs = thinking, output flowing = working). Upstream models one
// `working`, because no deterministic signal distinguishes the two — the
// distinction was an artifact of the text heuristic. The pet keeps its
// `thinking` SPRITE (see PetStatusIndicator), driven off `working` + the
// activity summary, but the session STATE has four values, upstream's four.
//
// `ended` is retained, never deleted: upstream principle 6. A dead session
// stays visible and simply stops accepting input.
public enum AgentSessionState: Sendable, Equatable {
    /// The agent is idle, awaiting input.
    case idle
    /// The agent has been working since the associated time.
    case working(since: Date)
    /// The agent is blocked on the user (question or permission) since the
    /// associated time.
    case needsInput(since: Date)
    /// The agent process ended.
    case ended

    /// Whether the user's attention is required.
    /// upstream: PR#6798 — ChatAgentState.needsAttention
    public var needsAttention: Bool {
        if case .needsInput = self { return true }
        return false
    }

    public var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    public var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    public var isEnded: Bool {
        if case .ended = self { return true }
        return false
    }

    /// When the current non-idle phase began, for elapsed-time display.
    public var since: Date? {
        switch self {
        case .working(let since), .needsInput(let since): return since
        case .idle, .ended: return nil
        }
    }

    /// Compact label for logs and the debug HUD; strips the associated value.
    /// upstream: PR#6798 — AgentChatSessionRegistry.stateLabel
    public var label: String {
        switch self {
        case .idle: return "idle"
        case .working: return "working"
        case .needsInput: return "needsInput"
        case .ended: return "ended"
        }
    }

    /// Selection rank; lower sorts first. Needs-input outranks working so the
    /// session that is actually blocked on the user surfaces first, and a dead
    /// session never shadows a live one.
    /// upstream: PR#6798 — ChatSessionDescriptor.selectionPriority
    public static func selectionPriority(_ state: AgentSessionState) -> Int {
        switch state {
        case .needsInput: return 0
        case .working: return 1
        case .idle: return 2
        case .ended: return 3
        }
    }
}

/// Which agent runtime owns a session.
/// upstream: PR#6798 — CmuxAgentChat/Model/ChatAgentKind.swift (narrowed: this
/// fork only ever binds Claude Code today, but the wire carries `_source` and
/// the registry must not lose it).
public enum AgentKind: String, Sendable, Equatable {
    case claude
    case codex
    case unknown

    public init(source: String) {
        switch source.lowercased() {
        case "claude", "claude-code", "claudecode": self = .claude
        case "codex": self = .codex
        default: self = .unknown
        }
    }
}
