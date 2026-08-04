import Foundation

// MARK: - Shader Tuning

struct ShaderTuning: Equatable {
    var speedMultiplier: Double = 1.0
    var contrast: Double = 1.0
    var brightness: Double = 0.0
}

// MARK: - Activity Classification

/// Classifies Claude's current activity into an energy level that maps to a shader tier floor.
enum ActivityClass: Int, Comparable {
    case idle = 0
    case thinking = 1   // Thinking, planning
    case reading = 2    // Reading files, searching codebase
    case writing = 3    // Writing code, editing
    case executing = 4  // Building, testing, running commands, installing, git

    static func < (lhs: ActivityClass, rhs: ActivityClass) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The minimum shader tier this activity class demands.
    var baseTier: ShaderTier {
        switch self {
        case .idle:      return .ambient
        case .thinking:  return .ambient
        case .reading:   return .flowing
        case .writing:   return .deep
        case .executing: return .highEnergy
        }
    }

    /// Human-readable name for debug HUD.
    var debugName: String {
        switch self {
        case .idle: return "idle"
        case .thinking: return "thinking"
        case .reading: return "reading"
        case .writing: return "writing"
        case .executing: return "executing"
        }
    }

    /// Classify an activity summary string (from heuristicSummary or LLM) into an activity class.
    static func classify(_ summary: String?) -> ActivityClass {
        guard let summary else { return .idle }
        let lower = summary.lowercased()

        if lower.contains("build") || lower.contains("compil") { return .executing }
        if lower.contains("test") { return .executing }
        if lower.contains("running") || lower.contains("command") || lower.contains("bash") { return .executing }
        if lower.contains("install") { return .executing }
        if lower.contains("git") { return .executing }
        if lower.contains("writ") || lower.contains("edit") { return .writing }
        if lower.contains("read") { return .reading }
        if lower.contains("search") || lower.contains("grep") || lower.contains("glob") { return .reading }
        if lower.contains("think") || lower.contains("plan") { return .thinking }
        return .idle
    }
}

// MARK: - Shader Tier

enum ShaderTier: Int, CaseIterable, Comparable {
    case ambient = 0, flowing = 1, deep = 2, highEnergy = 3

    static func < (lhs: ShaderTier, rhs: ShaderTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var lower: ShaderTier? {
        ShaderTier(rawValue: rawValue - 1)
    }

    /// Human-readable name for debug HUD.
    var debugName: String {
        switch self {
        case .ambient: return "ambient"
        case .flowing: return "flowing"
        case .deep: return "deep"
        case .highEnergy: return "high"
        }
    }
}

// MARK: - Shader Catalog

/// Shared catalog of profiled shaders. Stateless — all session state lives in ShaderSession.
struct ShaderCatalog {
    struct ProfiledShader {
        let mode: Int
        let name: String
        let funcName: String
        let tier: ShaderTier
        let speedMultiplier: Double
        let contrast: Double
        let brightness: Double
    }

