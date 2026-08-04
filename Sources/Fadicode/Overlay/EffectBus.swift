import Foundation
import Combine

/// Central event bus for the hub-and-spoke overlay architecture.
/// LifecycleManager emits events; controllers subscribe to only what they need.
/// All subscriptions deliver on the main thread.
final class EffectBus {
    private let subject = PassthroughSubject<EffectEvent, Never>()

    /// Emit an event to all subscribers.
    func emit(_ event: EffectEvent) {
        #if DEBUG
        let ts = String(format: "%.2f", Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 1000))
        let label: String
        switch event {
        case .lifecycleActive: label = "lifecycleActive"
        case .lifecycleCompleting: label = "lifecycleCompleting"
        case .lifecycleIdle: label = "lifecycleIdle"
        case .activityUpdate: label = "activityUpdate"
        case .questionDetected: label = "questionDetected"
        case .questionDismissed: label = "questionDismissed"
        }
        NSLog("[EffectBus] [\(ts)] \(label)")
        #endif
        subject.send(event)
    }

    // MARK: - Typed Subscribers

    func onLifecycleActive() -> AnyPublisher<LifecycleActivePayload, Never> {
        subject
            .compactMap { if case .lifecycleActive(let p) = $0 { return p } else { return nil } }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func onLifecycleCompleting() -> AnyPublisher<LifecycleCompletingPayload, Never> {
        subject
            .compactMap { if case .lifecycleCompleting(let p) = $0 { return p } else { return nil } }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func onLifecycleIdle() -> AnyPublisher<Void, Never> {
        subject
            .compactMap { if case .lifecycleIdle = $0 { return () } else { return nil } }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func onActivityUpdate() -> AnyPublisher<ActivityUpdatePayload, Never> {
        subject
            .compactMap { if case .activityUpdate(let p) = $0 { return p } else { return nil } }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func onQuestionDetected() -> AnyPublisher<QuestionPayload, Never> {
        subject
            .compactMap { if case .questionDetected(let p) = $0 { return p } else { return nil } }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    func onQuestionDismissed() -> AnyPublisher<Void, Never> {
        subject
            .compactMap { if case .questionDismissed = $0 { return () } else { return nil } }
            .receive(on: DispatchQueue.main)
            .eraseToAnyPublisher()
    }
}
