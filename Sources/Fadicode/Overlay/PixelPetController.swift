import Foundation
import Combine

/// Controls the pixel pet's mood based on lifecycle events.
/// The pet animation system (PetAnimator, SpriteSheet, etc.) stays untouched —
/// this controller only publishes mood changes.
final class PixelPetController: ObservableObject, VisualController {

    /// Pet moods that map to the existing PetState system.
    enum PetMood: String {
        case idle, working, excited, celebrating
    }

    @Published private(set) var mood: PetMood = .idle

    private var cancellables = Set<AnyCancellable>()

    func attach(to bus: EffectBus) {
        bus.onLifecycleActive()
            .sink { [weak self] _ in
                self?.mood = .working
            }
            .store(in: &cancellables)

        bus.onLifecycleCompleting()
            .sink { [weak self] _ in
                self?.mood = .celebrating
            }
            .store(in: &cancellables)

        bus.onLifecycleIdle()
            .sink { [weak self] in
                self?.mood = .idle
            }
            .store(in: &cancellables)
    }

    func detach() {
        cancellables.removeAll()
    }

    func reset() {
        mood = .idle
    }

    func debugState() -> [String: String] {
        ["petMood": mood.rawValue]
    }
}
