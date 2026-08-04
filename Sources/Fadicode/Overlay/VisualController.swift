import Foundation

/// Protocol for all visual controllers in the hub-and-spoke architecture.
/// Each controller manages one visual subsystem independently.
protocol VisualController: AnyObject {
    /// Subscribe to relevant events on the bus.
    func attach(to bus: EffectBus)

    /// Unsubscribe from all events.
    func detach()

    /// Reset to initial state (used by emergency reset).
    func reset()

    /// Return debug key-value pairs for the debug HUD.
    func debugState() -> [String: String]
}
