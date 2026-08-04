import Foundation
import Combine

/// Controls the completion summary popup — streaming fetch, dismiss, recall.
final class CompletionPopupController: ObservableObject, VisualController {

    @Published private(set) var completionSummary: CompletionSummary?
    @Published private(set) var dismissedCompletionSummary: CompletionSummary?
    @Published private(set) var completionHistory: [CompletionHistoryEntry] = []
    @Published private(set) var lastActivityDuration: TimeInterval?

    /// Whether the recall button should show.
    var showRecallButton: Bool {
        completionSummary == nil && dismissedCompletionSummary != nil
    }

    private var cancellables = Set<AnyCancellable>()
    private var activeStreamingTask: URLSessionDataTask?
    private var dismissTimer: DispatchWorkItem?

    func attach(to bus: EffectBus) {
        bus.onLifecycleCompleting()
            .sink { [weak self] payload in
                self?.handleCompleting(payload)
            }
            .store(in: &cancellables)

        bus.onLifecycleActive()
            .sink { [weak self] _ in
                // Activity resumed — dismiss any completion popup
                self?.cancelStreaming()
                self?.clearStashed()
            }
            .store(in: &cancellables)

        bus.onLifecycleIdle()
            .sink { [weak self] _ in
                // If there's a completion showing, start auto-dismiss timer
                self?.startDismissTimer()
            }
            .store(in: &cancellables)
    }

    func detach() {
        cancellables.removeAll()
        cancelStreaming()
        dismissTimer?.cancel()
    }

    func reset() {
        cancelStreaming()
        dismissTimer?.cancel()
        completionSummary = nil
        dismissedCompletionSummary = nil
        lastActivityDuration = nil
    }

    func debugState() -> [String: String] {
        [
            "completion": completionSummary != nil ? "showing" : (dismissedCompletionSummary != nil ? "stashed" : "---"),
            "history": "\(completionHistory.count)",
        ]
    }

    // MARK: - Public Actions

    func dismiss() {
        if let summary = completionSummary {
            dismissedCompletionSummary = summary
        }
        completionSummary = nil
        dismissTimer?.cancel()
    }

    func recall() {
        if let stashed = dismissedCompletionSummary {
            completionSummary = stashed
            dismissedCompletionSummary = nil
            startDismissTimer()
        }
    }

    // MARK: - Completion Handling

    private func handleCompleting(_ payload: LifecycleCompletingPayload) {
        lastActivityDuration = payload.duration

        let content = payload.terminalContent
        let lines = content.components(separatedBy: "\n")
        let tail = lines.suffix(100).joined(separator: "\n")
        guard !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // Show placeholder immediately
        let placeholder = CompletionSummary(
            whatHappened: "Summarizing...",
            whatNeeded: "Summarizing...",
            suggestedPrompt: nil
        )
        completionSummary = placeholder
        dismissedCompletionSummary = nil

        // Cancel any existing streaming task
        cancelStreaming()

        // Stream from Haiku. ClaudeActivitySummary is @MainActor; hop onto the
        // main actor explicitly so this compiles under the stricter isolation
        // checking of newer Swift toolchains (behavior unchanged: EffectBus
        // events already arrive on the main thread).
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activeStreamingTask = ClaudeActivitySummary.shared.summarizeCompletionStreaming(
            terminalContent: tail,
            onPartial: { [weak self] partial in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.completionSummary = partial
                }
            },
            onComplete: { [weak self] summary in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.activeStreamingTask = nil
                    if let summary {
                        self.completionSummary = summary
                        let entry = CompletionHistoryEntry(timestamp: Date(), summary: summary)
                        self.completionHistory.append(entry)
                        if self.completionHistory.count > 10 {
                            self.completionHistory.removeFirst(self.completionHistory.count - 10)
                        }
                        self.startDismissTimer()
                    } else {
                        // Streaming failed
                        self.completionSummary = nil
                    }
                }
            }
            )
        }
    }

    // MARK: - Internal

    private func cancelStreaming() {
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
    }

    private func clearStashed() {
        completionSummary = nil
        dismissedCompletionSummary = nil
    }

    private func startDismissTimer() {
        dismissTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: work)
    }
}
