import Foundation
import Combine

/// A panel that displays the Agent Observatory — a system-wide view of all
/// running AI agents across all terminal tabs.
@MainActor
final class AgentObservatoryPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .observatory

    /// Display title shown in tab bar.
    @Published var displayTitle: String = String(
        localized: "observatory.title",
        defaultValue: "Observatory"
    )

    /// SF Symbol icon for the tab bar.
    var displayIcon: String? { "binoculars.fill" }

    /// Token incremented to trigger focus flash animation.
    @Published private(set) var focusFlashToken: Int = 0

    /// The workspace this panel belongs to.
    private(set) var workspaceId: UUID

    init(workspaceId: UUID) {
        self.id = UUID()
        self.workspaceId = workspaceId
    }

    // MARK: - Panel protocol

    func focus() {
        // Observatory is read-only; no first responder to manage.
    }

    func unfocus() {
        // No-op for read-only panel.
    }

    func close() {
        // No resources to clean up.
    }

    func triggerFlash() {
        focusFlashToken += 1
    }
}
