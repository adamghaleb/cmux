import AppKit
import SwiftUI

/// Individual agent card showing status, duration, and quick actions.
struct AgentCardView: View {
    let agent: AgentSnapshot
    let onFocus: (AgentSnapshot) -> Void
    let onKill: (AgentSnapshot) -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: agent type + status indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(agent.agentType.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                if let duration = agent.durationString {
                    Text(duration)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            // State label
            Text(stateLabel)
                .font(.system(size: 11))
                .foregroundColor(stateColor)

            // Activity summary or last line
            if let summary = agent.activitySummary ?? agent.lastLine {
                Text(summary)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(2)
                    .truncationMode(.tail)
            }

            // Workspace badge
            HStack(spacing: 4) {
                if let color = agent.workspaceColor {
                    Circle()
                        .fill(Color(hex: color) ?? .blue)
                        .frame(width: 6, height: 6)
                }
                Text(agent.workspaceTitle)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            // Quick actions (visible on hover)
            if isHovered {
                HStack(spacing: 8) {
                    actionButton(
                        label: String(localized: "observatory.action.focus", defaultValue: "Focus"),
                        icon: "eye",
                        action: { onFocus(agent) }
                    )

                    if agent.state.isWaiting {
                        actionButton(
                            label: String(localized: "observatory.action.answer", defaultValue: "Answer"),
                            icon: "text.bubble",
                            action: { onFocus(agent) }
                        )
                    }

                    if agent.state.isActive || agent.state.isWaiting {
                        actionButton(
                            label: String(localized: "observatory.action.stop", defaultValue: "Stop"),
                            icon: "stop.fill",
                            color: .red.opacity(0.8),
                            action: { onKill(agent) }
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered
                    ? Color.primary.opacity(0.08)
                    : Color.primary.opacity(0.04)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(statusColor.opacity(isHovered ? 0.4 : 0.15), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - Action Button

    private func actionButton(
        label: String,
        icon: String,
        color: Color = .accentColor,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - State Display

    private var statusColor: Color {
        switch agent.state {
        case .active: return .green
        case .waitingForInput: return .orange
        case .completing: return .blue
        case .error: return .red
        case .idle: return .secondary.opacity(0.5)
        }
    }

    private var stateLabel: String {
        switch agent.state {
        case .active:
            return String(localized: "observatory.state.active", defaultValue: "active")
        case .waitingForInput:
            return agent.isQuestion
                ? String(localized: "observatory.state.question", defaultValue: "question")
                : String(localized: "observatory.state.waiting", defaultValue: "waiting")
        case .completing(let tier, _):
            return String(
                localized: "observatory.state.completing",
                defaultValue: "completing (\(tier.rawValue))"
            )
        case .error:
            return String(localized: "observatory.state.error", defaultValue: "error")
        case .idle:
            return String(localized: "observatory.state.idle", defaultValue: "idle")
        }
    }

    private var stateColor: Color {
        switch agent.state {
        case .active: return .green.opacity(0.9)
        case .waitingForInput: return .orange.opacity(0.9)
        case .completing: return .blue.opacity(0.9)
        case .error: return .red.opacity(0.9)
        case .idle: return .secondary
        }
    }
}

// MARK: - Color Extensions

extension Color {
    /// Returns white or black text color based on background luminance.
    static func adaptiveText(for backgroundColor: NSColor) -> Color {
        let converted = backgroundColor.usingColorSpace(.sRGB) ?? backgroundColor
        let luminance = 0.299 * converted.redComponent + 0.587 * converted.greenComponent + 0.114 * converted.blueComponent
        return luminance > 0.5 ? .black : .white
    }

    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.hasPrefix("#") ? String(hexSanitized.dropFirst()) : hexSanitized

        guard hexSanitized.count == 6,
              let rgb = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
