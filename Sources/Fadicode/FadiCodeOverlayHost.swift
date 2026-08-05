import SwiftUI
import AppKit

/// Data model for terminal inspector display.
struct TerminalInspectorData {
    let shell: String
    let workingDirectory: String
    let terminalSize: String
    let cellSize: String
    let isReadOnly: Bool
}

/// NSHostingView bridge that embeds the fadicode overlay system on top of a terminal surface.
/// Add as a subview of the terminal's NSView. Passes through all mouse/keyboard events.
final class FadiCodeOverlayHost: NSView {

    let overlaySystem = FadiCodeOverlaySystem()
    private var hostingView: NSHostingView<AnyView>?

    /// Presentation refresh. NOT a state poll.
    ///
    /// This used to be a 100ms timer that hashed the whole terminal screen and
    /// drove every lifecycle transition off the diff, with an idle backoff
    /// bolted on to make the cost bearable. The state now arrives from
    /// `AgentSessionRegistry` (see LifecycleManager), so this timer only
    /// refreshes what the badge SAYS while the agent is already known to be
    /// working — and `LifecycleManager.poll()` returns immediately when it is
    /// not. 1Hz, no hashing, no backoff bookkeeping.
    /// upstream: PR#6798
    private var presentationTimer: Timer?

    /// Pet animator — created once, driven by PixelPetController mood changes.
    private let petAnimator: PetAnimator? = PetAnimator.bundledDefault()

    /// Supplies the one input `ShaderDirector.shaderFocused` never had.
    ///
    /// One per overlay, so focus resolves at both levels Adam asked for: two
    /// cmux windows side by side each render their own state, and within one
    /// window only the focused pane of a split stays vivid.
    /// See fadi-orchestrator#69.
    private let focusObserver = OverlayFocusObserver()

    /// Whether the debug overlay is visible (stored in projectBadgeState for SwiftUI observability).
    var debugOverlayVisible: Bool {
        get { projectBadgeState.debugOverlayVisible }
        set { projectBadgeState.debugOverlayVisible = newValue }
    }

    /// Whether the project picker overlay is visible (stored in projectBadgeState for SwiftUI observability).
    var projectPickerVisible: Bool {
        get { projectBadgeState.projectPickerVisible }
        set { projectBadgeState.projectPickerVisible = newValue }
    }

    /// Project badge info — updated when the terminal directory changes.
    var projectName: String = "" {
        didSet {
            guard projectName != oldValue else { return }
            projectBadgeState.projectName = projectName
        }
    }
    /// The workspace's colour. A *default*: this surface's own colour, if it has
    /// one, wins over it. See `SurfaceColorStore`.
    var projectColorHex: String? {
        didSet {
            guard projectColorHex != oldValue else { return }
            refreshEffectiveColor()
        }
    }

    /// Push the winning colour into the SwiftUI layer.
    ///
    /// Everything tinted by the session hue — the shader palette, the surface
    /// wash, the pet — reads `projectBadgeState.projectColorHex`, so resolving
    /// precedence in exactly one place keeps them from disagreeing.
    private func refreshEffectiveColor() {
        let surfaceHex = surfaceId.flatMap { SurfaceColorStore.shared.color(for: $0) }
        let effective = SurfaceColorStore.effectiveHex(
            surfaceHex: surfaceHex,
            workspaceHex: projectColorHex
        )
        guard effective != projectBadgeState.projectColorHex else { return }
        projectBadgeState.projectColorHex = effective
    }

    private let projectBadgeState = ProjectBadgeState()

