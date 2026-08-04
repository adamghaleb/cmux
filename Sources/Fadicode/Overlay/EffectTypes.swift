import Foundation
import AppKit

// MARK: - Lifecycle State

/// The three states of the hub lifecycle. Replaces the 6-phase OverlayPhase.
enum LifecycleState: Equatable {
    case idle
    case active(since: Date)
    case completing(tier: TaskTier, since: Date)

    static func == (lhs: LifecycleState, rhs: LifecycleState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.active, .active): return true
        case (.completing(let lt, _), .completing(let rt, _)): return lt == rt
        default: return false
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var isCompleting: Bool {
        if case .completing = self { return true }
        return false
    }
}

// MARK: - Task Tier

/// Completion tier — maps to OSC 7777 `claude-done --tier` values.
enum TaskTier: String, CaseIterable {
    case short, medium, long, epic

    /// Infer tier from session duration when OSC doesn't provide one.
    static func from(duration: TimeInterval) -> TaskTier {
        switch duration {
        case ..<30:  return .short
        case ..<120: return .medium
        case ..<300: return .long
        default:     return .epic
        }
    }
}

// MARK: - Shader Hint

/// Hints the ShaderDirector about what kind of work Claude is doing,
/// so it can pick an appropriate shader tier floor.
enum ShaderHint: String {
    case planning, coding, creative, researching, conversing
}

// MARK: - Working State Action

/// Action type for OSC 7778 working state signals.
enum WorkingStateAction: String {
    case start, stop
}

// MARK: - Badge Visibility

/// Controls when the project name badge is shown.
enum BadgeVisibility: String {
    case always, hover, never
}

// MARK: - Activity Phase

/// Categorized phase of Claude's current activity, derived from heuristic summary text.
enum ActivityPhase: String, Equatable {
    case reading = "Reading"
    case writing = "Writing"
    case thinking = "Thinking"
    case testing = "Testing"
    case installing = "Installing"
    case building = "Building"
    case searching = "Searching"
    case git = "Git"
    case running = "Running"
    case waiting = "Waiting"
    case other

    /// Human-readable display label.
    var displayName: String {
        switch self {
        case .other: return ""
        default: return rawValue
        }
    }
}

// MARK: - Effect Event

/// Events broadcast over the EffectBus. Each controller subscribes to the events it cares about.
enum EffectEvent {
    case lifecycleActive(LifecycleActivePayload)
    case lifecycleCompleting(LifecycleCompletingPayload)
    case lifecycleIdle
    case activityUpdate(ActivityUpdatePayload)
    case questionDetected(QuestionPayload)
    case questionDismissed
}

// MARK: - Payloads

struct LifecycleActivePayload {
    let hint: ShaderHint?
    let promptText: String?
    let resuming: Bool  // true if re-activating from completing
}

struct LifecycleCompletingPayload {
    let tier: TaskTier
    let duration: TimeInterval
    let terminalContent: String
}

struct ActivityUpdatePayload {
    let summary: String?
    let detail: String?
    let sessionDuration: TimeInterval
}

struct QuestionPayload {
    let question: ClaudeQuestion
}

// MARK: - Activity Category

/// Single source of truth for keyword-based terminal activity classification.
/// Consolidates the heuristic logic previously duplicated in
/// `ClaudeActivitySummary.heuristicSummary()` and `LifecycleManager.classifyActivity()`.
///
/// All terminal-content activity detection flows through `ActivityCategory.classify(_:)`.
/// Each category provides a human-readable `.summary`, a `.shaderHint` for the
/// ShaderDirector, and a `.phase` for breadcrumb display.
enum ActivityCategory: String, CaseIterable {
    case installingDependencies
    case runningTests
    case buildingProject
    case readingFiles
    case writingCode
    case searchingCodebase
    case gitOperations
    case thinking
    case runningCommands
    case working // fallback

