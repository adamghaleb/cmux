import Foundation

/// Optional status indicator shown alongside the pet.
/// These are text-based since the cat sprite sheet doesn't include icon frames.
public enum PetStatusIndicator: String, CaseIterable {
    case pencil  = "✏️"
    case gear    = "⚙️"
    case heart   = "❤️"
    case zzz     = "💤"

    /// Suggested indicator for each pet state.
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
}
