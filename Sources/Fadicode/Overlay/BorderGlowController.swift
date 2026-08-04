import Foundation
import Combine

/// Controls the activity border glow around the terminal surface.
final class BorderGlowController: ObservableObject, VisualController {

    @Published private(set) var isActive: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private var holdWork: DispatchWorkItem?

    func attach(to bus: EffectBus) {
        bus.onLifecycleActive()
            .sink { [weak self] _ in
                self?.holdWork?.cancel()
                self?.isActive = true
            }
            .store(in: &cancellables)

        bus.onLifecycleCompleting()
            .sink { [weak self] _ in
                guard let self else { return }
                // Brief hold, then deactivate
                let work = DispatchWorkItem { [weak self] in
                    self?.isActive = false
                }
                self.holdWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
            }
            .store(in: &cancellables)

        bus.onLifecycleIdle()
            .sink { [weak self] in
                self?.holdWork?.cancel()
                self?.isActive = false
            }
            .store(in: &cancellables)
    }

    func detach() {
        cancellables.removeAll()
        holdWork?.cancel()
    }

    func reset() {
        holdWork?.cancel()
        isActive = false
    }

    func debugState() -> [String: String] {
        ["borderGlow": isActive ? "on" : "off"]
    }
}
