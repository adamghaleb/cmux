import Foundation

/// Optional status indicator shown alongside the pet.
///
/// These are SF Symbols, not emoji. Emoji carried a large ascender box that made
/// the glyph float away from the sprite, they ignored the session tint, they
/// could not animate, and they violated the project's own "no emoji as UI" rule.
/// SF Symbols give a fixed vector box, native symbol effects, and correct
/// optical weight at every display size. See fadi-orchestrator#70.
public enum PetStatusIndicator: String, CaseIterable {
    case pencil   = "pencil"
    case gear     = "gearshape.fill"
    case heart    = "heart.fill"
    case zzz      = "zzz"
    /// The agent is blocked on the user. The one state the pet must never be
    /// wrong about, because it is the only one that asks Adam to do something.
    /// upstream: PR#6798 — ChatAgentState.needsAttention
    case question = "questionmark.circle.fill"

    /// The SF Symbol name to render.
    public var systemImage: String { rawValue }

    /// How this indicator should move.
    ///
    /// Kept as data rather than branching in the view: the view applies all
    /// three effects with `isActive:` gates, which keeps the view's type stable
    /// (SwiftUI cannot switch between differently-typed symbol effects inline).
    public enum Motion {
        /// A steady throb — ongoing, unhurried work.
        case pulse
        /// A discrete knock, repeated — activity with a beat to it.
        case bounce
        /// Layers illuminate in sequence. Only meaningful on multi-layer
        /// symbols such as `zzz`.
        case variableColor
    }

    public var motion: Motion {
        switch self {
        case .pencil:   return .bounce
        case .gear:     return .pulse
        case .heart:    return .bounce
        case .zzz:      return .variableColor
        case .question: return .bounce
        }
    }

    /// Spoken description for VoiceOver. The glyph alone conveys nothing.
    public var accessibilityLabel: String {
        switch self {
        case .pencil:
            return String(localized: "accessibility.pet.writing", defaultValue: "Agent is writing")
        case .gear:
            return String(localized: "accessibility.pet.thinking", defaultValue: "Agent is thinking")
        case .heart:
            return String(localized: "accessibility.pet.happy", defaultValue: "Agent finished happily")
        case .zzz:
            return String(localized: "accessibility.pet.sleeping", defaultValue: "Agent session ended")
        case .question:
            return String(localized: "accessibility.pet.needsInput", defaultValue: "Agent needs your input")
        }
    }

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
