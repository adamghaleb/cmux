import AppKit
import SwiftUI

/// A colored pill showing the project name in the top-left corner of a terminal pane.
struct ProjectBadgeView: View {
    let projectName: String
    let colorHex: String?

    var body: some View {
        if !projectName.isEmpty {
            Text(projectName)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(textColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(badgeColor.opacity(0.85))
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
    }

    private var badgeNSColor: NSColor {
        guard let hex = colorHex else { return .gray }
        return NSColor(hex: hex) ?? .gray
    }

    private var badgeColor: Color {
        Color(nsColor: badgeNSColor)
    }

    private var textColor: Color {
        .adaptiveText(for: badgeNSColor)
    }
}
