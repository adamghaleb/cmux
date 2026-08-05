import Foundation
import Combine
import Bonsplit

/// Controls the GPU shader overlay. Subscribes to lifecycle events and manages
/// shader session, tier escalation, and cycling independently.
final class ShaderDirector: ObservableObject, VisualController {

    // MARK: Published State (read by SwiftUI)

    @Published private(set) var shaderActive: Bool = false
    @Published private(set) var shaderMode: Int = ShaderCatalog.pickForTier(.ambient, avoiding: []).mode
    @Published private(set) var shaderTuning: ShaderTuning = ShaderTuning()
    @Published private(set) var shaderChangeCount: Int = 0

    /// Whether the window hosting this overlay currently has the user's focus.
    ///
    /// Drives the entire unfocused treatment: full palette instead of the
    /// vivid-only top stops, `.normal` instead of `.screen` blending, a dimmed
    /// terminal and a thinner grid. Written only by ``setFocused(_:)``, which is
    /// fed by `WindowFocusObserver` from `FadiCodeOverlayHost`.
    ///
    /// This was `var` with no writer anywhere in the codebase, which made every
    /// unfocused branch dead code. `private(set)` is what keeps it honest.
    /// See fadi-orchestrator#69.
    @Published private(set) var shaderFocused: Bool = true
    /// True while the window is being live-resized.
    @Published var shaderResizing: Bool = false

    // MARK: Internal State

    let shaderSession = ShaderSession()
    private var cancellables = Set<AnyCancellable>()
    private var cycleTimer: Timer?

    // Auto mode (can be disabled from debug HUD)
    var autoMode: Bool = true

    // MARK: VisualController

    func attach(to bus: EffectBus) {
        bus.onLifecycleActive()
            .sink { [weak self] payload in self?.handleActive(payload) }
            .store(in: &cancellables)

        bus.onLifecycleCompleting()
            .sink { [weak self] _ in self?.handleCompleting() }
            .store(in: &cancellables)

        bus.onLifecycleIdle()
            .sink { [weak self] in self?.handleIdle() }
            .store(in: &cancellables)

        bus.onActivityUpdate()
            .sink { [weak self] payload in self?.handleActivityUpdate(payload) }
            .store(in: &cancellables)
    }

    func detach() {
        cancellables.removeAll()
        stopCycleTimer()
    }

    func reset() {
        if shaderSession.isSessionActive {
            shaderSession.endSession()
        }
        shaderActive = false
        shaderChangeCount = 0
        stopCycleTimer()
    }

    func debugState() -> [String: String] {
        [
            "shader": shaderActive ? "on" : "off",
            "mode": "\(shaderMode)",
            "tier": shaderSession.isSessionActive ? shaderSession.currentTier.debugName : "---",
            "changes": "\(shaderChangeCount)",
            "focus": shaderFocused ? "focused" : "unfocused",
        ]
    }

    // MARK: - Window Focus

    /// Route real window focus into the shader treatment.
    ///
    /// Idempotent: repeated calls with the same verdict do not republish, so a
    /// noisy stream of AppKit notifications cannot thrash SwiftUI. Always
    /// applies on the main thread — `@Published` drives view updates and the
    /// observer can call in from a workspace notification.
    func setFocused(_ focused: Bool) {
        if Thread.isMainThread {
            applyFocus(focused)
        } else {
            DispatchQueue.main.async { [weak self] in self?.applyFocus(focused) }
        }
    }

    private func applyFocus(_ focused: Bool) {
        guard focused != shaderFocused else { return }
        shaderFocused = focused
        #if DEBUG
        dlog("[SD] focus -> \(focused ? "focused" : "unfocused")")
        #endif
    }

    // MARK: - Event Handlers

