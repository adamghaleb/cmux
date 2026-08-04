import Foundation

/// Resolves which agent runtime owns a surface.
///
/// # Gate 2 rewrite (upstream: PR#6798)
///
/// This used to answer the question by scanning the last 3000 characters of
/// terminal output for braille spinners, tool banners and box-drawing glyphs.
/// It reported "Claude Code" for any terminal that had ever printed a rounded
/// box corner, and "Terminal" for a live Claude session that happened to be
/// quiet. Upstream deleted every detector of that class; this now reads the
/// deterministic binding instead — the same `env -> process -> surface` chain
/// that decides presence.
///
/// The old entry point `detectFromContent(_:)` is deleted. There is nothing in
/// terminal text that can answer this question correctly.
struct AgentDetector {

    /// The agent runtime bound to a surface, from the session registry.
    ///
    /// - Parameter surfaceID: The surface (panel) UUID.
    /// - Returns: The detected agent, or `.none` when nothing is bound.
    @MainActor
    static func detect(surfaceID: UUID) -> AgentType {
        guard let record = AgentSessionRegistry.shared.record(surfaceID: surfaceID) else {
            // No session record yet, but the presence probe may already have
            // seen the process — report the agent, not "Terminal".
            return AgentPresence.shared.isAgentLive(surfaceID: surfaceID) ? .claudeCode : .none
        }
        if record.state.isEnded { return .none }
        return type(for: record.agentKind)
    }

    private static func type(for kind: AgentKind) -> AgentType {
        switch kind {
        case .claude: return .claudeCode
        case .codex: return .codex
        case .unknown: return .unknown
        }
    }
}
