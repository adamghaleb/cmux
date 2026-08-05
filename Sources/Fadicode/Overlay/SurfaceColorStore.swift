import AppKit

/// Per-surface identity hue.
///
/// Colour used to live only on `Workspace.customColor`, which paints a whole
/// workspace at once — so a single terminal could not be coloured on its own,
/// and (because `propagateOverlayColor` walked a tab-keyed map) split panes
/// never received a colour at all and sat on their startup default forever.
/// See fadi-orchestrator#69 follow-up.
///
/// This is deliberately an *identity* hue rather than a paint setting: a colour
/// belongs to a surface, survives whatever the workspace is doing, and is
/// intended to be the thing a session can be recognised by. That is the seam
/// orchestrator#46 (deterministic fadi colours per session) and #74 (an agent
/// stamping its output with its own terminal's colour) are meant to build on —
/// they should assign into this store rather than inventing a parallel map.
///
/// Main-actor by contract: every reader is a view or an AppKit host.
@MainActor
final class SurfaceColorStore {

    static let shared = SurfaceColorStore()

    /// Posted whenever one surface's colour changes.
    /// `userInfo[surfaceIDKey]` carries the affected surface.
    static let didChangeNotification = Notification.Name("fadicodeSurfaceColorDidChange")
    static let surfaceIDKey = "fadicode.surfaceColor.surfaceID"

    private var hexBySurface: [UUID: String] = [:]

    private init() {}

    /// The surface's own colour, or nil when it simply follows its workspace.
    func color(for surfaceID: UUID) -> String? {
        hexBySurface[surfaceID]
    }

    /// Set (or with nil, clear) one surface's colour.
    ///
    /// Clearing is meaningful: it hands the surface back to the workspace
    /// default rather than freezing it on the last explicit value.
    func setColor(_ hex: String?, for surfaceID: UUID) {
        let normalized = hex.flatMap(Self.normalize)
        guard normalized != hexBySurface[surfaceID] else { return }
        if let normalized {
            hexBySurface[surfaceID] = normalized
        } else {
            hexBySurface.removeValue(forKey: surfaceID)
        }
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: nil,
            userInfo: [Self.surfaceIDKey: surfaceID]
        )
    }

    /// Drop a surface's entry when its terminal goes away, so the map does not
    /// grow for the life of the process.
    func forget(_ surfaceID: UUID) {
        setColor(nil, for: surfaceID)
    }

    /// Which surface wins for this overlay: its own colour, else the workspace's.
    ///
    /// Pure and static so the precedence rule can be tested without a store.
    static func effectiveHex(surfaceHex: String?, workspaceHex: String?) -> String? {
        surfaceHex ?? workspaceHex
    }

    /// Accept `#rrggbb` or `rrggbb`, reject anything `NSColor` cannot read, and
    /// return a canonical `#rrggbb` so equality checks do not miss on case.
    static func normalize(_ hex: String) -> String? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6,
              value.allSatisfy({ $0.isHexDigit }),
              NSColor(hex: "#" + value) != nil
        else { return nil }
        return "#" + value
    }
}
