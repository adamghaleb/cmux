import SwiftUI

/// Renders the active shader effect as an overlay on the terminal.
/// Full pipeline: raw shader → glow dilation → blur → scale → posterize/pixelate with palette colors.
/// Supports shader-to-shader dissolve transitions, focus-aware dimming, and palette transitions.
@available(macOS 14.0, *)
struct ShaderOverlayView: View {
    @ObservedObject var director: ShaderDirector
    let themeRGB: (r: Double, g: Double, b: Double)
    var themeColor: NSColor? = nil
    var surfaceID: UUID = UUID()

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @AppStorage("FadicodePixelationEnabled") private var pixelationEnabled = true
    @AppStorage("FadicodePosterizationEnabled") private var posterizationEnabled = true
    @AppStorage("FadicodeVisualPreset") private var visualPreset = 0

    // Pipeline constants
    private let basePixelSize: Double = 6.0
    private let gridRatio: Double = 0.28
    private let focusedGridRatio: Double = 0.55
    private let posterizeLevels: Double = 7.0
    private let hueSpread: Double = 0.20
    private let complementMix: Double = 0.10
    private let transitionDuration: Double = 1.2

    // Focus opacity targets
    private let unfocusedDim: Double = 0.95
    private let unfocusedShader: Double = 1.0
    private let focusedDim: Double = 0.05
    private let focusedShader: Double = 1.0

    // Animation state
    @State private var dimOpacity: Double = 0.0
    @State private var shaderOpacity: Double = 0.0
    private var intensity: Double { shaderOpacity }
    @State private var activeGridOpacity: Double = 2.5
    @State private var startDate: Date = .now
    @State private var timeOffset: TimeInterval = 0
    @State private var frozenForResize: Bool = false
    @State private var frozenElapsed: TimeInterval = 0
    @State private var pixelSize: Double = 6.0

    // Transition state
    @State private var previousMode: Int? = nil
    @State private var previousTuning: ShaderTuning? = nil
    @State private var transitionStart: Date? = nil
    @State private var lastKnownMode: Int? = nil
    @State private var lastKnownTuning: ShaderTuning = ShaderTuning()

    // Palette state — initialized with an 8-stop grayscale ramp so the shader
    // has valid palette data before onAppear fires (prevents black first frame).
    @State private var paletteFloats: [Float] = Array(repeating: Float(0.5), count: 24)
    @State private var paletteCount: Int = 8
    @State private var previousPaletteFloats: [Float] = []
    @State private var paletteTransitionStart: Date? = nil
    @State private var lastPaletteColorKey: Int = 0
    private let paletteTransitionDuration: TimeInterval = 1.0

    /// Map mode index to Metal shader function name.
    private static let shaderFuncNames: [Int: String] = ShaderCatalog.shaders.reduce(into: [:]) { dict, shader in
        dict[shader.mode] = shader.funcName
    }

    /// Line-based shaders that need glow dilation + blur to fatten thin lines.
    private static let lineShaderIndices: Set<Int> = [39, 46, 58]

