import XCTest
import Combine

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#elseif canImport(fadicode_DEV)
// This fork ships the Debug app as `fadicode DEV`, so the module is
// `fadicode_DEV`. Kept last so upstream's own module names still win.
@testable import fadicode_DEV
#endif

/// orchestrator #69 — the unfocused shader treatment.
///
/// `ShaderDirector.shaderFocused` was read in six places and written in none,
/// so the whole unfocused branch was unreachable. These tests exercise the two
/// seams that now make it reachable: the focus policy, and the director's
/// setter. Both are driven the way the app drives them, not inspected for shape.
@MainActor
final class ShaderFocusRoutingTests: XCTestCase {

    // MARK: - Focus policy

    func testKeyWindowInActiveAppIsFocused() {
        XCTAssertTrue(
            OverlayFocusObserver.windowIsFocused(
                windowIsKey: true, windowIsMain: true,
                appIsActive: true, windowIsVisible: true
            )
        )
    }

    /// Cmd-tab away: the app deactivates. This is the case Adam reported.
    func testInactiveAppIsNeverFocused() {
        XCTAssertFalse(
            OverlayFocusObserver.windowIsFocused(
                windowIsKey: true, windowIsMain: true,
                appIsActive: false, windowIsVisible: true
            ),
            "A stale key window must not keep the focused treatment once the app deactivates"
        )
    }

    /// Two cmux windows side by side: only the key one gets the focused look.
    func testBackgroundWindowOfActiveAppIsUnfocused() {
        XCTAssertFalse(
            OverlayFocusObserver.windowIsFocused(
                windowIsKey: false, windowIsMain: false,
                appIsActive: true, windowIsVisible: true
            )
        )
    }

    /// Space switch / full-screen swipe: the window keeps key and main but is
    /// no longer on screen, so it must read as unfocused.
    func testWindowOnAnotherSpaceIsUnfocused() {
        XCTAssertFalse(
            OverlayFocusObserver.windowIsFocused(
                windowIsKey: true, windowIsMain: true,
                appIsActive: true, windowIsVisible: false
            ),
            "A window parked on an inactive space still claims key; visibility is what disambiguates"
        )
    }

    /// An auxiliary panel (find bar, sheet) taking key must not read as
    /// "the user tabbed away" — the terminal window is still main.
    func testMainButNotKeyStaysFocused() {
        XCTAssertTrue(
            OverlayFocusObserver.windowIsFocused(
                windowIsKey: false, windowIsMain: true,
                appIsActive: true, windowIsVisible: true
            )
        )
    }

    // MARK: - Per-surface focus

    /// A split with two panes: exactly one is focused at a time.
    /// Adam: "it should be when you're just tabbed out of that terminal specifically also."
    func testExactlyOneSurfaceIsFocusedInASplit() {
        let paneA = UUID()
        let paneB = UUID()

        func verdict(for pane: UUID, focused: UUID) -> Bool {
            OverlayFocusObserver.isFocused(
                windowIsKey: true, windowIsMain: true,
                appIsActive: true, windowIsVisible: true,
                mySurfaceID: pane, focusedSurfaceID: focused,
                // The responder lives in exactly one pane's subtree.
                responderInSurface: pane == focused
            )
        }

        XCTAssertTrue(verdict(for: paneA, focused: paneA))
        XCTAssertFalse(verdict(for: paneB, focused: paneA),
                       "The unfocused pane of a split must take the unfocused treatment")

        // Focus moves to the other pane.
        XCTAssertFalse(verdict(for: paneA, focused: paneB))
        XCTAssertTrue(verdict(for: paneB, focused: paneB))
    }

    /// Window focus gates surface focus: when the whole window loses key,
    /// every pane goes unfocused, including the one that owns the responder.
    func testNoSurfaceIsFocusedWhenWindowLosesKey() {
        let paneA = UUID()
        let paneB = UUID()
        for pane in [paneA, paneB] {
            XCTAssertFalse(
                OverlayFocusObserver.isFocused(
                    windowIsKey: false, windowIsMain: false,
                    appIsActive: false, windowIsVisible: true,
                    mySurfaceID: pane, focusedSurfaceID: paneA,
                    responderInSurface: pane == paneA
                ),
                "Tabbing out of the window must unfocus every pane in it"
            )
        }
    }

    /// The responder is ground truth. If it is in this pane, this pane is
    /// focused even when the bookkeeping has not caught up yet.
    func testResponderContainmentWinsOverStaleBookkeeping() {
        let mine = UUID()
        XCTAssertTrue(
            OverlayFocusObserver.surfaceIsFocused(
                mySurfaceID: mine,
                focusedSurfaceID: UUID(),   // stale: says someone else won
                responderInSurface: true
            )
        )
    }

    /// Fresh launch, nothing has claimed focus. Dimming every pane in a key
    /// window would be a worse lie than dimming none.
    func testUnclaimedFocusLeavesSurfacesFocused() {
        XCTAssertTrue(
            OverlayFocusObserver.surfaceIsFocused(
                mySurfaceID: UUID(),
                focusedSurfaceID: nil,
                responderInSurface: false
            )
        )
    }