    /// Localized human-readable summary string shown in the activity badge and overlay.
    var summary: String {
        switch self {
        case .installingDependencies:
            return String(localized: "activity.heuristic.installingDependencies", defaultValue: "Installing dependencies")
        case .runningTests:
            return String(localized: "activity.heuristic.runningTests", defaultValue: "Running tests")
        case .buildingProject:
            return String(localized: "activity.heuristic.buildingProject", defaultValue: "Building project")
        case .readingFiles:
            return String(localized: "activity.heuristic.readingFiles", defaultValue: "Reading files")
        case .writingCode:
            return String(localized: "activity.heuristic.writingCode", defaultValue: "Writing code")
        case .searchingCodebase:
            return String(localized: "activity.heuristic.searchingCodebase", defaultValue: "Searching codebase")
        case .gitOperations:
            return String(localized: "activity.heuristic.gitOperations", defaultValue: "Git operations")
        case .thinking:
            return String(localized: "activity.heuristic.thinking", defaultValue: "Thinking")
        case .runningCommands:
            return String(localized: "activity.heuristic.runningCommands", defaultValue: "Running commands")
        case .working:
            return String(localized: "activity.heuristic.working", defaultValue: "Working")
        }
    }

    /// Shader hint for the ShaderDirector to pick an appropriate visual tier.
    var shaderHint: ShaderHint? {
        switch self {
        case .thinking: return .planning
        case .writingCode: return .coding
        case .readingFiles, .searchingCodebase: return .researching
        default: return nil
        }
    }

    /// Phase label for breadcrumb display, mapped to the existing ActivityPhase enum.
    var phase: ActivityPhase {
        switch self {
        case .readingFiles: return .reading
        case .writingCode: return .writing
        case .thinking: return .thinking
        case .runningTests: return .testing
        case .installingDependencies: return .installing
        case .buildingProject: return .building
        case .searchingCodebase: return .searching
        case .gitOperations: return .git
        case .runningCommands: return .running
        case .working: return .other
        }
    }

    /// Classify terminal content by scanning the last 2000 characters for keyword patterns.
    /// Returns the best matching category, or `.working` as a fallback.
    static func classify(_ content: String) -> ActivityCategory {
        let lower = content.lowercased()
        let lastChunk = String(lower.suffix(2000))

        if lastChunk.contains("npm install") || lastChunk.contains("yarn add")
            || lastChunk.contains("bun install") || lastChunk.contains("pip install")
        {
            return .installingDependencies
        }
        if lastChunk.contains("running tests") || lastChunk.contains("test suite")
            || lastChunk.contains("jest") || lastChunk.contains("pytest")
            || lastChunk.contains("vitest")
        {
            return .runningTests
        }
        if lastChunk.contains("compiling") || lastChunk.contains("building")
            || lastChunk.contains("webpack") || lastChunk.contains("xcodebuild")
            || lastChunk.contains("zig build")
        {
            return .buildingProject
        }
        if lastChunk.contains("read tool") || lastChunk.contains("reading file") {
            return .readingFiles
        }
        if lastChunk.contains("write tool") || lastChunk.contains("edit tool")
            || lastChunk.contains("writing file")
        {
            return .writingCode
        }
        if lastChunk.contains("searching") || lastChunk.contains("grep tool")
            || lastChunk.contains("glob tool") || lastChunk.contains("ripgrep")
        {
            return .searchingCodebase
        }
        if lastChunk.contains("git commit") || lastChunk.contains("git push")
            || lastChunk.contains("git diff")
        {
            return .gitOperations
        }
        if lastChunk.contains("thinking") || lastChunk.contains("planning") {
            return .thinking
        }
        if lastChunk.contains("bash tool") || lastChunk.contains("running command") {
            return .runningCommands
        }

        return .working
    }
}

// MARK: - Content Detection Helpers

/// Static helpers for detecting Claude Code activity in terminal content.
/// Moved from OverlayStateMachine to avoid dependency on the old monolith.
enum ContentDetection {

    /// Braille spinner chars and other animated glyphs.
    private static let spinnerPattern: NSRegularExpression = {
        // Pattern is a compile-time constant; failure here is a programmer error.
        guard let regex = try? NSRegularExpression(
            pattern: "[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏⣾⣽⣻⢿⡿⣟⣯⣷◐◓◑◒▖▘▝▗⣀⣤⣶⣿⠿⠛⠉⠁◰◳◲◱]",
            options: []
        ) else {
            assertionFailure("Invalid spinnerPattern regex")
            return NSRegularExpression()
        }
        return regex
    }()

    /// Strip spinner/animated chars for stable hashing.
    static func stableContentHash(_ content: String) -> Int {
        let range = NSRange(content.startIndex..., in: content)
        let stripped = spinnerPattern.stringByReplacingMatches(
            in: content, options: [], range: range, withTemplate: ""
        )
        return stripped.hashValue
    }