    /// The surface ID this overlay host is attached to (for scoped notifications).
    ///
    /// This is also the deterministic agent-binding key: the same UUID is
    /// injected into every shell this surface spawns as `CMUX_SURFACE_ID`
    /// (GhosttyTerminalView.swift), so any `claude` running here inherits it.
    /// upstream: PR#6798
    var surfaceId: UUID? {
        didSet {
            // Tell the focus observer which pane it is speaking for. Set here
            // rather than at init because the host is put in the view hierarchy
            // before its surface id is known.
            focusObserver.surfaceID = surfaceId
            // The surface's own colour can only be resolved once we know which
            // surface we are.
            refreshEffectiveColor()
            guard let surfaceId else {
                overlaySystem.lifecycle.agentPresent = nil
                Task { @MainActor [weak self] in self?.overlaySystem.lifecycle.unbind() }
                return
            }
            overlaySystem.lifecycle.agentPresent = {
                AgentPresence.shared.isAgentLive(surfaceID: surfaceId)
            }
            // Subscribe this surface's overlay to the deterministic session
            // state. Everything the overlay renders follows from here.
            // upstream: PR#6798
            Task { @MainActor [weak self] in
                self?.overlaySystem.lifecycle.bind(surfaceID: surfaceId)
                // Idempotent; the first surface to appear starts the rail.
                AgentSessionTabRail.shared.start()
            }
        }
    }

    /// Closure to read terminal content for the lifecycle manager's content polling.
    var readTerminalContent: (() -> String)? {
        didSet {
            overlaySystem.lifecycle.readContent = readTerminalContent
        }
    }

    /// Closure to type text into the terminal (for question pill responses).
    var typeIntoTerminal: ((String) -> Void)?

    /// Closure to read terminal inspector data from the panel.
    var readInspectorData: (() -> TerminalInspectorData)?

    /// Closure to toggle read-only mode on the panel.
    var toggleReadOnly: (() -> Void)?

    /// Whether the mouse is in the bottom interactive zone (quick-launch bar area).
    private var mouseInBottomZone = false
    private var bottomTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = bottomTrackingArea {
            removeTrackingArea(existing)
        }
        // Bottom 50px zone — covers the quick-launch bar hover area
        let bottomRect = NSRect(x: 0, y: 0, width: bounds.width, height: 50)
        let area = NSTrackingArea(
            rect: bottomRect,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: ["zone": "bottom"]
        )
        addTrackingArea(area)
        bottomTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        if let info = event.trackingArea?.userInfo as? [String: String],
           info["zone"] == "bottom" {
            mouseInBottomZone = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let info = event.trackingArea?.userInfo as? [String: String],
           info["zone"] == "bottom" {
            mouseInBottomZone = false
        }
    }

    private func setup() {
        let overlayView = FadiCodeOverlayView(
            system: overlaySystem,
            lifecycle: overlaySystem.lifecycle,
            borderGlow: overlaySystem.borderGlow,
            taskFlash: overlaySystem.taskFlash,
            completionPopup: overlaySystem.completionPopup,
            questionDetection: overlaySystem.questionDetection,
            pixelPet: overlaySystem.pixelPet,
            shaderDirector: overlaySystem.shaderDirector,
            petAnimator: petAnimator,
            projectBadgeState: projectBadgeState,
            onQuestionChoice: { [weak self] choice in
                self?.typeIntoTerminal?(choice)
                self?.overlaySystem.onQuestionAnswered()
            },
            onDismissCompletion: { [weak self] in
                self?.overlaySystem.dismissCompletion()
            },
            onRecallCompletion: { [weak self] in
                self?.overlaySystem.recallCompletion()
            },
            onCompletionDone: { [weak self] in
                self?.overlaySystem.onCompletionDone()
            },
            onProjectSelected: { [weak self] path in
                self?.projectPickerVisible = false
                // Shell-escape the path to prevent command injection from special characters
                let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
                self?.typeIntoTerminal?("cd '\(escaped)' && clear\n")
            },
            onOpenBrowser: {
                NotificationCenter.default.post(name: .fadicodeOpenBrowser, object: nil)
            },
            onNewTerminal: {
                NotificationCenter.default.post(name: .fadicodeNewTerminal, object: nil)
            },
            inspectorData: { [weak self] in
                self?.readInspectorData?() ?? TerminalInspectorData(
                    shell: String(localized: "inspector.fallback.unknownShell", defaultValue: "Unknown"), workingDirectory: "~",
                    terminalSize: "—", cellSize: "—", isReadOnly: false
                )
            },
            onToggleReadOnly: { [weak self] in
                self?.toggleReadOnly?()
            }
        )

        let hosting = NSHostingView(rootView: AnyView(overlayView))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)

        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        self.hostingView = hosting

