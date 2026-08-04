import Foundation

/// Optional status indicator shown alongside the pet.
/// These are text-based since the cat sprite sheet doesn't include icon frames.
public enum PetStatusIndicator: String, CaseIterable {
    case pencil  = "✏️"
    case gear    = "⚙️"
    case heart   = "❤️"
    case zzz     = "💤"
    /// The agent is blocked on the user. The one state the pet must never be
    /// wrong about, because it is the only one that asks Adam to do something.
    /// upstream: PR#6798 — ChatAgentState.needsAttention
    case question = "❓"

    /// Suggested indicator for each pet state.
    ///
    /// Sprite-level fallback, used when no agent is bound to the surface.
    /// Prefer ``indicator(for:petState:)``: the pet's SPRITE distinguishes
    /// working from thinking for looks, but the session's real state has four
    /// values and `needsInput` has no sprite of its own.
    public static func indicator(for state: PetState) -> PetStatusIndicator? {
        switch state {
        case .idle:                                              return nil
        case .working:                                           return .pencil
        case .thinking:                                          return .gear
        case .celebratingShort, .celebratingMedium, .celebratingLong: return .heart
        case .petted:                                            return .heart
        case .sleeping:                                          return .zzz
        }
    }

    /// Indicator for the authoritative session state.
    ///
    /// This is the mapping that matters. It is a pure function of what the
    /// agent's own hooks, its process, and its transcript said — never of what
    /// the terminal happened to be printing.
    /// upstream: PR#6798 — ChatAgentState
    ///
    /// - Parameters:
    ///   - agentState: The surface's live session state, or nil when no agent
    ///     is bound.
    ///   - petState: The pet's current sprite state, used only to pick between
    ///     the two working glyphs and to keep celebration hearts.
    /// - Returns: The glyph to show, or nil for "show nothing".
    public static func indicator(
        for agentState: AgentSessionState?,
        petState: PetState
    ) -> PetStatusIndicator? {
        guard let agentState else { return indicator(for: petState) }
        switch agentState {
        case .needsInput:
            return .question
        case .working:
            // The sprite decides the flavour: the animator swings between
            // working and thinking for liveliness. Neither is a claim about
            // the session — the session is simply `working`.
            return petState == .thinking ? .gear : .pencil
        case .idle:
            switch petState {
            case .celebratingShort, .celebratingMedium, .celebratingLong, .petted:
                return .heart
            default:
                return nil
            }
        case .ended:
            return .zzz
        }
    }
}