    /// Pack RGB into a single Int for change detection.
    private var themeColorKey: Int {
        guard let tc = themeColor else { return 0 }
        let c = tc.usingColorSpace(.sRGB) ?? tc
        return Int(c.redComponent * 10000) * 100_000_000
             + Int(c.greenComponent * 10000) * 10_000
             + Int(c.blueComponent * 10000)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dim layer: darkens terminal when unfocused
                Rectangle()
                    .fill(Color.black)
                    .opacity(dimOpacity)

                // Shader layer
                shaderView
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: geo.size) { newSize in
                let newPixel = Self.adaptivePixelSize(for: newSize, base: basePixelSize)
                if newPixel != pixelSize {
                    pixelSize = newPixel
                    activeGridOpacity = newPixel * (director.shaderFocused ? focusedGridRatio : gridRatio)
                }
            }
            .onAppear {
                let newPixel = Self.adaptivePixelSize(for: geo.size, base: basePixelSize)
                if newPixel != pixelSize {
                    pixelSize = newPixel
                    activeGridOpacity = newPixel * (director.shaderFocused ? focusedGridRatio : gridRatio)
                }
            }
        }
        .opacity(shaderOpacity)
        .blendMode(director.shaderFocused ? .screen : .normal)
        .allowsHitTesting(false)
        .onChange(of: director.shaderActive) { active in
            if active {
                lastKnownMode = director.shaderMode
                lastKnownTuning = director.shaderTuning
                previousMode = director.shaderMode
                previousTuning = director.shaderTuning
                transitionStart = .distantPast
                regeneratePalette()
                startDate = Date(timeIntervalSinceNow: -timeOffset)
                let dimTarget = director.shaderFocused ? focusedDim : unfocusedDim
                let shaderTarget = director.shaderFocused ? focusedShader : unfocusedShader
                let gridTarget = director.shaderFocused ? pixelSize * focusedGridRatio : pixelSize * gridRatio
                withAnimation(reduceMotion ? nil : .easeIn(duration: 0.4)) {
                    dimOpacity = dimTarget
                    shaderOpacity = shaderTarget
                    activeGridOpacity = gridTarget
                }
            } else {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.5)) {
                    dimOpacity = 0.0
                    shaderOpacity = 0.0
                }
            }
        }
        .onChange(of: director.shaderFocused) { focused in
            guard director.shaderActive else { return }
            if focused {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    dimOpacity = focusedDim
                    shaderOpacity = focusedShader
                    activeGridOpacity = pixelSize * focusedGridRatio
                }
            } else {
                withAnimation(reduceMotion ? nil : .easeIn(duration: 0.2)) {
                    dimOpacity = unfocusedDim
                    shaderOpacity = unfocusedShader
                    activeGridOpacity = pixelSize * gridRatio
                }
            }
        }
        .onChange(of: director.shaderMode) { newMode in
            guard shaderOpacity > 0.01 else {
                lastKnownMode = newMode
                lastKnownTuning = director.shaderTuning
                previousMode = newMode
                previousTuning = director.shaderTuning
                transitionStart = .distantPast
                return
            }
            previousMode = lastKnownMode ?? newMode
            previousTuning = lastKnownTuning
            transitionStart = .now
            lastKnownMode = newMode
            lastKnownTuning = director.shaderTuning
        }
        .onChange(of: director.shaderTuning) { newTuning in
            previousTuning = lastKnownTuning
            lastKnownTuning = newTuning
        }
        .onChange(of: director.shaderResizing) { resizing in
            guard director.shaderActive else { return }
            if resizing {
                frozenElapsed = Date().timeIntervalSince(startDate)
                frozenForResize = true
            } else {
                frozenForResize = false
            }
        }
        .onChange(of: themeColorKey) { _ in
            lastPaletteColorKey = themeColorKey
            regeneratePalette(animate: director.shaderActive)
        }
        .onAppear {
            let hash = surfaceID.hashValue
            timeOffset = Double(abs(hash) % 12000) / 100.0
            lastKnownMode = director.shaderMode
            lastKnownTuning = director.shaderTuning
            previousMode = director.shaderMode
            previousTuning = director.shaderTuning
            transitionStart = .distantPast
            activeGridOpacity = director.shaderFocused ? pixelSize * focusedGridRatio : pixelSize * gridRatio
            lastPaletteColorKey = themeColorKey
            regeneratePalette()
            if director.shaderActive {
                startDate = Date(timeIntervalSinceNow: -timeOffset)
                let dimTarget = director.shaderFocused ? focusedDim : unfocusedDim
                let shaderTarget = director.shaderFocused ? focusedShader : unfocusedShader
                withAnimation(reduceMotion ? nil : .easeIn(duration: 0.4)) {
                    dimOpacity = dimTarget
                    shaderOpacity = shaderTarget
                }
            }
        }
    }

    // MARK: - Palette

    private func regeneratePalette(animate: Bool = false) {
        if animate && shaderOpacity > 0.01 {
            previousPaletteFloats = (0..<paletteFloats.count).map { pf($0) }
            paletteTransitionStart = .now
        } else {
            previousPaletteFloats = []
            paletteTransitionStart = nil
        }

        let tc = themeColor ?? NSColor(red: CGFloat(themeRGB.r), green: CGFloat(themeRGB.g), blue: CGFloat(themeRGB.b), alpha: 1.0)
        let palette = generateAutoPalette(
            themeColor: tc, hueSpread: Float(hueSpread),
            complementMix: Float(complementMix), contrast: 1.0,
            saturation: 1.0, levels: Int(posterizeLevels)
        )
        paletteFloats = palette.toFloatArray()
        paletteCount = palette.stops.count
    }

    /// Palette float interpolation with quintic smoothstep for smooth transitions.
    private func pf(_ index: Int, now: Date = .now) -> Float {
        let current = index < paletteFloats.count ? paletteFloats[index] : Float(0.0)
        guard let transStart = paletteTransitionStart,
              index < previousPaletteFloats.count else {
            return current
        }
        let elapsed = now.timeIntervalSince(transStart)
        let raw = min(elapsed / max(paletteTransitionDuration, 0.01), 1.0)
        if raw >= 1.0 { return current }
        let p = raw
        let t = Float(p * p * p * (p * (p * 6.0 - 15.0) + 10.0))
        let prev = previousPaletteFloats[index]
        return prev + (current - prev) * t
    }

    // MARK: - Render Pipeline

    /// Pixel size scales with terminal area: 4px (tiny split) → 16px (full screen).
    private static func adaptivePixelSize(for size: CGSize, base: Double) -> Double {
        let area = size.width * size.height
        let tinyArea: Double = 50_000
        let fullScreen: Double = 1_200_000
        let t = min(max((area - tinyArea) / (fullScreen - tinyArea), 0.0), 1.0)
        return (4.0 + t * 12.0).rounded()
    }

    private var effectivePixelSize: Double {
        pixelationEnabled ? pixelSize : 0.0
    }

    private var effectivePosterizeLevels: Double {
        if visualPreset == 1 { return 4.0 }
        return posterizationEnabled ? posterizeLevels : 0.0
    }

    private var effectivePresetMode: Float {
        Float(visualPreset)
    }

    /// Palette count: focused strips top 2 stops (vivid only), unfocused uses full palette.
    private var effectivePaletteCount: Float {
        let count = paletteCount
        if director.shaderFocused { return Float(max(count - 2, 2)) }
        return Float(count)
    }

    private func rawShaderLayer(modeIndex: Int, elapsed: Double, size: CGSize, contrast: Double = 1.0, brightness: Double = 0.0) -> some View {
        let funcName = Self.shaderFuncNames[modeIndex] ?? "combinedEffect"
        let fn = ShaderLibrary[dynamicMember: funcName]
        return Rectangle()
            .fill(Color.white)
            .frame(width: size.width, height: size.height)
            .colorEffect(
                fn(
                    .float(Float(elapsed)),
                    .float(Float(intensity)),
                    .float(Float(themeRGB.r)),
                    .float(Float(themeRGB.g)),
                    .float(Float(themeRGB.b)),
                    .float(Float(size.width)),
                    .float(Float(size.height)),
                    .float(Float(effectivePixelSize)),
                    .float(Float(activeGridOpacity)),
                    .float(Float(effectivePosterizeLevels)),
                    .float(Float(hueSpread)),
                    .float(Float(complementMix)),
                    .float(Float(contrast)),
                    .float(Float(brightness))
                )
            )
            .drawingGroup()
    }

    /// Raw shader + glow dilation (for line shaders) + blur, before post-processing.
    private func blurredRawLayer(modeIndex: Int, elapsed: Double, size: CGSize, contrast: Double = 1.0, brightness: Double = 0.0) -> some View {
        let scaledPixel = effectivePixelSize
        let needsLineGlow = Self.lineShaderIndices.contains(modeIndex)
        let glowR = (needsLineGlow && scaledPixel > 1) ? scaledPixel * 0.6 : 0.0
        let glowOff = CGSize(width: max(glowR + 1, 1), height: max(glowR + 1, 1))
        let blurR = (needsLineGlow && scaledPixel > 1) ? scaledPixel * 0.12 : 0.0
        return rawShaderLayer(modeIndex: modeIndex, elapsed: elapsed, size: size, contrast: contrast, brightness: brightness)
            .layerEffect(
                ShaderLibrary.glowDilateEffect(.float(Float(glowR))),
                maxSampleOffset: glowOff
            )
            .blur(radius: blurR)
            .drawingGroup()
    }

    /// Post-process: posterize/pixelate with palette colors.
    private func postProcess<V: View>(_ view: V, size: CGSize, now: Date = .now) -> some View {
        let effectivePixel = effectivePixelSize
        let maxOff = CGSize(width: max(effectivePixel, 1), height: max(effectivePixel, 1))
        return view
            .frame(width: size.width, height: size.height)
            .drawingGroup()
            .layerEffect(
                ShaderLibrary.posterizePixelateEffect(
                    .float(Float(effectivePixel)),
                    .float(Float(activeGridOpacity)),
                    .float(Float(effectivePosterizeLevels)),
                    .float(effectivePresetMode),
                    .float(effectivePaletteCount),
                    .float(pf(0,  now: now)), .float(pf(1,  now: now)), .float(pf(2,  now: now)),
                    .float(pf(3,  now: now)), .float(pf(4,  now: now)), .float(pf(5,  now: now)),
                    .float(pf(6,  now: now)), .float(pf(7,  now: now)), .float(pf(8,  now: now)),
                    .float(pf(9,  now: now)), .float(pf(10, now: now)), .float(pf(11, now: now)),
                    .float(pf(12, now: now)), .float(pf(13, now: now)), .float(pf(14, now: now)),
                    .float(pf(15, now: now)), .float(pf(16, now: now)), .float(pf(17, now: now)),
                    .float(pf(18, now: now)), .float(pf(19, now: now)), .float(pf(20, now: now)),
                    .float(pf(21, now: now)), .float(pf(22, now: now)), .float(pf(23, now: now))
                ),
                maxSampleOffset: maxOff
            )
    }

    // MARK: - Shader View

    private var shaderView: some View {
        TimelineView(.animation(paused: frozenForResize)) { timeline in
            let baseElapsed: TimeInterval = {
                if frozenForResize { return frozenElapsed }
                return timeline.date.timeIntervalSince(startDate)
            }()

            let currentMode = lastKnownMode ?? director.shaderMode
            let currentTuning = lastKnownTuning
            let currentElapsed = baseElapsed * currentTuning.speedMultiplier
            let currentContrast = currentTuning.contrast
            let currentBrightness = currentTuning.brightness

            // Dissolve progress (0 = show previous, 1 = show current) with quintic smoothstep
            let progress: Float = {
                guard let transStart = transitionStart else { return 1.0 }
                let transElapsed = (frozenForResize
                    ? Date(timeIntervalSince1970: frozenElapsed + startDate.timeIntervalSince1970)
                    : timeline.date
                ).timeIntervalSince(transStart)
                let raw = min(transElapsed / max(transitionDuration, 0.01), 1.0)
                let p = raw
                return Float(p * p * p * (p * (p * 6.0 - 15.0) + 10.0))
            }()

            let prevMode = previousMode ?? currentMode
            let prevTuning = previousTuning ?? currentTuning
            let prevElapsed = baseElapsed * prevTuning.speedMultiplier
            let prevContrast = prevTuning.contrast
            let prevBrightness = prevTuning.brightness

            GeometryReader { geo in
                let size = geo.size

                postProcess(
                    ZStack {
                        blurredRawLayer(modeIndex: prevMode, elapsed: prevElapsed, size: size, contrast: prevContrast, brightness: prevBrightness)
                            .colorEffect(
                                ShaderLibrary.lumaDissolveOut(.float(progress))
                            )

                        blurredRawLayer(modeIndex: currentMode, elapsed: currentElapsed, size: size, contrast: currentContrast, brightness: currentBrightness)
                            .colorEffect(
                                ShaderLibrary.lumaRevealEffect(.float(progress))
                            )
                    }
                    .drawingGroup(),
                    size: size,
                    now: timeline.date
                )
            }
        }
    }
}