        // Presentation refresh only — see `presentationTimer`.
        presentationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.overlaySystem.lifecycle.poll()
        }

        // Listen for debug overlay toggle notification
        #if DEBUG
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleDebugOverlay),
            name: .fadicodeDebugOverlayToggled,
            object: nil
        )
        #endif

        // Listen for project picker toggle notification (scoped to this surface)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleProjectPicker(_:)),
            name: .fadicodeProjectPickerToggled,
            object: nil
        )

        // Listen for overlay settings changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(overlaySettingsChanged),
            name: .fadicodeOverlaySettingsChanged,
            object: nil
        )

        // Listen for terminal inspector toggle notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleInspector(_:)),
            name: .fadicodeTerminalInspectorToggled,
            object: nil
        )

        // Feed real window focus to the shader. The observer only reports
        // transitions, so this closure runs on genuine focus changes.
        focusObserver.onChange = { [weak self] focused in
            self?.overlaySystem.shaderDirector.setFocused(focused)
        }

        // Re-tint when THIS surface's colour changes. The shader pipeline
        // already reads the hue every frame, so republishing the effective
        // colour is enough to re-tint a running effect in place — no restart.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(surfaceColorChanged(_:)),
            name: SurfaceColorStore.didChangeNotification,
            object: nil
        )
    }

    @objc private func surfaceColorChanged(_ note: Notification) {
        guard let changed = note.userInfo?[SurfaceColorStore.surfaceIDKey] as? UUID,
              changed == surfaceId else { return }
        refreshEffectiveColor()
    }

    /// Re-bind the focus observer whenever this overlay changes windows.
    ///
    /// Surfaces get moved between windows by tab tear-off and by workspace
    /// churn, so binding once at init would leave the shader reading a dead
    /// window's focus. `superview` is the surface's own view subtree — the
    /// terminal view and this overlay are siblings under it — which is what
    /// lets the observer ask whether the first responder is in *this* pane.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusObserver.bind(to: window, surfaceRoot: superview)
        overlaySystem.shaderDirector.setFocused(focusObserver.isFocused)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hostingView else { return nil }
        let pointInSelf = self.convert(point, from: self.superview)

        // Modal overlays consume all hits
        if debugOverlayVisible || projectPickerVisible || projectBadgeState.inspectorVisible {
            return hostingView.hitTest(pointInSelf)
        }

        // Question pill and completion popup are interactive
        if overlaySystem.claudeQuestion != nil || overlaySystem.completionSummary != nil {
            return hostingView.hitTest(pointInSelf)
        }

        // When mouse is in the bottom zone, route ALL events to hosting view
        // so SwiftUI buttons in the quick-launch bar are fully clickable.
        if mouseInBottomZone {
            return hostingView.hitTest(pointInSelf)
        }

        // For pixel pet and other scattered interactive elements:
        // check if hosting view has a real interactive subview at this point.
        if let hit = hostingView.hitTest(pointInSelf),
           hit != hostingView {
            return hit
        }

        // Pass through to the terminal underneath
        return nil
    }

    // MARK: - OSC Signal Handlers

    // OSC 7777 / 7778 are EXPLICIT agent-emitted signals, not inferences, so
    // Gate 2 keeps them — but routes them through the same authority as hooks
    // instead of poking the overlay directly. `AgentSessionRegistry` maps
    // 7778;start onto UserPromptSubmit and 7777 / 7778;stop onto Stop, which
    // means the registry's reducer, its version counter and its exit watcher
    // all see them. The direct lifecycle call is kept only as the visual
    // fast-path for the completion tier, which OSC knows and hooks do not.
    // upstream: PR#6798

    /// Called when OSC 7777 task completion signal arrives.
    func handleTaskCompletion(tier: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let surfaceId = self.surfaceId {
                AgentSessionRegistry.shared.noteExplicitWorkingStopped(surfaceID: surfaceId)
            }
            self.overlaySystem.lifecycle.onResponseComplete(tier: tier)
            // Drive pet celebration
            if let animator = self.petAnimator {
                switch tier {
                case "long": animator.playOrQueue(.celebratingLong)
                case "medium": animator.playOrQueue(.celebratingMedium)
                default: animator.playOrQueue(.celebratingShort)
                }
            }
        }
    }

    /// Called when OSC 7778 working state signal arrives.
    func handleWorkingState(action: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let surfaceId = self.surfaceId else { return }
            if action == "start" {
                AgentSessionRegistry.shared.noteExplicitWorkingStarted(surfaceID: surfaceId)
            } else if action == "stop" {
                AgentSessionRegistry.shared.noteExplicitWorkingStopped(surfaceID: surfaceId)
            }
        }
    }

    #if DEBUG
    @objc private func toggleDebugOverlay() {
        debugOverlayVisible.toggle()
    }
    #endif

    @objc private func toggleProjectPicker(_ notification: Notification) {
        // Only toggle on the targeted surface, or on this surface if it's the key window's first responder
        if let notifSurfaceId = notification.userInfo?["surfaceId"] as? UUID {
            guard notifSurfaceId == surfaceId else { return }
        }
        projectPickerVisible.toggle()
    }

    @objc private func toggleInspector(_ notification: Notification) {
        guard let notifSurfaceId = notification.userInfo?["surfaceId"] as? UUID,
              notifSurfaceId == surfaceId else { return }
        projectBadgeState.inspectorVisible.toggle()
    }

    @objc private func overlaySettingsChanged() {
        // SwiftUI views observe settings via @AppStorage which auto-refreshes.
        // No need to broadcast objectWillChange — individual controllers handle
        // their own observation (GitHub #17).
    }

    deinit {
        presentationTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let fadicodeDebugOverlayToggled = Notification.Name("fadicodeDebugOverlayToggled")
    static let fadicodeProjectPickerToggled = Notification.Name("fadicodeProjectPickerToggled")
    static let fadicodeOverlaySettingsChanged = Notification.Name("fadicodeOverlaySettingsChanged")
    static let fadicodeOpenBrowser = Notification.Name("fadicodeOpenBrowser")
    static let fadicodeNewTerminal = Notification.Name("fadicodeNewTerminal")
    static let fadicodeTerminalInspectorToggled = Notification.Name("fadicodeTerminalInspectorToggled")
    static let fadicodeWorkspaceColorChanged = Notification.Name("fadicodeWorkspaceColorChanged")
    static let fadicodeOpenObservatory = Notification.Name("fadicodeOpenObservatory")
    static let fadicodeObservatoryFocusPanel = Notification.Name("fadicodeObservatoryFocusPanel")
    static let fadicodeObservatoryKillAgent = Notification.Name("fadicodeObservatoryKillAgent")
}

