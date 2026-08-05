import AppKit

/// Watches one terminal surface and reports whether its overlay should be drawn
/// in the *focused* treatment.
///
/// This exists because `ShaderDirector.shaderFocused` was declared and read in
/// six places but never once assigned — the entire unfocused shader branch was
/// unreachable. See fadi-orchestrator#69.
///
/// The verdict has two levels, because Adam asked for both:
///
///   1. **Window.** Tab away from fadicode entirely and every surface in the
///      window goes unfocused.
///   2. **Surface.** Focus one pane of a split and the *other* panes go
///      unfocused while it stays vivid.
///
/// Neither level is available from SwiftUI: `controlActiveState` reports the
/// *app's* activation, so it cannot tell one cmux window from another, cannot
/// tell one pane from another, and does not change at all on a space switch.
final class OverlayFocusObserver {

    /// The surface the app most recently gave focus to, app-wide.
    ///
    /// App-wide is the correct scope *because* the window gate sits above it:
    /// only the key window's surfaces are eligible at all, so one global
    /// "who has the caret" is enough to pick the winner inside that window.
    /// Fed by `.ghosttyDidFocusSurface`, which `Workspace` posts on every focus
    /// move — the app's existing focus authority, not a second source of truth.
    private static var focusedSurfaceID: UUID?

    /// Called on the main thread whenever the focus verdict changes.
    /// Fires only on an actual transition, never on every notification.
    var onChange: ((Bool) -> Void)?

    private(set) var isFocused: Bool = true

    /// The surface this overlay belongs to. Set late — `FadiCodeOverlayHost`
    /// learns its id after the view is already in the hierarchy.
    var surfaceID: UUID? {
        didSet {
            guard surfaceID != oldValue else { return }
            recompute()
        }
    }

    private weak var window: NSWindow?
    /// The view whose subtree is this surface. The first responder living
    /// inside it is the ground truth for "the keys land here".
    private weak var surfaceRoot: NSView?
    private var observers: [NSObjectProtocol] = []

    // MARK: - Policy

    /// Does the *window* make this overlay eligible for the focused treatment?
    ///
    /// - Parameters:
    ///   - windowIsKey: This window receives keyboard input.
    ///   - windowIsMain: This window is the app's main window. Kept as a
    ///     fallback so an auxiliary panel taking key (find bar, sheet) does not
    ///     read as "the user tabbed away".
    ///   - appIsActive: cmux is the frontmost app. Guards the case where AppKit
    ///     still reports a stale key window after deactivation.
    ///   - windowIsVisible: The window is on the active space and not fully
    ///     occluded. This is what makes a space switch or a full-screen swipe
    ///     count as unfocused — neither one necessarily resigns key.
    static func windowIsFocused(
        windowIsKey: Bool,
        windowIsMain: Bool,
        appIsActive: Bool,
        windowIsVisible: Bool
    ) -> Bool {
        guard appIsActive, windowIsVisible else { return false }
        return windowIsKey || windowIsMain
    }

    /// Is *this* surface the one the user is working in?
    ///
    /// - Parameters:
    ///   - mySurfaceID: This overlay's surface, or nil before it is bound.
    ///   - focusedSurfaceID: The app's most recently focused surface, or nil if
    ///     nothing has claimed focus yet this launch.
    ///   - responderInSurface: The window's first responder lives in this
    ///     surface's view subtree.
    static func surfaceIsFocused(
        mySurfaceID: UUID?,
        focusedSurfaceID: UUID?,
        responderInSurface: Bool
    ) -> Bool {
        // Ground truth first: whatever the bookkeeping says, this is where the
        // keystrokes are actually going.
        if responderInSurface { return true }
        // Nothing has claimed focus yet (fresh launch, restored window with the
        // responder not yet installed). Dimming every surface in a key window
        // would be a worse lie than dimming none, so stay focused.
        guard let focusedSurfaceID else { return true }
        // An overlay with no surface binding cannot be the focused one.
        guard let mySurfaceID else { return false }
        return mySurfaceID == focusedSurfaceID
    }