    static let shaders: [ProfiledShader] = [
        // Ambient (low energy)
        ProfiledShader(mode: 2,  name: "Point Cloud",         funcName: "pointCloudEffect",         tier: .ambient,    speedMultiplier: 4.0,  contrast: 1.9,  brightness: -0.1),
        ProfiledShader(mode: 16, name: "Sacred Geometry",     funcName: "sacredGeometryEffect",     tier: .ambient,    speedMultiplier: 1.0,  contrast: 1.5,  brightness: 0.6),
        ProfiledShader(mode: 19, name: "Moire",               funcName: "moireEffect",               tier: .ambient,    speedMultiplier: 2.8,  contrast: 2.8,  brightness: -0.25),
        ProfiledShader(mode: 28, name: "Cosmic Web",          funcName: "cosmicWebEffect",          tier: .ambient,    speedMultiplier: 2.6,  contrast: 3.0,  brightness: -0.05),
        ProfiledShader(mode: 31, name: "Nebula Cloud",        funcName: "nebulaCloudEffect",        tier: .ambient,    speedMultiplier: 2.8,  contrast: 1.7,  brightness: 0.7),
        ProfiledShader(mode: 34, name: "Entity Presence",     funcName: "entityPresenceEffect",     tier: .ambient,    speedMultiplier: 4.4,  contrast: 2.1,  brightness: 0.8),
        ProfiledShader(mode: 46, name: "String Theory",       funcName: "stringTheoryEffect",       tier: .ambient,    speedMultiplier: 5.0,  contrast: 0.0,  brightness: 1.0),
        ProfiledShader(mode: 58, name: "Dream Catcher",       funcName: "dreamCatcherEffect",       tier: .ambient,    speedMultiplier: 3.0,  contrast: 0.0,  brightness: 1.0),

        // Flowing (medium energy, lower coverage)
        ProfiledShader(mode: 13, name: "Spiral Galaxy",       funcName: "spiralGalaxyEffect",       tier: .flowing,    speedMultiplier: 4.3,  contrast: 2.6,  brightness: -0.2),
        ProfiledShader(mode: 15, name: "Lava Lamp",           funcName: "lavaLampEffect",           tier: .flowing,    speedMultiplier: 2.6,  contrast: 2.5,  brightness: -0.15),
        ProfiledShader(mode: 18, name: "Fractal Rings",       funcName: "fractalRingsEffect",       tier: .flowing,    speedMultiplier: 5.0,  contrast: 2.4,  brightness: 0.05),
        ProfiledShader(mode: 20, name: "Chrysanthemum",       funcName: "chrysanthemumEffect",       tier: .flowing,    speedMultiplier: 2.8,  contrast: 1.7,  brightness: -0.05),
        ProfiledShader(mode: 25, name: "Ego Dissolution",     funcName: "egoDissolutionEffect",     tier: .flowing,    speedMultiplier: 4.7,  contrast: 1.4,  brightness: 0.5),
        ProfiledShader(mode: 32, name: "DNA Helix",           funcName: "dnaHelixEffect",           tier: .flowing,    speedMultiplier: 0.5,  contrast: 2.1,  brightness: 0.4),
        ProfiledShader(mode: 39, name: "Celestial Clockwork", funcName: "celestialClockworkEffect", tier: .flowing,    speedMultiplier: 5.0,  contrast: 3.0,  brightness: 1.0),
        ProfiledShader(mode: 12, name: "Voronoi",             funcName: "voronoiEffect",             tier: .flowing,    speedMultiplier: 2.8,  contrast: 1.0,  brightness: -0.35),

        // Deep Processing (medium energy, high coverage)
        ProfiledShader(mode: 26, name: "Folding Dimensions",  funcName: "foldingDimensionsEffect",  tier: .deep,       speedMultiplier: 3.0,  contrast: 2.6,  brightness: 0.6),
        ProfiledShader(mode: 27, name: "Cymatics",            funcName: "cymaticsEffect",            tier: .deep,       speedMultiplier: 2.9,  contrast: 3.0,  brightness: 0.7),
        ProfiledShader(mode: 30, name: "Interference Crystal", funcName: "interferenceCrystalEffect", tier: .deep,      speedMultiplier: 2.1,  contrast: 1.0,  brightness: 0.8),
        ProfiledShader(mode: 36, name: "Quantum Field",       funcName: "quantumFieldEffect",       tier: .deep,       speedMultiplier: 3.4,  contrast: 1.9,  brightness: 0.4),
        ProfiledShader(mode: 42, name: "Resonance",           funcName: "resonanceEffect",           tier: .deep,       speedMultiplier: 3.9,  contrast: 1.8,  brightness: 1.0),
        ProfiledShader(mode: 45, name: "Infinite Zoom",       funcName: "infiniteZoomEffect",       tier: .deep,       speedMultiplier: 1.4,  contrast: 3.0,  brightness: 1.0),
        ProfiledShader(mode: 52, name: "Weaver's Loom",       funcName: "weaversLoomEffect",         tier: .deep,       speedMultiplier: 5.0,  contrast: 2.8,  brightness: 0.95),
        ProfiledShader(mode: 54, name: "Resonance Chamber",   funcName: "resonanceChamberEffect",   tier: .deep,       speedMultiplier: 1.5,  contrast: 3.0,  brightness: 1.0),

        // High Energy
        ProfiledShader(mode: 6,  name: "Light Grid",          funcName: "lightGridEffect",          tier: .highEnergy, speedMultiplier: 1.9,  contrast: 3.0,  brightness: -0.35),
        ProfiledShader(mode: 7,  name: "Sinebow",             funcName: "sinebowEffect",             tier: .highEnergy, speedMultiplier: 3.8,  contrast: 2.0,  brightness: 0.75),
        ProfiledShader(mode: 10, name: "Kaleidoscope",        funcName: "kaleidoscopeEffect",       tier: .highEnergy, speedMultiplier: 2.8,  contrast: 2.0,  brightness: 0.6),
        ProfiledShader(mode: 21, name: "Machine Elves",       funcName: "machineElvesEffect",       tier: .highEnergy, speedMultiplier: 1.9,  contrast: 1.4,  brightness: 0.45),
        ProfiledShader(mode: 37, name: "Geometric Alchemy",   funcName: "geometricAlchemyEffect",   tier: .highEnergy, speedMultiplier: 3.7,  contrast: 3.0,  brightness: 1.0),
    ]