// MARK: - SwiftUI Overlay View

/// Observable state bridged from the AppKit overlay host.
/// Holds project badge info + overlay visibility flags so SwiftUI can observe changes.
final class ProjectBadgeState: ObservableObject {
    @Published var projectName: String = ""
    @Published var projectColorHex: String?
    @Published var projectPickerVisible: Bool = false
    @Published var debugOverlayVisible: Bool = false
    @Published var inspectorVisible: Bool = false
}

/// The SwiftUI view that renders all fadicode overlays on top of the terminal.
///
/// Each sub-controller is observed independently to avoid broadcasting every
/// change across the entire view tree (GitHub #17). Views only redraw when the
/// specific controller they depend on publishes a change.
private struct FadiCodeOverlayView: View {
    /// The system is retained for the debug overlay and facade methods,
    /// but is NOT observed — SwiftUI views observe sub-controllers directly.
    let system: FadiCodeOverlaySystem

    // Observe individual controllers — each only triggers redraws for its own changes
    @ObservedObject var lifecycle: LifecycleManager
    @ObservedObject var borderGlow: BorderGlowController
    @ObservedObject var taskFlash: TaskFlashController
    @ObservedObject var completionPopup: CompletionPopupController
    @ObservedObject var questionDetection: QuestionDetectionController
    @ObservedObject var pixelPet: PixelPetController
    @ObservedObject var shaderDirector: ShaderDirector

