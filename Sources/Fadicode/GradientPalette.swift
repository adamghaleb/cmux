import SwiftUI

// MARK: - Data Model

struct PaletteStop: Identifiable, Equatable {
    let id: UUID
    var color: NSColor
    var position: Float // 0.0–1.0

    init(color: NSColor, position: Float) {
        self.id = UUID()
        self.color = color
        self.position = position
    }

    var rgb: (r: Float, g: Float, b: Float) {
        let c = color.usingColorSpace(.sRGB) ?? color
        return (Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent))
    }
}

struct GradientPalette: Identifiable, Equatable {
    let id: UUID
    let name: String
    var stops: [PaletteStop] // 2–8 stops, sorted by position
    let isBuiltIn: Bool

    init(name: String, stops: [PaletteStop], isBuiltIn: Bool = false) {
        self.id = UUID()
        self.name = name
        self.stops = stops.sorted { $0.position < $1.position }
        self.isBuiltIn = isBuiltIn
    }

    /// Flattened RGB floats for the shader (24 values: 8 stops x 3 channels).
    /// Unused stops repeat the last color.
    func toFloatArray() -> [Float] {
        var result = [Float](repeating: 0, count: 24)
        let sorted = stops.sorted { $0.position < $1.position }
        for i in 0..<8 {
            let stop = i < sorted.count ? sorted[i] : sorted.last!
            let rgb = stop.rgb
            result[i * 3 + 0] = rgb.r
            result[i * 3 + 1] = rgb.g
            result[i * 3 + 2] = rgb.b
        }
        return result
    }

    static func == (lhs: GradientPalette, rhs: GradientPalette) -> Bool {
        lhs.id == rhs.id && lhs.stops == rhs.stops
    }
}


// MARK: - Auto Palette Generator

/// Generates a gradient palette from theme color using warm-cool hue shifting:
/// dark stops lean cool (away from yellow), bright stops lean warm (toward yellow).
/// Contrast controls the power curve on the brightness ramp.
func generateAutoPalette(themeColor: NSColor, hueSpread: Float, complementMix: Float, contrast: Float, saturation: Float, levels: Int) -> GradientPalette {
    let c = themeColor.usingColorSpace(.sRGB) ?? themeColor
    let r = Float(c.redComponent)
    let g = Float(c.greenComponent)
    let b = Float(c.blueComponent)
    let themeHSV = rgbToHSV(r: r, g: g, b: b)
    let baseHue = themeHSV.h
    // Respect the theme's actual saturation — grays/whites/browns stay muted
    let baseSat = max(themeHSV.s, 0.05)

    // Warm-cool direction: find which way yellow (warm) is on the hue circle
    let warmTarget: Float = 0.167
    var toWarm = warmTarget - baseHue
    if toWarm > 0.5 { toWarm -= 1.0 }
    if toWarm < -0.5 { toWarm += 1.0 }
    let warmSign: Float = toWarm >= 0 ? 1.0 : -1.0

    let stopCount = min(max(levels, 3), 8)
    var stops: [PaletteStop] = []

    for i in 0..<stopCount {
        let q = Float(i) / Float(stopCount - 1)
        let position = q

        let topBand = Float(stopCount - 1) / Float(stopCount)
        let bridgeBand = Float(stopCount - 2) / Float(stopCount)

        // Asymmetric warm-cool hue ramp
        let t = q * 2.0 - 1.0
        let hueOffset: Float
        if t >= 0 {
            let warmExtent = min(hueSpread, abs(toWarm))
            hueOffset = warmSign * warmExtent * t
        } else {
            hueOffset = warmSign * hueSpread * t
        }
        let hue = fmodf(baseHue + hueOffset + 1.0, 1.0)

        // Saturation curve
        let satCurve = 1.0 - (t * t) * 0.5
        var sat = baseSat * satCurve
        sat = max(sat, baseSat * 0.3)
        sat = paletteMix(sat * 1.15, sat, paletteSmoothstep(0.0, 0.4, q))
        sat *= paletteMix(1.0, 1.15, max(contrast - 1.0, 0.0))
        sat *= saturation
        sat = min(sat, 1.0)

        // Value ramp with contrast power curve
        let contrastQ = powf(q, contrast)
        var val = paletteMix(0.06, 1.2, contrastQ)
        val = min(max(val, 0.0), 1.0)

        // Top band → white, bridge band → light desaturated
        if q >= topBand {
            sat = 0.0
            val = 1.0
        } else if q >= bridgeBand {
            sat *= 0.3
            val = paletteMix(val, 1.0, 0.65)
        }

        var finalR: Float, finalG: Float, finalB: Float
        (finalR, finalG, finalB) = hsvToRGB(h: hue, s: sat, v: val)

        // Complement blend in highlights
        if complementMix > 0.001 {
            let compHue = fmodf(baseHue + 0.5, 1.0)
            let compSat = baseSat * 0.85
            let (cr, cg, cb) = hsvToRGB(h: compHue, s: compSat, v: val)
            let compBlend = paletteSmoothstep(0.55, 1.0, q) * complementMix
            finalR = paletteMix(finalR, cr, compBlend)
            finalG = paletteMix(finalG, cg, compBlend)
            finalB = paletteMix(finalB, cb, compBlend)
        }

        let nsColor = NSColor(red: CGFloat(finalR), green: CGFloat(finalG), blue: CGFloat(finalB), alpha: 1.0)
        stops.append(PaletteStop(color: nsColor, position: position))
    }

    return GradientPalette(name: "Auto", stops: stops, isBuiltIn: true)
}

// MARK: - Swift-side HSV helpers (mirrors ShaderUtils.h)

private func rgbToHSV(r: Float, g: Float, b: Float) -> (h: Float, s: Float, v: Float) {
    let maxC = max(r, max(g, b))
    let minC = min(r, min(g, b))
    let d = maxC - minC
    var h: Float = 0
    let s = maxC > 0 ? d / maxC : 0
    let v = maxC
    if d > 1e-10 {
        if maxC == r { h = (g - b) / d + (g < b ? 6.0 : 0.0) }
        else if maxC == g { h = (b - r) / d + 2.0 }
        else { h = (r - g) / d + 4.0 }
        h /= 6.0
    }
    return (h, s, v)
}

private func hsvToRGB(h: Float, s: Float, v: Float) -> (Float, Float, Float) {
    let c = v * s
    let x = c * (1.0 - abs(fmodf(h * 6.0, 2.0) - 1.0))
    let m = v - c
    var r: Float = 0, g: Float = 0, b: Float = 0
    let seg = Int(h * 6.0) % 6
    switch seg {
    case 0: r = c; g = x; b = 0
    case 1: r = x; g = c; b = 0
    case 2: r = 0; g = c; b = x
    case 3: r = 0; g = x; b = c
    case 4: r = x; g = 0; b = c
    default: r = c; g = 0; b = x
    }
    return (r + m, g + m, b + m)
}

private func paletteMix(_ a: Float, _ b: Float, _ t: Float) -> Float {
    return a + (b - a) * t
}

private func paletteSmoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let t = min(max((x - edge0) / (edge1 - edge0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)
}
