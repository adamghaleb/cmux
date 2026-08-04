import SwiftUI

/// Slide-out panel showing metadata about the focused terminal surface.
struct TerminalInspectorView: View {
    let shell: String
    let workingDirectory: String
    let terminalSize: String
    let cellSize: String
    let isReadOnly: Bool
    let onClose: () -> Void
    let onToggleReadOnly: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label(
                    String(localized: "inspector.title", defaultValue: "Terminal Inspector"),
                    systemImage: "info.circle"
                )
                .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "accessibility.inspector.close", defaultValue: "Close terminal inspector"))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    inspectorRow(
                        icon: "terminal",
                        label: String(localized: "inspector.shell", defaultValue: "Shell"),
                        value: shell
                    )

                    inspectorRow(
                        icon: "folder",
                        label: String(localized: "inspector.cwd", defaultValue: "Working Directory"),
                        value: workingDirectory
                    )

                    inspectorRow(
                        icon: "rectangle.split.3x3",
                        label: String(localized: "inspector.size", defaultValue: "Terminal Size"),
                        value: terminalSize
                    )

                    inspectorRow(
                        icon: "square.grid.2x2",
                        label: String(localized: "inspector.cellSize", defaultValue: "Cell Size"),
                        value: cellSize
                    )

                    Divider()

                    HStack {
                        Label(
                            String(localized: "inspector.readOnly", defaultValue: "Read-Only"),
                            systemImage: "lock"
                        )
                        .font(.system(size: 12))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { isReadOnly },
                            set: { _ in onToggleReadOnly() }
                        ))
                        .labelsHidden()
                        .controlSize(.small)
                        .accessibilityLabel(String(localized: "accessibility.inspector.readOnly", defaultValue: "Read-only mode"))
                        .accessibilityHint(String(localized: "accessibility.inspector.readOnlyHint", defaultValue: "Toggles whether the terminal accepts keyboard input"))
                    }
                }
                .padding(14)
            }
        }
        .frame(width: 260)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.3), radius: 8, x: -2, y: 2)
    }

    @ViewBuilder
    private func inspectorRow(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}
