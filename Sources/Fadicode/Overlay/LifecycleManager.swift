import Foundation
import Combine

/// Hub of the hub-and-spoke architecture. Manages 3 lifecycle states
/// and emits events via the EffectBus. Content polling lives here.
final class LifecycleManager: ObservableObject {

    @Published private(set) var state: LifecycleState = .idle

    let bus: EffectBus

    /// Closure to read terminal content — set by FadiCodeOverlaySystem.
    var readContent: (() -> String)?

    // Content hashing for change detection
    private var lastContentHash: Int = 0
    private var lastRawContentHash: Int = 0
    private var lastContentLength: Int = 0

    // Activity tracking
    private(set) var activityStartTime: Date?
    private(set) var activitySummary: String?

    // Safety timers
    private var activeTimeoutWork: DispatchWorkItem?
    private var completingTimeoutWork: DispatchWorkItem?

    // Auto mode (disable from debug HUD)
    var autoMode: Bool = true

    // Debounce rapid transitions
    private var lastTransitionTime: Date = .distantPast

    init(bus: EffectBus) {
        self.bus = bus
    }

    // MARK: - Public Transition Methods

    /// IDLE -> ACTIVE. Called when content polling detects Claude working,
    /// or when an OSC 7778 start signal arrives.
    func onPromptSubmitted(hint: ShaderHint? = nil, promptText: String? = nil) {
        guard state.isIdle else { return }

        // Debounce: ignore if we just transitioned
        let now = Date()
        guard now.timeIntervalSince(lastTransitionTime) > 0.5 else { return }
        lastTransitionTime = now

        activityStartTime = now
        state = .active(since: now)

        // Start safety timeout (5 min)
        startActiveTimeout()

        bus.emit(.lifecycleActive(LifecycleActivePayload(
            hint: hint,
            promptText: promptText,
            resuming: false
        )))
    }

    /// ACTIVE -> COMPLETING. Called when OSC 7777 (claude-done) fires.
    /// Also accepts from IDLE (claude-done can arrive before polling detects activity).
    func onResponseComplete(tier: String) {
        guard state.isActive || state.isIdle else { return }

        // If idle, briefly activate so controllers get proper lifecycle events
        if state.isIdle {
            let now = Date()
            activityStartTime = now
            state = .active(since: now)
            bus.emit(.lifecycleActive(LifecycleActivePayload(
                hint: nil, promptText: nil, resuming: false
            )))
        }

        let taskTier = TaskTier(rawValue: tier) ?? .short
        let duration = activityStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let content = readContent?() ?? ""

        lastTransitionTime = Date()
        state = .completing(tier: taskTier, since: Date())

        cancelActiveTimeout()
        startCompletingTimeout()

        bus.emit(.lifecycleCompleting(LifecycleCompletingPayload(
            tier: taskTier,
            duration: duration,
            terminalContent: content
        )))
    }

    /// COMPLETING -> IDLE. Called after completion popup dismissed or timeout.
    func onCompletionDone() {
        guard state.isCompleting else { return }

        lastTransitionTime = Date()
        activityStartTime = nil
        activitySummary = nil
        state = .idle

        cancelCompletingTimeout()

        bus.emit(.lifecycleIdle)
    }

    /// Emit activity update while ACTIVE.
    func onActivityUpdate(summary: String?, detail: String? = nil) {
        guard state.isActive else { return }

        activitySummary = summary
        let duration = activityStartTime.map { Date().timeIntervalSince($0) } ?? 0

        bus.emit(.activityUpdate(ActivityUpdatePayload(
            summary: summary,
            detail: detail,
            sessionDuration: duration
        )))
    }

    /// Emit question detected event.
    func onQuestionDetected(_ question: ClaudeQuestion) {
        bus.emit(.questionDetected(QuestionPayload(question: question)))
    }

    /// Emit question dismissed event.
    func onQuestionDismissed() {
        bus.emit(.questionDismissed)
    }

    /// Emergency reset — used by debug HUD or error recovery.
    func forceReset() {
        cancelActiveTimeout()
        cancelCompletingTimeout()
        activityStartTime = nil
        activitySummary = nil
        lastContentHash = 0
        lastRawContentHash = 0
        lastContentLength = 0
        state = .idle
        bus.emit(.lifecycleIdle)
    }

    // MARK: - Content Polling

    /// Called every 100ms by the poll timer. Reads terminal content and drives state transitions.
    func poll() {
        guard autoMode else { return }
        guard let readContent else { return }
        let content = readContent()
        let hash = ContentDetection.stableContentHash(content)
        let rawHash = content.hashValue

        // Spinner-only change (content stable, raw hash differs = braille spinner animating)
        let isSpinnerChange = hash == lastContentHash && rawHash != lastRawContentHash
        let isContentChange = hash != lastContentHash

        lastRawContentHash = rawHash

        switch state {
        case .idle:
            pollIdle(content: content, hash: hash, isSpinnerChange: isSpinnerChange, isContentChange: isContentChange)

        case .active:
            pollActive(content: content, hash: hash, isContentChange: isContentChange)

        case .completing:
            pollCompleting(content: content, isContentChange: isContentChange)
        }

        if isContentChange {
            lastContentHash = hash
            lastContentLength = content.count
        }
    }

