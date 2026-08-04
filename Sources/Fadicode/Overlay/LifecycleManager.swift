import Foundation
import Combine

/// Hub of the hub-and-spoke architecture. Owns the three overlay lifecycle
/// states and emits events on the EffectBus.
///
/// # What changed in Gate 2 (upstream: PR#6798)
///
/// This class used to DECIDE whether Claude was working by polling terminal
/// TEXT at 10Hz, hashing it, and pattern-matching spinner glyphs and tool
/// banners. Every state transition in the overlay — border glow, shaders, the
/// pixel pet, the completion popup — hung off that guess. It fired on ordinary
/// shell output (a big paste, `ls`, a scroll) and, once ACTIVE, could only
/// leave via an OSC 7777 signal or a five-minute safety timeout. It lied in
/// both directions, which is what made the pet untrustworthy.
///
/// That entire path is gone. `AgentSessionRegistry` is now the authority:
/// agent hook events decide the state, process exit ends it deterministically,
/// and the transcript corroborates. This class SUBSCRIBES to that state and
/// translates it into the fork's three-phase overlay vocabulary:
///
///     AgentSessionState.working     -> .active
///     AgentSessionState.needsInput  -> .active + `needsInput` published
///     AgentSessionState.idle        -> .completing (if we were active) -> .idle
///     AgentSessionState.ended       -> .idle
///
/// Terminal text is still READ, but only for presentation: the activity-badge
/// phrase and, when the deterministic state already says `needsInput`, the
/// option labels for the question pill. Text no longer decides *whether*
/// anything is happening, only *what to render* about something we already
/// know is happening.
final class LifecycleManager: ObservableObject {

    @Published private(set) var state: LifecycleState = .idle

    /// True when the deterministic authority says the agent is blocked on the
    /// user. Never inferred from text.
    /// upstream: PR#6798 — ChatAgentState.needsAttention
    @Published private(set) var needsInput: Bool = false

    /// The bound surface's authoritative session state, republished so views
    /// (the pixel pet, the activity badge) render the real four-state model
    /// rather than the overlay's three-phase approximation of it.
    /// upstream: PR#6798 — ChatAgentState
    @Published private(set) var agentState: AgentSessionState?

    let bus: EffectBus

    /// Closure to read terminal content. Presentation only — see the class
    /// comment. Nothing in this file may derive lifecycle STATE from it.
    var readContent: (() -> String)?

    /// Deterministic gate: is a real agent process alive and bound to this
    /// surface? Set by `FadiCodeOverlayHost` once `surfaceId` is known.
    ///
    /// nil means "unknown" and is treated as permissive, so a surface that
    /// never got a binding key behaves as it did before.
    /// upstream: PR#6798
    var agentPresent: (() -> Bool)?

    /// True when we have no binding information (permissive) or an agent is live.
    private var isAgentPresent: Bool { agentPresent?() ?? true }

    // Activity tracking
    private(set) var activityStartTime: Date?
    private(set) var activitySummary: String?

    /// The surface this manager speaks for, once bound.
    private(set) var boundSurfaceID: UUID?
    private var registryCancellable: AnyCancellable?
    private var lastAgentState: AgentSessionState?

    // Safety timer for the completing -> idle hop only. The old 5-minute
    // "active timeout" is deleted: `ended` is now delivered deterministically
    // by the process-exit watcher, so nothing can strand us in `.active`.
    private var completingTimeoutWork: DispatchWorkItem?

    // Auto mode (disable from debug HUD)
    var autoMode: Bool = true

    // Debounce rapid transitions
    private var lastTransitionTime: Date = .distantPast

    /// Last question rendered, so the pill is not rebuilt on every refresh.
    private var lastQuestion: ClaudeQuestion?

    init(bus: EffectBus) {
        self.bus = bus
    }

    // MARK: - Binding