    let petAnimator: PetAnimator?
    @ObservedObject var projectBadgeState: ProjectBadgeState
    let onQuestionChoice: (String) -> Void
    let onDismissCompletion: () -> Void
    let onRecallCompletion: () -> Void
    let onCompletionDone: () -> Void
    let onProjectSelected: (String) -> Void
    let onOpenBrowser: () -> Void
    let onNewTerminal: () -> Void
    let inspectorData: () -> TerminalInspectorData
    let onToggleReadOnly: () -> Void

    @AppStorage("FadicodeBadgeVisibility") private var badgeVisibility = "always"
    @AppStorage("FadicodeBorderGlowEnabled") private var borderGlowEnabled = true
    @State private var isBadgeHovered = false

    /// Resolved workspace accent color from the project badge state.
    private var accentNSColor: NSColor? {
        guard let hex = projectBadgeState.projectColorHex else { return nil }
        return NSColor(hex: hex)
    }

    private var accentColor: Color? {
        guard let ns = accentNSColor else { return nil }
        return Color(nsColor: ns)
    }

    private var themeRGB: (r: Double, g: Double, b: Double) {
        guard let ns = accentNSColor else { return (r: 0.1, g: 0.9, b: 0.3) } // default green
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        ns.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: nil)
        return (r: Double(r), g: Double(g), b: Double(b))
    }

    var body: some View {
        ZStack {
            // Workspace color indicator — subtle full-surface tint + top edge strip
            if let accent = accentColor {
                // Full background tint (matches v1 behavior)
                Rectangle()
                    .fill(accent.opacity(0.04))
                    .allowsHitTesting(false)

                // Top edge strip
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(accent)
                        .frame(height: 2)
                        .opacity(0.7)
                    Spacer()
                }
                .allowsHitTesting(false)
            }

            // Shader overlay — full post-process pipeline with palette, transitions, focus
            if #available(macOS 14.0, *) {
                ShaderOverlayView(
                    director: shaderDirector,
                    themeRGB: themeRGB,
                    themeColor: accentNSColor
                )
            }

            // Border glow while Claude is active — tinted with workspace color
            if borderGlow.isActive && borderGlowEnabled {
                BorderGlowView(accentColor: accentColor)
                    .transition(.opacity)
            }

            // Task completion flash
            TaskFlashOverlay(tier: taskFlash.flashTier)

            // Activity badge (top-right)
            if lifecycle.state.isActive || lifecycle.state.isCompleting {
                ActivityBadgeView(
                    state: lifecycle.state,
                    agentState: lifecycle.agentState,
                    summary: lifecycle.activitySummary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 12)
                .padding(.top, 8)
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            // Question detection pill (bottom-center) — tinted with workspace color
            if let question = questionDetection.question {
                QuestionPillView(
                    question: question,
                    onChoice: onQuestionChoice,
                    accentColor: accentColor,
                    accentNSColor: accentNSColor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Completion popup (bottom-right) — tinted with workspace color
            if let summary = completionPopup.completionSummary {
                CompletionPopupView(
                    summary: summary,
                    duration: completionPopup.lastActivityDuration,
                    onDismiss: onDismissCompletion,
                    onDone: onCompletionDone,
                    accentColor: accentColor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if completionPopup.showRecallButton {
                RecallButton(onRecall: onRecallCompletion)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }

            // Pixel pet (bottom-right, above completion popup) — tinted with workspace color
            if let animator = petAnimator,
               UserDefaults.standard.bool(forKey: "FadicodePixelPetEnabled") {
                PixelPetView(
                    animator: animator,
                    displaySize: 96,
                    showIndicator: true,
                    tintColor: accentNSColor,
                    agentState: lifecycle.agentState
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 16)
                .padding(.bottom, completionPopup.completionSummary != nil ? 180 : 16)
                .transition(.scale.combined(with: .opacity))
            }

            // Project badge (top-left) — visibility controlled by settings
            if !projectBadgeState.projectName.isEmpty && badgeVisibility != "never" {
                ProjectBadgeView(
                    projectName: projectBadgeState.projectName,
                    colorHex: projectBadgeState.projectColorHex
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 12)
                .padding(.top, 8)
                .allowsHitTesting(badgeVisibility == "hover")
                .opacity(badgeVisibility == "hover" ? (isBadgeHovered ? 1.0 : 0.0) : 1.0)
                .onHover { hovering in
                    if badgeVisibility == "hover" {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isBadgeHovered = hovering
                        }
                    }
                }
                .transition(.opacity)
            }

            // Quick launch bar (bottom-center, auto-hides)
            QuickLaunchBar(
                projectName: projectBadgeState.projectName,
                accentColor: accentColor,
                onOpenProjects: { projectBadgeState.projectPickerVisible = true },
                onOpenWeb: onOpenBrowser,
                onOpenTerminal: onNewTerminal
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 8)

            // Debug overlay (toggled with Cmd+Shift+D).
            // DebugStateOverlay.swift is entirely `#if DEBUG`, so the call site
            // must be guarded too or Release builds fail to compile.
            #if DEBUG
            if projectBadgeState.debugOverlayVisible {
                DebugStateOverlay(
                    overlaySystem: system,
                    onClose: { projectBadgeState.debugOverlayVisible = false }
                )
            }
            #endif

            // Terminal inspector (toggled via right-click menu)
            if projectBadgeState.inspectorVisible {
                let data = inspectorData()
                TerminalInspectorView(
                    shell: data.shell,
                    workingDirectory: data.workingDirectory,
                    terminalSize: data.terminalSize,
                    cellSize: data.cellSize,
                    isReadOnly: data.isReadOnly,
                    onClose: { projectBadgeState.inspectorVisible = false },
                    onToggleReadOnly: onToggleReadOnly
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Project picker overlay (toggled with Cmd+Ctrl+O)
            if projectBadgeState.projectPickerVisible {
                ProjectPickerOverlay(
                    onSelect: onProjectSelected,
                    onDismiss: { projectBadgeState.projectPickerVisible = false }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: lifecycle.state.isActive)
        .animation(.easeInOut(duration: 0.3), value: lifecycle.state.isCompleting)
        .animation(.easeInOut(duration: 0.25), value: questionDetection.question != nil)
        .animation(.easeInOut(duration: 0.3), value: completionPopup.completionSummary != nil)
        .animation(.easeInOut(duration: 0.2), value: borderGlow.isActive)
        .animation(.easeInOut(duration: 0.25), value: projectBadgeState.projectName)
        .animation(.easeInOut(duration: 0.25), value: projectBadgeState.projectPickerVisible)
        .animation(.easeInOut(duration: 0.25), value: projectBadgeState.inspectorVisible)
        // Drive pet state from mood controller
        .onChange(of: pixelPet.mood) { mood in
            guard let animator = petAnimator else { return }
            switch mood {
            case .idle:
                animator.fallbackState = .idle
                animator.state = .idle
            case .working:
                animator.fallbackState = .working
                animator.state = .working
            case .excited:
                animator.fallbackState = .working
                animator.state = .thinking
            case .celebrating:
                animator.playOrQueue(.celebratingMedium)
            }
        }
    }
}

// MARK: - Border Glow View

private struct BorderGlowView: View {
    var accentColor: Color?
    @State private var pulse = false

    private var primary: Color { accentColor ?? .green }
    private var secondary: Color {
        // Shift hue slightly for a complementary glow
        accentColor.map { $0.opacity(1) } ?? .cyan
    }

    var body: some View {
        Rectangle()
            .strokeBorder(
                LinearGradient(
                    colors: [
                        primary.opacity(pulse ? 0.6 : 0.3),
                        secondary.opacity(pulse ? 0.4 : 0.2),
                        primary.opacity(pulse ? 0.6 : 0.3)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
            .shadow(color: primary.opacity(pulse ? 0.4 : 0.2), radius: pulse ? 12 : 6)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}

// MARK: - Question Pill View

private struct QuestionPillView: View {
    let question: ClaudeQuestion
    let onChoice: (String) -> Void
    var accentColor: Color?
    var accentNSColor: NSColor?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var buttonColor: Color { accentColor ?? .accentColor }
    private var buttonTextColor: Color {
        .adaptiveText(for: accentNSColor ?? .controlAccentColor)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(question.questionText)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                ForEach(Array(question.options.prefix(6).enumerated()), id: \.offset) { _, option in
                    Button {
                        onChoice(option.value)
                    } label: {
                        Text(option.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(buttonTextColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(buttonColor.opacity(0.85))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.label)
                    .accessibilityHint(String(localized: "accessibility.questionPill.optionHint", defaultValue: "Responds to Claude's question with this option"))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(reduceTransparency ? AnyShapeStyle(Color(nsColor: .windowBackgroundColor)) : AnyShapeStyle(.ultraThinMaterial), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
    }
}

// MARK: - Completion Popup View

private struct CompletionPopupView: View {
    let summary: CompletionSummary
    let duration: TimeInterval?
    let onDismiss: () -> Void
    let onDone: () -> Void
    var accentColor: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var showCopied = false

    private var checkColor: Color { accentColor ?? .green }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(checkColor)
                    .font(.system(size: 14))
                Text(String(localized: "overlay.completion.taskComplete", defaultValue: "Task Complete"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                if let dur = duration {
                    Text(formatDuration(dur))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "accessibility.completionPopup.dismiss", defaultValue: "Dismiss completion popup"))
            }

            // What happened
            Text(summary.whatHappened)
                .font(.system(size: 11))
                .foregroundColor(.primary.opacity(0.9))
                .lineLimit(3)

            // What's needed
            if summary.whatNeeded != "Nothing — task complete" {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    Text(summary.whatNeeded)
                        .font(.system(size: 11))
                        .foregroundColor(.primary.opacity(0.8))
                        .lineLimit(2)
                }
            }

            // Suggested prompt
            if let prompt = summary.suggestedPrompt {
                Button {
                    // Copy suggested prompt to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(prompt, forType: .string)
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCopied = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.clipboard")
                            .font(.system(size: 9))
                        Text(showCopied
                            ? String(localized: "completionPopup.copied", defaultValue: "Copied!")
                            : prompt)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(showCopied ? .green : checkColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill((showCopied ? Color.green : checkColor).opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showCopied
                    ? String(localized: "accessibility.completionPopup.copied", defaultValue: "Copied to clipboard")
                    : String(localized: "accessibility.completionPopup.copyPrompt", defaultValue: "Copy suggested prompt"))
                .accessibilityHint(String(localized: "accessibility.completionPopup.copyPromptHint", defaultValue: "Copies the suggested follow-up prompt to the clipboard"))
            }
        }
        .padding(12)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Recall Button

private struct RecallButton: View {
    let onRecall: () -> Void

    var body: some View {
        Button(action: onRecall) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.system(size: 10))
                Text(String(localized: "overlay.recall.button", defaultValue: "Recall"))
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "accessibility.recall.label", defaultValue: "Recall completion summary"))
        .accessibilityHint(String(localized: "accessibility.recall.hint", defaultValue: "Shows the last task completion summary again"))
    }
}

// MARK: - Activity Badge

private struct ActivityBadgeView: View {
    let state: LifecycleState
    /// Authoritative session state; drives the dot colour so "blocked on you"
    /// is visually distinct from "working". upstream: PR#6798
    let agentState: AgentSessionState?
    let summary: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)

            if let summary {
                Text(ContentDetection.phaseDisplayName(summary))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(.primary.opacity(0.8))
            }

            if case .active(let since) = state {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    let elapsed = context.date.timeIntervalSince(since)
                    Text(formatDuration(elapsed))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var dotColor: Color {
        if agentState?.needsAttention == true { return .orange }
        switch state {
        case .idle: return .gray
        case .active: return .green
        case .completing: return .blue
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