    /// Strip ANSI escape codes.
    private static let ansiPattern: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(
            pattern: "\\x1B\\[[0-9;]*[A-Za-z]|\\x1B\\].*?(?:\\x07|\\x1B\\\\)",
            options: []
        ) else {
            assertionFailure("Invalid ansiPattern regex")
            return NSRegularExpression()
        }
        return regex
    }()

    static func stripAnsi(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return ansiPattern.stringByReplacingMatches(
            in: text, options: [], range: range, withTemplate: ""
        )
    }

    /// Check if terminal content indicates Claude is waiting for user input.
    static func isWaitingForUser(_ content: String) -> Bool {
        let clean = stripAnsi(content)

        if clean.contains("Allow") && (clean.contains("Yes") || clean.contains("always") || clean.contains("Deny")) { return true }
        if clean.contains("Enter to select") || clean.contains("to navigate") { return true }
        if clean.contains("approve this plan") || clean.contains("Do you want to proceed")
            || clean.contains("Would you like to proceed") { return true }

        let lines = clean.components(separatedBy: "\n")
        let tailLines = lines.suffix(8).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        guard let lastLine = tailLines.last else { return false }

        if lastLine.contains("❯") || lastLine.contains("$") { return true }
        if lastLine.hasPrefix(">") { return true }
        if lastLine.hasSuffix("> ") || lastLine.hasSuffix(": ") { return true }
        if lastLine.contains("(y/n)") || lastLine.contains("(Y/n)") { return true }

        let tail = tailLines.suffix(4).joined(separator: " ")
        if tail.contains("Yes, allow") || tail.contains("No, deny") { return true }
        if tail.contains("Allow once") || tail.contains("Allow always") { return true }

        return false
    }

    /// Broad check: is Claude Code output visible? Used for initial detection.
    static func isClaudeCodePresent(in content: String) -> Bool {
        if isClaudeActivelyWorking(in: content) { return true }

        let lines = content.components(separatedBy: "\n")
        let recent = lines.suffix(60).joined(separator: "\n")

        let toolNames = ["Bash(", "Read(", "Grep(", "Glob(", "Edit(", "Write(",
                         "Task(", "LSP(", "Explore(", "WebFetch(", "WebSearch(",
                         "NotebookEdit(", "Skill(", "AskUser("]
        for tool in toolNames {
            if recent.contains(tool) { return true }
        }

        if recent.contains("Tool:") || recent.contains("tool)") { return true }
        if recent.contains("plan mode") || recent.contains("Plan:") || recent.contains(".claude/plans/") { return true }
        return false
    }

    /// Strict check: is Claude Code *actively* working right now?
    /// Only matches ephemeral indicators that disappear when Claude stops.
    static func isClaudeActivelyWorking(in content: String) -> Bool {
        let lines = content.components(separatedBy: "\n")
        let recent = lines.suffix(30).joined(separator: "\n")

        let spinners: [Character] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏", "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"]
        for s in spinners {
            if recent.contains(s) { return true }
        }

        if recent.contains("Calculating") { return true }
        if recent.contains("more tool use") { return true }
        if recent.contains("ctrl+b to run in back") { return true }
        if recent.contains("Thinking…") || recent.contains("Thinking...") { return true }
        return false
    }

    /// Map summary string to phase category.
    static func phaseFromSummary(_ summary: String) -> ActivityPhase {
        let lower = summary.lowercased()
        if lower.contains("read") { return .reading }
        if lower.contains("writ") || lower.contains("edit") { return .writing }
        if lower.contains("think") || lower.contains("plan") { return .thinking }
        if lower.contains("test") { return .testing }
        if lower.contains("install") { return .installing }
        if lower.contains("build") || lower.contains("compil") { return .building }
        if lower.contains("search") || lower.contains("grep") || lower.contains("glob") { return .searching }
        if lower.contains("git") { return .git }
        if lower.contains("running") || lower.contains("bash") || lower.contains("command") { return .running }
        if lower.contains("wait") { return .waiting }
        return .other
    }

    /// Display label for an activity phase, falling back to truncated summary for `.other`.
    static func phaseDisplayName(_ summary: String) -> String {
        let phase = phaseFromSummary(summary)
        if phase != .other { return phase.displayName }
        if summary.count <= 20 { return summary }
        let trimmed = summary.prefix(20)
        return trimmed.hasSuffix(" ") ? String(trimmed.dropLast()) : String(trimmed)
    }
}
