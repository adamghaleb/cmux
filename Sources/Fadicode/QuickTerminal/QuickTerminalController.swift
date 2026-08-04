import AppKit
import SwiftUI
import Combine

/// Position for the quick terminal drop-down panel.
enum QuickTerminalPosition: String, CaseIterable {
    case top, bottom, left, right
}

/// Manages a standalone drop-down terminal panel that slides in from a screen edge.
/// Completely independent from the workspace/tab system — own NSPanel with own Ghostty surface.
@MainActor
final class QuickTerminalController {
    static let shared = QuickTerminalController()

    private var panel: NSPanel?
    private var terminalPanel: TerminalPanel?
    private var hostedScrollView: GhosttySurfaceScrollView?
    private var isVisible = false
    private var cancellables = Set<AnyCancellable>()

    /// Unique workspace ID for the quick terminal (not shown in sidebar)
    private let workspaceId = UUID()

    var position: QuickTerminalPosition {
        QuickTerminalPosition(rawValue: UserDefaults.standard.string(forKey: "QuickTerminalPosition") ?? "top") ?? .top
    }

    var sizePercent: Double {
        let val = UserDefaults.standard.double(forKey: "QuickTerminalSizePercent")
        return val > 0 ? min(max(val, 0.2), 0.9) : 0.4
    }

    private init() {}

    /// Toggle the quick terminal on/off with slide animation.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    private func show() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        if panel == nil {
            createPanel(screenFrame: screenFrame)
        }

        guard let panel else { return }

        // Restore occlusion state so Ghostty resumes the display-link / rendering.
        terminalPanel?.surface.setOcclusion(true)

        let targetFrame = targetFrame(for: screenFrame)
        let offscreenFrame = offscreenFrame(for: screenFrame)

        panel.setFrame(offscreenFrame, display: false)
        panel.orderFrontRegardless()
        isVisible = true

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(targetFrame, display: true)
        }

        // Focus the terminal
        terminalPanel?.focus()
    }

    private func hide() {
        guard let panel, let screen = NSScreen.main else { return }
        let offscreen = offscreenFrame(for: screen.visibleFrame)

        // Immediately unfocus so the surface stops processing input
        terminalPanel?.unfocus()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offscreen, display: true)
        }, completionHandler: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.panel?.orderOut(nil)
                self.isVisible = false

                // Tell Ghostty the surface is fully occluded so it stops the
                // display-link / rendering loop and any associated timers.
                self.terminalPanel?.surface.setOcclusion(false)
            }
        })
    }

    private func createPanel(screenFrame: NSRect) {
        let p = NSPanel(
            contentRect: targetFrame(for: screenFrame),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        p.title = String(localized: "quickTerminal.title", defaultValue: "Quick Terminal")
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.identifier = NSUserInterfaceItemIdentifier("fadicode.quickTerminal")
        p.animationBehavior = .none
        p.backgroundColor = .clear
        p.isOpaque = false

        // Create a terminal panel with a fresh surface
        let terminal = TerminalPanel(workspaceId: workspaceId)
        let scrollView = terminal.hostedView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        guard let contentView = p.contentView else { return }
        let containerView = NSView(frame: contentView.bounds)
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 8
        containerView.layer?.masksToBounds = true
        contentView.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        containerView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        self.panel = p
        self.terminalPanel = terminal
        self.hostedScrollView = scrollView
    }

    private func targetFrame(for screenFrame: NSRect) -> NSRect {
        let size = sizePercent
        switch position {
        case .top:
            let h = screenFrame.height * size
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.maxY - h,
                width: screenFrame.width,
                height: h
            )
        case .bottom:
            let h = screenFrame.height * size
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: screenFrame.width,
                height: h
            )
        case .left:
            let w = screenFrame.width * size
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: w,
                height: screenFrame.height
            )
        case .right:
            let w = screenFrame.width * size
            return NSRect(
                x: screenFrame.maxX - w,
                y: screenFrame.origin.y,
                width: w,
                height: screenFrame.height
            )
        }
    }

    private func offscreenFrame(for screenFrame: NSRect) -> NSRect {
        let target = targetFrame(for: screenFrame)
        switch position {
        case .top:
            return target.offsetBy(dx: 0, dy: target.height)
        case .bottom:
            return target.offsetBy(dx: 0, dy: -target.height)
        case .left:
            return target.offsetBy(dx: -target.width, dy: 0)
        case .right:
            return target.offsetBy(dx: target.width, dy: 0)
        }
    }

    /// Tear down the quick terminal panel and surface.
    func destroy() {
        terminalPanel?.close()
        panel?.close()
        panel = nil
        terminalPanel = nil
        hostedScrollView = nil
        isVisible = false
    }
}
