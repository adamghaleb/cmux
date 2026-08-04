import AppKit

/// A sprite sheet loaded from a PNG, sliced into individual frames.
public struct SpriteSheet {
    public let image: NSImage
    public let frameSize: CGSize
    public let columns: Int
    public let rows: Int
    public let totalFrames: Int

    /// Load a sprite sheet from a bundle resource.
    /// - Parameters:
    ///   - name: Resource file name (without extension)
    ///   - frameSize: Size of each individual frame in the sheet
    ///   - bundle: Bundle to load from (defaults to this package's bundle)
    public init?(named name: String, frameSize: CGSize, bundle: Bundle? = nil) {
        let resolvedBundle = bundle ?? .main
        guard let url = resolvedBundle.url(forResource: name, withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        self.init(image: img, frameSize: frameSize)
    }

    /// Create a sprite sheet from an existing NSImage.
    public init(image: NSImage, frameSize: CGSize) {
        self.image = image
        self.frameSize = frameSize

        let bitmapSize = image.representations.first.map {
            CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
        } ?? image.size

        self.columns = Int(bitmapSize.width / frameSize.width)
        self.rows = Int(bitmapSize.height / frameSize.height)
        self.totalFrames = columns * rows
    }

    /// Load the bundled default sprite sheet (32x32 cat).
    public static func bundledDefault() -> SpriteSheet? {
        SpriteSheet(named: "cat", frameSize: CGSize(width: 32, height: 32))
    }

    /// Extract a single frame as an NSImage.
    public func frame(at index: Int) -> NSImage? {
        guard index >= 0 && index < totalFrames else { return nil }
        let col = index % columns
        let row = index / columns

        let bitmapSize = image.representations.first.map {
            CGSize(width: $0.pixelsWide, height: $0.pixelsHigh)
        } ?? image.size

        // Source rect in the sprite sheet (flipped Y for NSImage)
        let sourceRect = CGRect(
            x: CGFloat(col) * frameSize.width,
            y: bitmapSize.height - CGFloat(row + 1) * frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )

        let frameImage = NSImage(size: frameSize)
        frameImage.lockFocus()
        image.draw(
            in: CGRect(origin: .zero, size: frameSize),
            from: sourceRect,
            operation: .copy,
            fraction: 1.0
        )
        frameImage.unlockFocus()
        return frameImage
    }
}
