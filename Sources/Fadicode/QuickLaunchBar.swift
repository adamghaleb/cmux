import SwiftUI

/// A hoverable bottom bar that expands from a thin pill into quick-launch buttons.
/// Centered at the bottom of each terminal pane. Collapsed by default, expands on hover or focus.
struct QuickLaunchBar: View {
    let projectName: String
    var accentColor: Color?
    let onOpenProjects: () -> Void
    let onOpenWeb: () -> Void
    let onOpenTerminal: () -> Void
    var onOpenObservatory: (() -> Void)?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var hoveredButton: String?
    @FocusState private var focusedButton: String?

    private var accent: Color { accentColor ?? .blue }

    var body: some View {
        Group {
            if isExpanded {
                expandedBar
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
            } else {
                collapsedPill
                    .transition(.opacity.combined(with: .scale(scale: 1.05, anchor: .bottom)))
            }
        }
        .focusable()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isExpanded)
        .onHover { hovering in
            isExpanded = hovering
        }
        .onChange(of: focusedButton) { _, newValue in
            if newValue != nil {
                isExpanded = true
            }
        }
    }

    // MARK: - Collapsed: tiny pill hint

    private var collapsedPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(accent.opacity(0.5))
                .frame(width: 4, height: 4)
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 4, height: 4)
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 4, height: 4)
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 4, height: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
                .opacity(0.4)
        )
        .contentShape(Capsule())
        .accessibilityLabel(String(localized: "accessibility.quickLaunch.collapsed", defaultValue: "Quick launch bar"))
        .accessibilityHint(String(localized: "accessibility.quickLaunch.collapsedHint", defaultValue: "Hover to expand quick launch actions"))
    }

    // MARK: - Expanded: full buttons

    private var expandedBar: some View {
        HStack(spacing: 4) {
            quickButton(
                id: "projects",
                icon: "folder.fill",
                label: String(localized: "quicklaunch.projects", defaultValue: "Projects"),
                shortcutHint: "Cmd+1",
                shortcutKey: "1",
                shortcutModifiers: .command,
                action: onOpenProjects
            )
            quickButton(
                id: "web",
                icon: "globe",
                label: String(localized: "quicklaunch.web", defaultValue: "Web"),
                shortcutHint: "Cmd+2",
                shortcutKey: "2",
                shortcutModifiers: .command,
                action: onOpenWeb
            )
            quickButton(
                id: "observatory",
                icon: "binoculars.fill",
                label: String(localized: "quicklaunch.agents", defaultValue: "Agents"),
                shortcutHint: "Cmd+3",
                shortcutKey: "3",
                shortcutModifiers: .command,
                action: {
                    if let handler = onOpenObservatory {
                        handler()
                    } else {
                        NotificationCenter.default.post(name: .fadicodeOpenObservatory, object: nil)
                    }
                }
            )
            quickButton(
                id: "terminal",
                icon: "plus.rectangle.fill",
                label: String(localized: "quicklaunch.newTab", defaultValue: "New Tab"),
                shortcutHint: "Cmd+4",
                shortcutKey: "4",
                shortcutModifiers: .command,
                action: onOpenTerminal
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial))
        )
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        .contentShape(Capsule())
    }

    private func quickButton(
        id: String,
        icon: String,
        label: String,
        shortcutHint: String,
        shortcutKey: KeyEquivalent,
        shortcutModifiers: EventModifiers,
        action: @escaping () -> Void
    ) -> some View {
        let isHighlighted = hoveredButton == id || focusedButton == id
        return Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isHighlighted ? .primary : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isHighlighted ? Color.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable()
        .focused($focusedButton, equals: id)
        .keyboardShortcut(shortcutKey, modifiers: shortcutModifiers)
        .accessibilityLabel(label)
        .accessibilityHint(
            String(
                localized: "quicklaunch.shortcutHint",
                defaultValue: "Keyboard shortcut: \(shortcutHint)"
            )
        )
        .help("\(label) (\(shortcutHint))")
        .onHover { isHovered in
            hoveredButton = isHovered ? id : nil
        }
    }
}
