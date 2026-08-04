import Foundation

/// All possible states the pixel pet can be in.
public enum PetState: String, CaseIterable {
    case idle               // Resting, blinking — Claude at prompt
    case working            // Active output flowing — Claude typing
    case thinking           // Waiting for response — no output yet
    case celebratingShort   // Quick task done — one little jump
    case celebratingMedium  // Normal task done — triple pump + big jump
    case celebratingLong    // Big task done — triple pump + 2 big jumps with landing
    case sleeping           // Terminal unfocused / inactive
    case petted             // User tapped the pet — grooming reaction
}
