import Foundation
import Combine

/// Controls the activity badge (summary text + phase breadcrumbs + timer).
final class ActivityBadgeController: ObservableObject, VisualController {

    @Published private(set) var summary: String?
    @Published private(set) var phases: [ActivityPhase] = []
    @Published private(set) var startDate: Date?

    private var cancellables = Set<AnyCancellable>()

    func attach(to bus: EffectBus) {
        bus.onLifecycleActive()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.startDate == nil {
                    self.startDate = Date()
                }
            }
            .store(in: &cancellables)

        bus.onActivityUpdate()
            .sink { [weak self] payload in
                guard let self else { return }
                self.summary = payload.summary
                if let summary = payload.summary {
                    self.trackPhase(from: summary)
                }
            }
            .store(in: &cancellables)

        bus.onLifecycleCompleting()
            .sink { [weak self] _ in
                self?.summary = nil
                self?.startDate = nil
                self?.phases = []
            }
            .store(in: &cancellables)

        bus.onLifecycleIdle()
            .sink { [weak self] in
                self?.summary = nil
                self?.startDate = nil
                self?.phases = []
            }
            .store(in: &cancellables)
    }

    func detach() {
        cancellables.removeAll()
    }

    func reset() {
        summary = nil
        phases = []
        startDate = nil
    }

    func debugState() -> [String: String] {
        [
            "summary": summary ?? "---",
            "phases": phases.map(\.displayName).joined(separator: " > "),
        ]
    }

    // MARK: - Phase Tracking

    private func trackPhase(from summary: String) {
        let phase = ContentDetection.phaseFromSummary(summary)
        if phases.last != phase {
            phases.append(phase)
            if phases.count > 5 {
                phases.removeFirst()
            }
        }
    }
}
