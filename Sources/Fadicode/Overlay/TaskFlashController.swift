import Foundation
import Combine

/// Controls the task completion flash overlay.
final class TaskFlashController: ObservableObject, VisualController {

    @Published private(set) var flashTier: String?

    private var cancellables = Set<AnyCancellable>()
    private var resetWork: DispatchWorkItem?

    func attach(to bus: EffectBus) {
        bus.onLifecycleCompleting()
            .sink { [weak self] payload in
                guard let self else { return }
                self.resetWork?.cancel()

                // Reset to nil first for repeated signals
                if self.flashTier != nil {
                    self.flashTier = nil
                }
                DispatchQueue.main.async {
                    self.flashTier = payload.tier.rawValue
                }

                // Auto-reset after flash completes
                let work = DispatchWorkItem { [weak self] in
                    self?.flashTier = nil
                }
                self.resetWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
            }
            .store(in: &cancellables)
    }

    func detach() {
        cancellables.removeAll()
        resetWork?.cancel()
    }

    func reset() {
        resetWork?.cancel()
        flashTier = nil
    }

    func debugState() -> [String: String] {
        ["flash": flashTier ?? "---"]
    }
}
