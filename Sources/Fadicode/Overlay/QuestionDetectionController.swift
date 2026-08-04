import Foundation
import Combine

/// Controls the question detection pill overlay.
final class QuestionDetectionController: ObservableObject, VisualController {

    @Published private(set) var question: ClaudeQuestion?

    private var cancellables = Set<AnyCancellable>()

    func attach(to bus: EffectBus) {
        bus.onQuestionDetected()
            .sink { [weak self] payload in
                self?.question = payload.question
            }
            .store(in: &cancellables)

        bus.onQuestionDismissed()
            .sink { [weak self] in
                self?.question = nil
            }
            .store(in: &cancellables)

        // Dismiss question when new activity starts
        bus.onLifecycleActive()
            .sink { [weak self] _ in
                self?.question = nil
            }
            .store(in: &cancellables)
    }

    func detach() {
        cancellables.removeAll()
    }

    func reset() {
        question = nil
    }

    func debugState() -> [String: String] {
        ["question": question != nil ? "showing" : "---"]
    }
}