    /// An overlay whose surface binding has not arrived cannot claim to be the
    /// focused pane once some other pane has.
    func testUnboundSurfaceIsNotFocusedOnceSomeoneElseClaims() {
        XCTAssertFalse(
            OverlayFocusObserver.surfaceIsFocused(
                mySurfaceID: nil,
                focusedSurfaceID: UUID(),
                responderInSurface: false
            )
        )
    }

    // MARK: - Per-surface colour

    /// Adam: "it's not letting you change specifically one terminal's color
    /// instead of the whole workspace." A surface's own colour must win.
    func testSurfaceColorOverridesWorkspaceColor() {
        XCTAssertEqual(
            SurfaceColorStore.effectiveHex(surfaceHex: "#ff0055", workspaceHex: "#7cb342"),
            "#ff0055"
        )
    }

    /// A surface with no colour of its own still follows its workspace, so the
    /// override is additive rather than a replacement of the existing behaviour.
    func testSurfaceWithoutColorFollowsWorkspace() {
        XCTAssertEqual(
            SurfaceColorStore.effectiveHex(surfaceHex: nil, workspaceHex: "#7cb342"),
            "#7cb342"
        )
        XCTAssertNil(SurfaceColorStore.effectiveHex(surfaceHex: nil, workspaceHex: nil))
    }

    /// Two panes in one split can hold different colours at the same time.
    func testTwoSurfacesHoldIndependentColors() {
        let paneA = UUID()
        let paneB = UUID()
        let store = SurfaceColorStore.shared
        defer { store.forget(paneA); store.forget(paneB) }

        store.setColor("#ff0055", for: paneA)
        store.setColor("#00c2ff", for: paneB)

        XCTAssertEqual(store.color(for: paneA), "#ff0055")
        XCTAssertEqual(store.color(for: paneB), "#00c2ff",
                       "Colouring one pane must not repaint its neighbour")
    }

    /// Clearing hands a surface back to its workspace instead of freezing it.
    func testClearingSurfaceColorRestoresWorkspaceDefault() {
        let pane = UUID()
        let store = SurfaceColorStore.shared
        defer { store.forget(pane) }

        store.setColor("#ff0055", for: pane)
        store.setColor(nil, for: pane)
        XCTAssertNil(store.color(for: pane))
        XCTAssertEqual(
            SurfaceColorStore.effectiveHex(
                surfaceHex: store.color(for: pane),
                workspaceHex: "#7cb342"
            ),
            "#7cb342"
        )
    }

    /// A change must announce itself, since the running shader re-tints by
    /// observing rather than by restarting.
    func testSettingColorPostsChangeForThatSurface() {
        let pane = UUID()
        let store = SurfaceColorStore.shared
        defer { store.forget(pane) }

        let posted = expectation(description: "surface color change posted")
        let token = NotificationCenter.default.addObserver(
            forName: SurfaceColorStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { note in
            if note.userInfo?[SurfaceColorStore.surfaceIDKey] as? UUID == pane {
                posted.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        store.setColor("#ff0055", for: pane)
        wait(for: [posted], timeout: 1.0)
    }

    func testColorNormalizationAcceptsBareHexAndRejectsGarbage() {
        XCTAssertEqual(SurfaceColorStore.normalize("FF0055"), "#ff0055")
        XCTAssertEqual(SurfaceColorStore.normalize("#FF0055"), "#ff0055")
        XCTAssertNil(SurfaceColorStore.normalize("#ff00"))
        XCTAssertNil(SurfaceColorStore.normalize("nonsense"))
    }

    // MARK: - Director seam

    func testSetFocusedTogglesPublishedValueAndDebugState() {
        let director = ShaderDirector()
        XCTAssertTrue(director.shaderFocused, "Directors start focused")
        XCTAssertEqual(director.debugState()["focus"], "focused")

        director.setFocused(false)
        XCTAssertFalse(director.shaderFocused)
        XCTAssertEqual(director.debugState()["focus"], "unfocused",
                       "The DEBUG readout must reflect the real value, not a constant")

        director.setFocused(true)
        XCTAssertTrue(director.shaderFocused)
        XCTAssertEqual(director.debugState()["focus"], "focused")
    }

    /// AppKit emits focus notifications in clusters (key + main + occlusion all
    /// fire for one cmd-tab). Republishing on each would thrash SwiftUI.
    func testRedundantSetFocusedDoesNotRepublish() {
        let director = ShaderDirector()
        var publishCount = 0
        let cancellable = director.$shaderFocused.sink { _ in publishCount += 1 }

        let initial = publishCount  // Combine sends the current value on subscribe
        director.setFocused(true)
        director.setFocused(true)
        XCTAssertEqual(publishCount, initial, "Setting the same verdict must not republish")

        director.setFocused(false)
        XCTAssertEqual(publishCount, initial + 1, "A genuine transition must publish exactly once")

        cancellable.cancel()
    }
}