    /// Binds this manager to a surface's deterministic session state.
    ///
    /// From this point the overlay's lifecycle is a pure function of what the
    /// registry says about the agent — there is no other input.
    /// upstream: PR#6798
    @MainActor
    func bind(surfaceID: UUID) {
        guard boundSurfaceID != surfaceID else { return }
        boundSurfaceID = surfaceID
        registryCancellable = AgentSessionRegistry.shared.$stateBySurfaceID
            .map { $0[surfaceID] }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] agentState in
                self?.applyAgentState(agentState)
            }
    }

    @MainActor
    func unbind() {
        registryCancellable = nil
        boundSurfaceID = nil
        lastAgentState = nil
    }

    /// Translates the authoritative agent state into the overlay's phases.
    ///
    /// Only the transitions the overlay actually renders are acted on; a
    /// re-publication of the same state is a no-op, which is what removes the
    /// flicker the text heuristic produced.
    private func applyAgentState(_ agentState: AgentSessionState?) {
        self.agentState = agentState
        guard autoMode else { return }
        defer { lastAgentState = agentState }
        guard let agentState else {
            // No agent has ever been bound here. Nothing to render.
            if !state.isIdle { forceReset() }
            needsInput = false
            return
        }

        switch agentState {
        case .working(let since):
            needsInput = false
            if state.isCompleting { cancelCompletingTimeout() }
            if !state.isActive {
                enterActive(since: since, resuming: state.isCompleting, hint: currentShaderHint())
            }

        case .needsInput:
            // Blocked on the user is still a live session: keep the overlay
            // active so the surface reads as "yours to answer", and surface the
            // pill. Upstream ranks needsInput above working for attention.
            needsInput = true
            if !state.isActive {
                enterActive(since: agentState.since ?? Date(), resuming: false, hint: nil)
            }
            refreshQuestionPill()

        case .idle:
            needsInput = false
            dismissQuestionPill()
            if state.isActive {
                // A working -> idle edge is a completed turn: run the fork's
                // celebration path, tiered by how long the turn took.
                let duration = activityStartTime.map { Date().timeIntervalSince($0) } ?? 0
                enterCompleting(tier: TaskTier.from(duration: duration), duration: duration)
            }

        case .ended:
            needsInput = false
            dismissQuestionPill()
            if !state.isIdle { forceReset() }
        }
    }

    // MARK: - Public Transition Methods

    /// IDLE -> ACTIVE.
    ///
    /// Retained for the debug simulators and for an OSC 7778 `start` that
    /// arrives before the registry has published. The registry is still the
    /// authority; this only fast-paths the visual.
    func onPromptSubmitted(hint: ShaderHint? = nil, promptText: String? = nil) {
        guard state.isIdle else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTransitionTime) > 0.5 else { return }
        // Deterministic gate: no live agent bound to this surface means nothing
        // is allowed to claim one is working. Bypassed when `autoMode` is off,
        // which is how the debug HUD drives the overlay by hand.
        // upstream: PR#6798
        guard !autoMode || isAgentPresent else { return }
        enterActive(since: now, resuming: false, hint: hint, promptText: promptText)
    }

    /// ACTIVE -> COMPLETING. Called when OSC 7777 (claude-done) fires with an
    /// explicit tier, which is better information than the duration heuristic.
    func onResponseComplete(tier: String) {
        guard state.isActive || state.isIdle else { return }

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
        enterCompleting(tier: taskTier, duration: duration)
    }

    /// COMPLETING -> IDLE. Called after the completion popup is dismissed or
    /// the completing timeout fires.
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
        lastQuestion = nil
        bus.emit(.questionDismissed)
    }

    /// Emergency reset — used by the debug HUD, error recovery, and the
    /// `ended` edge.
    func forceReset() {
        cancelCompletingTimeout()
        activityStartTime = nil
        activitySummary = nil
        lastQuestion = nil
        needsInput = false
        state = .idle
        bus.emit(.lifecycleIdle)
    }

    // MARK: - Presentation refresh

    /// Refreshes what the overlay SAYS about the current state. Never changes
    /// the state itself.
    ///
    /// The 10Hz content-hash poll this replaced is documented in the class
    /// comment. This runs at 1Hz and only while the deterministic authority
    /// already says something is happening, so a quiet terminal costs nothing.
    func poll() {
        guard autoMode else { return }
        guard state.isActive else { return }
        guard let readContent else { return }
        let content = readContent()

        if let heuristic = ClaudeActivitySummary.shared.heuristicSummary(
            content.components(separatedBy: "\n").suffix(80).joined(separator: "\n")
        ) {
            if heuristic != activitySummary {
                activitySummary = heuristic
                let duration = activityStartTime.map { Date().timeIntervalSince($0) } ?? 0
                bus.emit(.activityUpdate(ActivityUpdatePayload(
                    summary: heuristic,
                    detail: nil,
                    sessionDuration: duration
                )))
            }
        }

        if needsInput { refreshQuestionPill(content: content) }
    }

    // MARK: - Question pill (presentation only)

    /// Builds the tappable option list for the question pill.
    ///
    /// WHETHER a question is pending is decided upstream-style, by the
    /// `needsInput` state that came from an `AskUserQuestion` /
    /// `PermissionRequest` / `ExitPlanMode` / `Notification` hook. This only
    /// answers WHAT the options are, which is not carried on the fork's ingest
    /// today, so it is scraped from the rendered prompt. Guarded by the
    /// deterministic state so it can never invent a question the way the old
    /// `detectQuestion` did on any terminal that happened to print
    /// "Enter to select".
    private func refreshQuestionPill(content: String? = nil) {
        guard needsInput else { return }
        let text = content ?? readContent?() ?? ""
        guard !text.isEmpty else { return }
        guard let question = ClaudeQuestion.parse(from: text) else { return }
        guard question != lastQuestion else { return }
        lastQuestion = question
        onQuestionDetected(question)
    }

    private func dismissQuestionPill() {
        guard lastQuestion != nil else { return }
        onQuestionDismissed()
    }

    // MARK: - Internal transitions

    private func enterActive(
        since: Date,
        resuming: Bool,
        hint: ShaderHint?,
        promptText: String? = nil
    ) {
        let now = Date()
        lastTransitionTime = now
        activityStartTime = since
        state = .active(since: since)
        bus.emit(.lifecycleActive(LifecycleActivePayload(
            hint: hint,
            promptText: promptText,
            resuming: resuming
        )))
    }

    private func enterCompleting(tier: TaskTier, duration: TimeInterval) {
        let content = readContent?() ?? ""
        lastTransitionTime = Date()
        state = .completing(tier: tier, since: Date())
        cancelCompletingTimeout()
        startCompletingTimeout()
        bus.emit(.lifecycleCompleting(LifecycleCompletingPayload(
            tier: tier,
            duration: duration,
            terminalContent: content
        )))
    }

    /// Shader hint for the current turn, from the last summary phrase rather
    /// than a fresh scrape of the screen.
    private func currentShaderHint() -> ShaderHint? {
        guard let activitySummary else { return nil }
        switch ContentDetection.phaseFromSummary(activitySummary) {
        case .thinking: return .planning
        case .writing: return .coding
        case .reading, .searching: return .researching
        default: return nil
        }
    }

    // MARK: - Safety timer

    private func startCompletingTimeout() {
        cancelCompletingTimeout()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state.isCompleting else { return }
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
        completingTimeoutWork?.cancel()
    }

    // MARK: - Debug

    /// Debug state for the HUD.
    var debugStateLabel: String {
        let agent = lastAgentState?.label ?? "unbound"
        switch state {
        case .idle: return "idle (agent: \(agent))"
        case .active: return needsInput ? "active/needsInput (agent: \(agent))" : "active (agent: \(agent))"
        case .completing(let tier, _): return "completing/\(tier.rawValue) (agent: \(agent))"
        }
    }
}
