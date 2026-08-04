#if DEBUG
import SwiftUI

/// Compact debug HUD at top of terminal for visualizing and controlling the overlay system.
/// Toggle with Cmd+Shift+D. Shows on all surfaces simultaneously.
struct DebugStateOverlay: View {
    /// Retained for calling facade/simulation methods. Not observed directly —
    /// sub-controllers are observed independently to avoid broadcast redraws (GitHub #17).
    let overlaySystem: FadiCodeOverlaySystem

    // Observe only the controllers the debug HUD reads from
    @ObservedObject var lifecycle: LifecycleManager
    @ObservedObject var shaderDirector: ShaderDirector
    @ObservedObject var borderGlow: BorderGlowController
    @ObservedObject var activityBadge: ActivityBadgeController

    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var isExpanded: Bool = true

    /// Convenience initializer that extracts controllers from the system.
    init(overlaySystem: FadiCodeOverlaySystem, onClose: @escaping () -> Void) {
        self.overlaySystem = overlaySystem
        self.lifecycle = overlaySystem.lifecycle
        self.shaderDirector = overlaySystem.shaderDirector
        self.borderGlow = overlaySystem.borderGlow
        self.activityBadge = overlaySystem.activityBadge
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Row 1: State info + collapse toggle
            HStack(spacing: 8) {
                badge("STATE", phaseLabel, phaseColor)
                shaderPicker
                badge("TIER", tierLabel, tierColor)

                Spacer()

                Button(action: { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded
                    ? String(localized: "accessibility.debug.collapse", defaultValue: "Collapse debug overlay")
                    : String(localized: "accessibility.debug.expand", defaultValue: "Expand debug overlay"))

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "accessibility.debug.close", defaultValue: "Close debug overlay"))
            }

            if isExpanded {
                // Row 2: Activity + status dots
                HStack(spacing: 8) {
                    badge("ACTIVITY", activityLabel, .green)

                    if let duration = sessionDuration {
                        infoChip("Session: \(formatDuration(duration))")
                    }

                    HStack(spacing: 4) {
                        statusDot(overlaySystem.borderGlow.isActive, "ACT")
                        statusDot(overlaySystem.shaderDirector.shaderActive, "SHD")
                        statusDot(overlaySystem.shaderDirector.shaderFocused, "FOC")
                    }
                    .font(.system(size: 8, design: .monospaced))

                    Spacer()

                    Toggle("Auto", isOn: Binding(
                        get: { overlaySystem.autoMode },
                        set: { overlaySystem.autoMode = $0 }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.8))
                    .accessibilityLabel(String(localized: "accessibility.debug.autoMode", defaultValue: "Auto mode"))
                    .accessibilityHint(String(localized: "accessibility.debug.autoModeHint", defaultValue: "Toggles automatic overlay state transitions"))
                }

                Divider().background(Color.white.opacity(0.2))

                // Row 3: Simulate states
                HStack(spacing: 4) {
                    Text("SIM:")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))

                    simButton("Think", color: .gray) { overlaySystem.simulateThinking() }
                    simButton("Read", color: .cyan) { overlaySystem.simulateReading() }
                    simButton("Write", color: .blue) { overlaySystem.simulateWriting() }
                    simButton("Build", color: .red) { overlaySystem.simulateExecuting() }
                    simButton("Done", color: .green) { overlaySystem.simulateCompletion() }
                    simButton("Wait", color: .purple) { overlaySystem.simulateWaitingForUser() }

                    Spacer()
                }

                // Row 4: Shader controls + full lifecycle
                HStack(spacing: 4) {
                    Text("CTL:")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))

                    controlButton("Cycle") { overlaySystem.shaderDirector.debugCycleShader() }
                    controlButton("Tier+") { overlaySystem.shaderDirector.debugEscalate() }
                    controlButton("Stop") { overlaySystem.shaderDirector.debugStopShader() }

                    Spacer()

                    simButton("Full Lifecycle", color: .orange) { overlaySystem.simulateFullLifecycle() }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(true)
    }

    // MARK: - Computed Labels

    private var phaseLabel: String {
        overlaySystem.lifecycle.debugStateLabel
    }

    private var phaseColor: Color {
        switch overlaySystem.lifecycle.state {
        case .idle: return .gray
        case .active: return .green
        case .completing: return .blue
        }
    }

    private var shaderLabel: String {
        guard overlaySystem.shaderDirector.shaderActive else { return "off" }
        let mode = overlaySystem.shaderDirector.shaderMode
        let name = ShaderCatalog.shaders.first(where: { $0.mode == mode })?.name ?? "?"
        return "\(mode) \(name)"
    }

    /// Clickable shader badge that opens a dropdown picker grouped by tier.
    private var shaderPicker: some View {
        Menu {
            let tiers: [ShaderTier] = [.ambient, .flowing, .deep, .highEnergy]
            ForEach(tiers, id: \.self) { tier in
                Section(tier.debugName.capitalized) {
                    ForEach(ShaderCatalog.shaders.filter { $0.tier == tier }, id: \.mode) { shader in
                        Button {
                            overlaySystem.shaderDirector.debugSelectShader(mode: shader.mode)
                        } label: {
                            let mode = overlaySystem.shaderDirector.shaderMode
                            let isCurrent = mode == shader.mode && overlaySystem.shaderDirector.shaderActive
                            Text("\(isCurrent ? "✓ " : "")\(shader.name)")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text("SHADER:")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Text(shaderLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.cyan)
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.cyan.opacity(0.6))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var tierLabel: String {
        let session = overlaySystem.shaderDirector.shaderSession
        guard session.isSessionActive else { return "---" }
        let filled = session.currentTier.rawValue + 1
        let empty = 4 - filled
        return String(repeating: "\u{25AA}", count: filled) + String(repeating: "\u{25AB}", count: empty)
    }

    private var tierColor: Color {
        let session = overlaySystem.shaderDirector.shaderSession
        switch session.currentTier {
        case .ambient: return .gray
        case .flowing: return .cyan
        case .deep: return .blue
        case .highEnergy: return .red
        }
    }

    private var activityLabel: String {
        overlaySystem.activitySummary ?? "---"
    }

    private var sessionDuration: TimeInterval? {
        let session = overlaySystem.shaderDirector.shaderSession
        guard let start = session.sessionStartTime else { return nil }
        return Date().timeIntervalSince(start)
    }

    // MARK: - View Helpers

    private func badge(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label + ":")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func infoChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, design: .monospaced))
            .foregroundColor(.white.opacity(0.6))
    }

    private func statusDot(_ active: Bool, _ label: String) -> some View {
        HStack(spacing: 1) {
            Circle()
                .fill(active ? Color.green : Color.red.opacity(0.4))
                .frame(width: 5, height: 5)
            Text(label)
                .foregroundColor(.white.opacity(0.5))
        }
    }

    private func controlButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.15))
                )
        }
        .buttonStyle(.plain)
    }

    private func simButton(_ label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
#endif