    /// Pick a random shader from the given tier, avoiding recent modes.
    static func pickForTier(_ tier: ShaderTier, avoiding recentModes: [Int]) -> ProfiledShader {
        var candidates = shaders.filter { $0.tier == tier && !recentModes.contains($0.mode) }
        if candidates.isEmpty {
            candidates = shaders.filter { $0.tier == tier }
        }
        if candidates.isEmpty {
            candidates = shaders.filter { !recentModes.contains($0.mode) }
        }
        if candidates.isEmpty {
            candidates = shaders
        }
        return candidates.randomElement()!
    }

    /// Weighted random pick (for OSC 7778 manual override).
    static func pickRandom(avoiding recentModes: [Int]) -> ProfiledShader {
        let weights: [(ShaderTier, Int)] = [
            (.ambient, 15), (.flowing, 35), (.deep, 35), (.highEnergy, 15),
        ]
        let total = weights.reduce(0) { $0 + $1.1 }
        var roll = Int.random(in: 0..<total)
        var tier: ShaderTier = .flowing
        for (t, w) in weights {
            roll -= w
            if roll < 0 { tier = t; break }
        }
        return pickForTier(tier, avoiding: recentModes)
    }
}

// MARK: - Shader Session (per-surface)

/// Per-surface shader session state. Each terminal panel owns its own instance.
class ShaderSession {
    /// When this session started (nil = inactive).
    private(set) var sessionStartTime: Date?

    /// The current tier being displayed.
    private(set) var currentTier: ShaderTier = .ambient

    /// When the last intra-tier shader cycle happened.
    private(set) var lastCycleTime: Date = .distantPast

    /// Randomized interval (12–18s) until the next intra-tier shader swap.
    private(set) var nextCycleInterval: TimeInterval = 15.0

    /// Last 3 modes picked — avoid repeats.
    private var recentModes: [Int] = []

    var isSessionActive: Bool { sessionStartTime != nil }

    /// Returns true if the summary matches a specific Claude activity (not generic "Working" or nil).
    func isSpecificActivity(_ summary: String?) -> Bool {
        guard let summary else { return false }
        return ActivityClass.classify(summary) != .idle
    }

    // MARK: Session Lifecycle

    func startSession(summary: String? = nil) -> ShaderCatalog.ProfiledShader {
        sessionStartTime = Date()
        currentTier = .ambient
        lastCycleTime = Date()
        nextCycleInterval = .random(in: 12...18)

        let activityTier = ActivityClass.classify(summary).baseTier
        if activityTier > currentTier {
            currentTier = activityTier
        }

        return pickAndTrack(currentTier)
    }

    func updateActivity(summary: String?, sessionDuration: TimeInterval) -> ShaderCatalog.ProfiledShader? {
        guard isSessionActive else { return nil }

        let targetTier = computeTargetTier(summary: summary, sessionDuration: sessionDuration)

        if targetTier > currentTier {
            currentTier = targetTier
            lastCycleTime = Date()
            nextCycleInterval = .random(in: 12...18)
            return pickAndTrack(currentTier)
        }

        let elapsed = Date().timeIntervalSince(lastCycleTime)
        if elapsed >= nextCycleInterval {
            lastCycleTime = Date()
            nextCycleInterval = .random(in: 12...18)
            return pickAndTrack(currentTier)
        }

        return nil
    }

    func endSession() {
        sessionStartTime = nil
        currentTier = .ambient
        lastCycleTime = .distantPast
        nextCycleInterval = 15.0
    }

    /// Weighted random pick for manual override (OSC 7778).
    func pickRandom() -> ShaderCatalog.ProfiledShader {
        return pickAndTrack(nil)
    }

    // MARK: Debug

    /// Force a specific tier (debug HUD).
    func debugSetTier(_ tier: ShaderTier) {
        currentTier = tier
        lastCycleTime = Date()
        nextCycleInterval = .random(in: 12...18)
        if sessionStartTime == nil {
            sessionStartTime = Date()
        }
    }

    // MARK: Internal

    private func computeTargetTier(summary: String?, sessionDuration: TimeInterval) -> ShaderTier {
        let timeTier: ShaderTier
        switch sessionDuration {
        case ..<10:  timeTier = .ambient
        case ..<30:  timeTier = .flowing
        case ..<60:  timeTier = .deep
        default:     timeTier = .highEnergy
        }
        let activityTier = ActivityClass.classify(summary).baseTier
        return max(timeTier, activityTier)
    }

    private func pickAndTrack(_ tier: ShaderTier?) -> ShaderCatalog.ProfiledShader {
        let picked: ShaderCatalog.ProfiledShader
        if let tier {
            picked = ShaderCatalog.pickForTier(tier, avoiding: recentModes)
        } else {
            picked = ShaderCatalog.pickRandom(avoiding: recentModes)
        }
        recentModes.append(picked.mode)
        if recentModes.count > 3 { recentModes.removeFirst() }
        return picked
    }
}
