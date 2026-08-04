import Foundation
import Combine

/// Facade that owns the EffectBus, LifecycleManager, and all visual controllers.
/// Replaces OverlayStateMachine as the single entry point for overlay behavior.
final class FadiCodeOverlaySystem: ObservableObject {

    // MARK: - Core

    let bus = EffectBus()
    let lifecycle: LifecycleManager

    // MARK: - Controllers

    let shaderDirector = ShaderDirector()
    let borderGlow = BorderGlowController()
    let activityBadge = ActivityBadgeController()
    let taskFlash = TaskFlashController()
    let completionSound = CompletionSoundController()
    let completionPopup = CompletionPopupController()
    let questionDetection = QuestionDetectionController()
    let pixelPet = PixelPetController()

    // MARK: - All controllers for iteration

    private var allControllers: [VisualController] {
        [shaderDirector, borderGlow, activityBadge, taskFlash,
         completionSound, completionPopup, questionDetection, pixelPet]
    }

    // MARK: - LLM Summary Polling

    private var summaryPollTimer: Timer?
    private var summaryPollCancellable: AnyCancellable?

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    init() {
        lifecycle = LifecycleManager(bus: bus)

        // Attach all controllers
        for controller in allControllers {
            controller.attach(to: bus)
        }

        // NOTE: We intentionally do NOT forward objectWillChange from child
        // controllers into this system object. Each controller is its own
        // ObservableObject — SwiftUI views observe them independently to avoid
        // broadcasting every change to the entire overlay tree (GitHub #17).

        // Start LLM summary polling when active, stop when not
        lifecycle.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state.isActive {
                    self.startSummaryPolling()
                } else {
                    self.stopSummaryPolling()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        for controller in allControllers {
            controller.detach()
        }
        stopSummaryPolling()
    }

    // MARK: - Public Facade Methods

    /// Dismiss the completion popup.
    func dismissCompletion() {
        completionPopup.dismiss()
    }

    /// Recall a dismissed completion popup.
    func recallCompletion() {
        completionPopup.recall()
    }

    /// Called after the user answers a question.
    func onQuestionAnswered() {
        lifecycle.onQuestionDismissed()
    }

    /// Transition completing -> idle.
    func onCompletionDone() {
        lifecycle.onCompletionDone()
    }

    /// Emergency reset — all controllers + lifecycle.
    func emergencyReset() {
        lifecycle.forceReset()
        for controller in allControllers {
            controller.reset()
        }
    }

    // MARK: - Auto Mode

    var autoMode: Bool {
        get { lifecycle.autoMode }
        set {
            lifecycle.autoMode = newValue
            shaderDirector.autoMode = newValue
        }
    }

    // MARK: - LLM Summary Polling

    private func startSummaryPolling() {
        guard summaryPollTimer == nil else { return }
        fetchActivitySummary()
        summaryPollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.fetchActivitySummary()
        }
    }

    private func stopSummaryPolling() {
        summaryPollTimer?.invalidate()
        summaryPollTimer = nil
    }

    private func fetchActivitySummary() {
        guard let readContent = lifecycle.readContent else { return }
        let content = readContent()
        let lines = content.components(separatedBy: "\n")
        let tail = lines.suffix(80).joined(separator: "\n")
        guard !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        ClaudeActivitySummary.shared.summarize(terminalContent: tail) { [weak self] summary in
            DispatchQueue.main.async {
                guard let self else { return }
                if let summary {
                    self.lifecycle.onActivityUpdate(summary: summary)
                }
            }
        }
    }

    // MARK: - Convenience Accessors (backward compat for SurfaceView)

    var isTerminalActive: Bool { borderGlow.isActive }
    var isWorkingStateActive: Bool { shaderDirector.shaderActive }
    var activeShaderMode: Int { shaderDirector.shaderMode }
    var activeShaderTuning: ShaderTuning { shaderDirector.shaderTuning }
    var shaderChangeCount: Int { shaderDirector.shaderChangeCount }
    var activityStartDate: Date? { activityBadge.startDate }
    var lastActivityDuration: TimeInterval? { completionPopup.lastActivityDuration }
    var activitySummary: String? { activityBadge.summary }
    var activityPhases: [ActivityPhase] { activityBadge.phases }
    var claudeQuestion: ClaudeQuestion? { questionDetection.question }
    var completionSummary: CompletionSummary? { completionPopup.completionSummary }
    var dismissedCompletionSummary: CompletionSummary? { completionPopup.dismissedCompletionSummary }
    var completionHistory: [CompletionHistoryEntry] { completionPopup.completionHistory }
    var showRecallButton: Bool { completionPopup.showRecallButton }

    // MARK: - Debug / Simulation

    #if DEBUG
    func simulateThinking() {
        shaderDirector.autoMode = false
        lifecycle.autoMode = false
        emergencyReset()
        lifecycle.onPromptSubmitted(hint: .planning)
        lifecycle.onActivityUpdate(summary: "Thinking")
        shaderDirector.debugSetTier(.ambient)
    }

    func simulateReading() {
        shaderDirector.autoMode = false
        lifecycle.autoMode = false
        emergencyReset()
        lifecycle.onPromptSubmitted(hint: .researching)
        lifecycle.onActivityUpdate(summary: "Reading files")
        shaderDirector.debugSetTier(.flowing)
    }

    func simulateWriting() {
        shaderDirector.autoMode = false
        lifecycle.autoMode = false
        emergencyReset()
        lifecycle.onPromptSubmitted(hint: .coding)
        lifecycle.onActivityUpdate(summary: "Writing code")
        shaderDirector.debugSetTier(.deep)
    }

    func simulateExecuting() {
        shaderDirector.autoMode = false
        lifecycle.autoMode = false
        emergencyReset()
        lifecycle.onPromptSubmitted()
        lifecycle.onActivityUpdate(summary: "Building project")
        shaderDirector.debugSetTier(.highEnergy)
    }

    func simulateCompletion() {
        shaderDirector.autoMode = false
        lifecycle.autoMode = false
        lifecycle.onResponseComplete(tier: "medium")
    }

    func simulateWaitingForUser() {
        shaderDirector.autoMode = false
        lifecycle.autoMode = false
        // Just stop activity — no dedicated waiting state in new system
        lifecycle.forceReset()
        lifecycle.onActivityUpdate(summary: "Waiting for user")
    }

    func simulateFullLifecycle() {
        simulateThinking()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.lifecycle.onActivityUpdate(summary: "Reading files")
            self?.shaderDirector.debugSetTier(.flowing)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
            self?.lifecycle.onActivityUpdate(summary: "Writing code")
            self?.shaderDirector.debugSetTier(.deep)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) { [weak self] in
            self?.lifecycle.onActivityUpdate(summary: "Building project")
            self?.shaderDirector.debugSetTier(.highEnergy)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { [weak self] in
            self?.simulateCompletion()
        }
    }
    #endif
}