    // MARK: - Poll Handlers

    private func pollIdle(content: String, hash: Int, isSpinnerChange: Bool, isContentChange: Bool) {
        // Spinner change always takes priority — definitive signal Claude is working
        if isSpinnerChange {
            if ContentDetection.isClaudeCodePresent(in: content) {
                let hint = classifyActivity(content)
                onPromptSubmitted(hint: hint)
                fetchHeuristicSummary(content)
            }
            return
        }

        // Strict active-work check also takes priority over waiting-for-user
        if isContentChange && ContentDetection.isClaudeActivelyWorking(in: content) {
            let hint = classifyActivity(content)
            onPromptSubmitted(hint: hint)
            fetchHeuristicSummary(content)
            detectQuestion(content)
            return
        }

        // Only now check if waiting for user — no active work signals present
        if ContentDetection.isWaitingForUser(content) { return }

        if isContentChange {
            let smallChange = abs(content.count - lastContentLength) < 30

            if !smallChange {
                // Large content change — Claude likely started
                if ContentDetection.isClaudeCodePresent(in: content) {
                    let hint = classifyActivity(content)
                    onPromptSubmitted(hint: hint)
                    fetchHeuristicSummary(content)
                }
            }

            // Check for questions
            detectQuestion(content)
        }
    }

    private func pollActive(content: String, hash: Int, isContentChange: Bool) {
        // Check for questions while active
        if isContentChange {
            detectQuestion(content)
        }

        // Update activity summary periodically
        if isContentChange {
            fetchHeuristicSummary(content)

            // Emit activity update with duration
            let duration = activityStartTime.map { Date().timeIntervalSince($0) } ?? 0
            bus.emit(.activityUpdate(ActivityUpdatePayload(
                summary: activitySummary,
                detail: nil,
                sessionDuration: duration
            )))
        }
    }

    private func pollCompleting(content: String, isContentChange: Bool) {
        // If new activity detected during completion, re-activate
        if isContentChange && ContentDetection.isClaudeActivelyWorking(in: content) {
            cancelCompletingTimeout()
            let now = Date()
            lastTransitionTime = now
            activityStartTime = now
            state = .active(since: now)
            startActiveTimeout()

            bus.emit(.lifecycleActive(LifecycleActivePayload(
                hint: classifyActivity(content),
                promptText: nil,
                resuming: true
            )))
        }
    }

    // MARK: - Heuristic Summary

    private func fetchHeuristicSummary(_ content: String) {
        let lines = content.components(separatedBy: "\n")
        let tail = lines.suffix(80).joined(separator: "\n")
        if let heuristic = ClaudeActivitySummary.shared.heuristicSummary(tail) {
            activitySummary = heuristic
        }
    }

    // MARK: - Question Detection

    private func detectQuestion(_ content: String) {
        if content.contains("Enter to select") || content.contains("to navigate")
            || content.contains("Would you like to proceed") {
            if let question = ClaudeQuestion.parse(from: content) {
                onQuestionDetected(question)
                return
            }
        }
        // No question visible — dismiss if one was showing
        onQuestionDismissed()
    }

    // MARK: - Activity Classification

    /// Classify terminal content into a shader hint.
    /// Delegates to `ActivityCategory.classify(_:)` for the single shared implementation.
    private func classifyActivity(_ content: String) -> ShaderHint? {
        ActivityCategory.classify(content).shaderHint
    }

    // MARK: - Safety Timers

    private func startActiveTimeout() {
        cancelActiveTimeout()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state.isActive else { return }
            NSLog("[LifecycleManager] Active timeout (5min) — forcing idle")
            self.forceReset()
        }
        activeTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 300.0, execute: work)
    }

    private func cancelActiveTimeout() {
        activeTimeoutWork?.cancel()
        activeTimeoutWork = nil
    }

    private func startCompletingTimeout() {
        cancelCompletingTimeout()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state.isCompleting else { return }
            NSLog("[LifecycleManager] Completing timeout (5s) — transitioning to idle")
            self.onCompletionDone()
        }
        completingTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }

    private func cancelCompletingTimeout() {
        completingTimeoutWork?.cancel()
        completingTimeoutWork = nil
    }

    deinit {
        cancelActiveTimeout()
        cancelCompletingTimeout()
    }

    // MARK: - Debug

    /// Debug state for the HUD.
    var debugStateLabel: String {
        switch state {
        case .idle: return "idle"
        case .active: return "active"
        case .completing(let tier, _): return "completing/\(tier.rawValue)"
        }
    }
}
