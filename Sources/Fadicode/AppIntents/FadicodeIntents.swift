import AppKit
import AppIntents

// MARK: - Error Type

enum FadicodeIntentError: Error, CustomLocalizedStringResourceConvertible {
    case appUnavailable
    case noTerminalFocused

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .appUnavailable:
            "Fadicode is not available."
        case .noTerminalFocused:
            "No terminal is currently focused."
        }
    }
}

// MARK: - New Terminal

@available(macOS 14.0, *)
struct NewTerminalIntent: AppIntent {
    static var title: LocalizedStringResource = "New Terminal"
    static var description = IntentDescription("Create a new terminal tab in Fadicode.")

    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppDelegate.shared, let manager = app.tabManager else {
            throw FadicodeIntentError.appUnavailable
        }
        _ = manager.addTab(select: true)
        return .result()
    }
}

// MARK: - Close Terminal

@available(macOS 14.0, *)
struct CloseTerminalIntent: AppIntent {
    static var title: LocalizedStringResource = "Close Terminal"
    static var description = IntentDescription("Close the currently focused terminal tab.")

    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppDelegate.shared, let manager = app.tabManager else {
            throw FadicodeIntentError.appUnavailable
        }
        guard let workspace = manager.selectedTab else {
            throw FadicodeIntentError.noTerminalFocused
        }
        manager.closeTab(workspace)
        return .result()
    }
}

// MARK: - Focus Terminal

@available(macOS 14.0, *)
struct FocusTerminalIntent: AppIntent {
    static var title: LocalizedStringResource = "Focus Fadicode"
    static var description = IntentDescription("Bring Fadicode to the foreground.")

    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.keyWindow?.makeKeyAndOrderFront(nil)
        return .result()
    }
}

// MARK: - Quick Terminal

@available(macOS 14.0, *)
struct QuickTerminalToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Quick Terminal"
    static var description = IntentDescription("Show or hide the quick drop-down terminal.")

    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickTerminalController.shared.toggle()
        return .result()
    }
}

// MARK: - Input Text

@available(macOS 14.0, *)
struct InputTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Input Text to Terminal"
    static var description = IntentDescription("Send text to the focused terminal as if it was typed.")

    @Parameter(title: "Text", description: "The text to send to the terminal.")
    var text: String

    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let app = AppDelegate.shared, let manager = app.tabManager else {
            throw FadicodeIntentError.appUnavailable
        }
        guard let panel = manager.selectedTerminalPanel else {
            throw FadicodeIntentError.noTerminalFocused
        }
        panel.sendText(text)
        return .result()
    }
}

// MARK: - Shortcuts Provider

@available(macOS 14.0, *)
struct FadicodeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NewTerminalIntent(),
            phrases: [
                "New terminal in \(.applicationName)",
                "Create terminal in \(.applicationName)",
            ],
            shortTitle: "New Terminal",
            systemImageName: "terminal"
        )
        AppShortcut(
            intent: QuickTerminalToggleIntent(),
            phrases: [
                "Toggle quick terminal in \(.applicationName)",
                "Show quick terminal in \(.applicationName)",
            ],
            shortTitle: "Quick Terminal",
            systemImageName: "rectangle.bottomhalf.inset.filled"
        )
        AppShortcut(
            intent: FocusTerminalIntent(),
            phrases: [
                "Focus \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: "Focus Fadicode",
            systemImageName: "terminal.fill"
        )
    }
}
