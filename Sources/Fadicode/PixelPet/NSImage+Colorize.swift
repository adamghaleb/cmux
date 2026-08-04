import AppKit

/// Tunable parameters for sprite colorization.
public struct ColorizeConfig: Equatable {
    /// Where in the luminance range the pure tint color sits (0.0–1.0).
    public var midpoint: CGFloat
    /// Exponent applied to the shadow ramp. >1 = deeper/darker shadows, <1 = lifted shadows.
    public var shadowCurve: CGFloat
    /// Exponent applied to the highlight ramp. >1 = highlights stay saturated longer, <1 = wash out faster.
    public var highlightCurve: CGFloat
    /// Post-process saturation multiplier (1.0 = unchanged).
    public var saturation: CGFloat
    /// Post-process contrast multiplier (1.0 = unchanged). Pushes darks darker, lights lighter.
    public var contrast: CGFloat

    public init(
        midpoint: CGFloat = 0.6,
        shadowCurve: CGFloat = 1.0,
        highlightCurve: CGFloat = 1.0,
        saturation: CGFloat = 1.0,
        contrast: CGFloat = 1.0
    ) {
        self.midpoint = midpoint
        self.shadowCurve = shadowCurve
        self.highlightCurve = highlightCurve
        self.saturation = saturation
        self.contrast = contrast
    }

    public static let `default` = ColorizeConfig(
        midpoint: 0.79,
        shadowCurve: 0.70,
        highlightCurve: 1.32,
        saturation: 1.81,
        contrast: 1.51
    )

    public var codeSnippet: String {
        """
        ColorizeConfig(
            midpoint: \(String(format: "%.2f", midpoint)),
            shadowCurve: \(String(format: "%.2f", shadowCurve)),
            highlightCurve: \(String(format: "%.2f", highlightCurve)),
            saturation: \(String(format: "%.2f", saturation)),
            contrast: \(String(format: "%.2f", contrast))
        )
        """
    }
}

extension NSImage {
    /// Colorizes the image while preserving luminosity detail.
    func colorized(with tint: NSColor, config: ColorizeConfig = .default) -> NSImage {
        guard let tintRGB = tint.usingColorSpace(.sRGB) else { return self }
        let tR = tintRGB.redComponent
        let tG = tintRGB.greenComponent
        let tB = tintRGB.blueComponent

        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return self
        }

        let w = cgImage.width
        let h = cgImage.height

        guard let context = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return self }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        guard let data = context.data else { return self }
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)

        let mid = config.midpoint

        for i in 0..<(w * h) {
            let offset = i * 4
            let r = CGFloat(pixels[offset]) / 255.0
            let g = CGFloat(pixels[offset + 1]) / 255.0
            let b = CGFloat(pixels[offset + 2]) / 255.0
            let a = CGFloat(pixels[offset + 3]) / 255.0

            if a < 0.01 { continue }

            let ur = a > 0 ? r / a : 0
            let ug = a > 0 ? g / a : 0
            let ub = a > 0 ? b / a : 0

            let lum = 0.299 * ur + 0.587 * ug + 0.114 * ub

            var newR, newG, newB: CGFloat
            if lum < mid {
                let t = pow(lum / mid, config.shadowCurve)
                newR = tR * t
                newG = tG * t
                newB = tB * t
            } else {
                let t = pow((lum - mid) / (1.0 - mid), config.highlightCurve)
                newR = tR + (1.0 - tR) * t
                newG = tG + (1.0 - tG) * t
                newB = tB + (1.0 - tB) * t
            }

            if config.contrast != 1.0 {
                let pivot: CGFloat = 0.5
                newR = pivot + (newR - pivot) * config.contrast
                newG = pivot + (newG - pivot) * config.contrast
                newB = pivot + (newB - pivot) * config.contrast
            }

            if config.saturation != 1.0 {
                let gray = 0.299 * newR + 0.587 * newG + 0.114 * newB
                newR = gray + (newR - gray) * config.saturation
                newG = gray + (newG - gray) * config.saturation
                newB = gray + (newB - gray) * config.saturation
            }

            newR = min(max(newR, 0), 1)
            newG = min(max(newG, 0), 1)
            newB = min(max(newB, 0), 1)
            pixels[offset]     = UInt8(newR * a * 255)
            pixels[offset + 1] = UInt8(newG * a * 255)
            pixels[offset + 2] = UInt8(newB * a * 255)
        }

        guard let newCG = context.makeImage() else { return self }
        return NSImage(cgImage: newCG, size: size)
    }
}