    /// The whole verdict. Window eligibility gates surface ownership.
    static func isFocused(
        windowIsKey: Bool,
        windowIsMain: Bool,
        appIsActive: Bool,
        windowIsVisible: Bool,
        mySurfaceID: UUID?,
        focusedSurfaceID: UUID?,
        responderInSurface: Bool
    ) -> Bool {
        guard windowIsFocused(
            windowIsKey: windowIsKey,
            windowIsMain: windowIsMain,
            appIsActive: appIsActive,
            windowIsVisible: windowIsVisible
        ) else { return false }
        return surfaceIsFocused(
            mySurfaceID: mySurfaceID,
            focusedSurfaceID: focusedSurfaceID,
            responderInSurface: responderInSurface
        )
    }

    // MARK: - Lifecycle

    /// Point the observer at a window and the view subtree that is this surface.
    /// Safe to call repeatedly; re-binding to the same window is a no-op, and
    /// `nil` (the view left the hierarchy) tears down.
    func bind(to newWindow: NSWindow?, surfaceRoot newRoot: NSView?) {
        surfaceRoot = newRoot

        guard newWindow !== window else {
            // Same window — the view may just have been re-laid-out, but the
            // window's state can still have moved underneath us.
            recompute()
            return
        }

        teardown()
        window = newWindow
        guard let newWindow else {
            recompute()
            return
        }

        let center = NotificationCenter.default
        let handler: (Notification) -> Void = { [weak self] _ in self?.recompute() }

        // Window-scoped: key and main both move independently.
        for name: NSNotification.Name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: newWindow, queue: .main, using: handler)
            )
        }

        // App-scoped: cmd-tab away without any window notification firing.
        for name: NSNotification.Name in [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main, using: handler)
            )
        }

        // Pane-scoped: the app's own focus authority. Every overlay listens and
        // records the same winner, so the pane that just lost focus learns about
        // it from the same post that told the winner it won.
        observers.append(
            center.addObserver(
                forName: .ghosttyDidFocusSurface,
                object: nil,
                queue: .main
            ) { [weak self] note in
                if let focused = note.userInfo?[GhosttyNotificationKey.surfaceId] as? UUID {
                    OverlayFocusObserver.focusedSurfaceID = focused
                }
                self?.recompute()
            }
        )

        // Space switches are a workspace-level event; the window keeps key.
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main,
                using: handler
            )
        )

        recompute()
    }

    private func teardown() {
        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
            workspaceCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    deinit {
        teardown()
    }

    // MARK: - Evaluation

    /// Re-read the world and publish if the verdict moved.
    ///
    /// Always lands on the main thread: every caller is already a main-queue
    /// notification, but `bind(to:surfaceRoot:)` can be reached from
    /// `viewDidMoveToWindow` during layout, and AppKit state must not be read
    /// off-main.
    func recompute() {
        if Thread.isMainThread {
            recomputeOnMain()
        } else {
            DispatchQueue.main.async { [weak self] in self?.recomputeOnMain() }
        }
    }

    private func recomputeOnMain() {
        let verdict: Bool
        if let window {
            // `occlusionState` is the space/full-screen signal: a window parked
            // on an inactive space reports itself as not visible while happily
            // continuing to claim `isMainWindow`.
            let visible = window.occlusionState.contains(.visible)
            let responder = window.firstResponder as? NSView
            let inSurface: Bool = {
                guard let responder, let surfaceRoot else { return false }
                return responder === surfaceRoot || responder.isDescendant(of: surfaceRoot)
            }()
            verdict = Self.isFocused(
                windowIsKey: window.isKeyWindow,
                windowIsMain: window.isMainWindow,
                appIsActive: NSApp.isActive,
                windowIsVisible: visible,
                mySurfaceID: surfaceID,
                focusedSurfaceID: Self.focusedSurfaceID,
                responderInSurface: inSurface
            )
        } else {
            verdict = false
        }

        guard verdict != isFocused else { return }
        isFocused = verdict
        onChange?(verdict)
    }
}