    private func handleActive(_ payload: LifecycleActivePayload) {
        let summary = summaryFromHint(payload.hint)

        if payload.resuming && shaderSession.isSessionActive {
            // Resume existing session
            if let picked = shaderSession.updateActivity(
                summary: summary,
                sessionDuration: shaderSession.sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
            ) {
                applyShader(picked)
            }
        } else if shaderSession.isSessionActive {
            // Session already running — update activity
            if let picked = shaderSession.updateActivity(
                summary: summary,
                sessionDuration: shaderSession.sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
            ) {
                applyShader(picked)
            }
        } else {
            // Start new session
            let picked = shaderSession.startSession(summary: summary)
            applyShader(picked)
        }

        shaderActive = true
        startCycleTimer()
    }

    private func handleCompleting() {
        stopCycleTimer()
        if shaderSession.isSessionActive {
            shaderSession.endSession()
        }
        shaderActive = false
    }

    private func handleIdle() {
        stopCycleTimer()
        if shaderSession.isSessionActive {
            shaderSession.endSession()
        }
        shaderActive = false
    }

    private func handleActivityUpdate(_ payload: ActivityUpdatePayload) {
        guard shaderSession.isSessionActive else { return }
        if let picked = shaderSession.updateActivity(
            summary: payload.summary,
            sessionDuration: payload.sessionDuration
        ) {
            applyShader(picked)
        }
    }

    // MARK: - Shader Application

    private func applyShader(_ shader: ShaderCatalog.ProfiledShader) {
        #if DEBUG
        dlog("[SD] mode \(shaderMode) -> \(shader.mode) (\(shader.name), tier: \(shader.tier), count: \(shaderChangeCount + 1))")
        #endif

        shaderMode = shader.mode
        shaderTuning = ShaderTuning(
            speedMultiplier: shader.speedMultiplier,
            contrast: shader.contrast,
            brightness: shader.brightness
        )
        shaderChangeCount += 1
    }

    // MARK: - Cycle Timer

    private func startCycleTimer() {
        stopCycleTimer()
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self, self.shaderSession.isSessionActive else { return }
            let duration = self.shaderSession.sessionStartTime.map { Date().timeIntervalSince($0) } ?? 0
            if let picked = self.shaderSession.updateActivity(
                summary: nil,
                sessionDuration: duration
            ) {
                self.applyShader(picked)
            }
        }
    }

    private func stopCycleTimer() {
        cycleTimer?.invalidate()
        cycleTimer = nil
    }

    // MARK: - Debug Controls

    #if DEBUG
    func debugSetTier(_ tier: ShaderTier) {
        let picked = ShaderCatalog.pickForTier(tier, avoiding: [shaderMode])
        applyShader(picked)
        shaderActive = true
        if !shaderSession.isSessionActive {
            _ = shaderSession.startSession(summary: nil)
        }
        shaderSession.debugSetTier(tier)
    }

    func debugCycleShader() {
        guard shaderSession.isSessionActive else {
            debugSetTier(.ambient)
            return
        }
        let picked = ShaderCatalog.pickForTier(shaderSession.currentTier, avoiding: [shaderMode])
        applyShader(picked)
    }

    func debugSelectShader(mode: Int) {
        guard let shader = ShaderCatalog.shaders.first(where: { $0.mode == mode }) else { return }
        if !shaderSession.isSessionActive {
            debugSetTier(shader.tier)
        }
        autoMode = false
        applyShader(shader)
    }

    func debugEscalate() {
        guard shaderSession.isSessionActive else {
            debugSetTier(.ambient)
            return
        }
        let nextRaw = shaderSession.currentTier.rawValue + 1
        let next = ShaderTier(rawValue: min(nextRaw, ShaderTier.highEnergy.rawValue)) ?? .highEnergy
        debugSetTier(next)
    }

    func debugStopShader() {
        autoMode = true
        reset()
    }
    #endif

    // MARK: - Helpers

    private func summaryFromHint(_ hint: ShaderHint?) -> String? {
        guard let hint else { return nil }
        switch hint {
        case .planning: return "Thinking"
        case .coding: return "Writing code"
        case .creative: return "Creative work"
        case .researching: return "Searching codebase"
        case .conversing: return "Conversing"
        }
    }
}
