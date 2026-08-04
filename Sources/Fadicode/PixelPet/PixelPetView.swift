import SwiftUI
import AppKit

/// A SwiftUI view that renders an animated pixel pet sprite.
/// Pixel-perfect rendering with no interpolation — crispy pixels at any display size.
public struct PixelPetView: View {
    @ObservedObject private var animator: PetAnimator
    private let displaySize: CGFloat
    private let showIndicator: Bool
    private let tintColor: NSColor?
    private let colorizeConfig: ColorizeConfig

    public init(
        animator: PetAnimator,
        displaySize: CGFloat = 64,
        showIndicator: Bool = true,
        tintColor: NSColor? = nil,
        colorizeConfig: ColorizeConfig = .default
    ) {
        self.animator = animator
        self.displaySize = displaySize
        self.showIndicator = showIndicator
        self.tintColor = tintColor
        self.colorizeConfig = colorizeConfig
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showIndicator, let indicator = PetStatusIndicator.indicator(for: animator.state) {
                Text(indicator.rawValue)
                    .font(.system(size: displaySize * 0.3))
                    .transition(.scale.combined(with: .opacity))
            }

            if let frame = animator.currentFrame {
                let displayFrame: NSImage = {
                    if let color = tintColor {
                        return frame.colorized(with: color, config: colorizeConfig)
                    }
                    return frame
                }()
                Image(nsImage: displayFrame)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: displaySize, height: displaySize)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: displaySize, height: displaySize)
            }
        }
        .onTapGesture {
            animator.playOrQueue(.petted)
        }
    }
}
