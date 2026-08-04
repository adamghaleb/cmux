import Foundation

/// Defines which frames in a sprite sheet correspond to each pet state.
public struct PetAnimation {
    /// The range of frame indices for this animation.
    public let frames: [Int]
    /// Frames per second for playback.
    public let fps: Double
    /// Whether the animation loops or plays once.
    public let loops: Bool

    public init(frames: [Int], fps: Double = 6, loops: Bool = true) {
        self.frames = frames
        self.fps = fps
        self.loops = loops
    }
}

/// Maps pet states to their animations. Configure this based on your sprite sheet layout.
public struct PetAnimationSet {
    public var animations: [PetState: PetAnimation]

    public init(animations: [PetState: PetAnimation]) {
        self.animations = animations
    }

    public func animation(for state: PetState) -> PetAnimation? {
        animations[state]
    }

    /// Animation set for the Elthen 32x32 cat sprite sheet (256x320, 8 columns x 10 rows).
    /// Row 0: sitting idle (blink)    Row 1: sitting idle variant
    /// Row 2: grooming (licking)      Row 3: cleaning/stretching
    /// Row 4: running (8 frames)      Row 5: lying down / falling asleep
    /// Row 6: sleeping flat           Row 7: walking alert (6 frames)
    /// Row 8: jumping + scared        Row 9: walking steady (8 frames)
    public static let defaultSet = PetAnimationSet(animations: [
        .idle:        PetAnimation(frames: [0,1,2,3, 8,9,10,11], fps: 4),
        .working:     PetAnimation(frames: Array(32..<40), fps: 8),
        .thinking:    PetAnimation(frames: Array(56..<62), fps: 4),
        // Short: one cute jump + landing
        .celebratingShort: PetAnimation(frames: [
            64,65,66,67, 68,69,
        ], fps: 8, loops: false),
        // Medium: triple pump → big jump + landing
        .celebratingMedium: PetAnimation(frames: [
            68,69,70, 68,69,70, 68,69,70,
            64,65,66,67, 68,69,
        ], fps: 8, loops: false),
        // Long: triple pump → 2 big jumps with landing
        .celebratingLong: PetAnimation(frames: [
            68,69,70, 68,69,70, 68,69,70,
            64,65,66,67, 68,69,
            64,65,66,67, 68,69,
        ], fps: 8, loops: false),
        .sleeping:    PetAnimation(frames: Array(48..<52), fps: 2),
        // Petted: grooming/licking reaction when user taps the pet
        .petted:      PetAnimation(frames: Array(16..<24), fps: 8, loops: false),
    ])
}
