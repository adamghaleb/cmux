import Foundation
import Combine

/// Plays the completion sound when a task finishes. Fire-and-forget.
final class CompletionSoundController: VisualController {

    private var cancellables = Set<AnyCancellable>()

    func attach(to bus: EffectBus) {
        bus.onLifecycleCompleting()
            .sink { payload in
                TaskFlashOverlay.playCompletionSound(tier: payload.tier.rawValue)
            }
            .store(in: &cancellables)
    }

    func detach() {
        cancellables.removeAll()
    }

    func reset() {
        // No state to reset
    }

    func debugState() -> [String: String] {
        [:]
    }
}
