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

    /// The surface's authoritative agent state. When present it, not the
    /// sprite, decides the status glyph — in particular it is the only thing
    /// that can show `needsInput`.
    /// upstream: PR#6798
    private let agentState: AgentSessionState?

    /// Fraction of each sprite frame that is empty space above the cat.
    ///
    /// Measured from `cat.png`: frames are 32x32 and the cat's alpha bounding
    /// box starts at row 20, so the top 62.5% of every frame is transparent.
    /// At `displaySize: 96` that is 60pt of nothing. Stacking the indicator
    /// above the sprite's *frame* therefore pushed it roughly three times
    /// further from the cat than it looked like it should be — the real reason
    /// the old emoji read as floating. The indicator is instead placed against
    /// the cat's actual head, inside that headroom.
    private static let spriteHeadroom: CGFloat = 20.0 / 32.0

    public init(
        animator: PetAnimator,
        displaySize: CGFloat = 64,
        showIndicator: Bool = true,
        tintColor: NSColor? = nil,
        colorizeConfig: ColorizeConfig = .default,
        agentState: AgentSessionState? = nil
    ) {
        self.animator = animator
        self.displaySize = displaySize
        self.showIndicator = showIndicator
        self.tintColor = tintColor
        self.colorizeConfig = colorizeConfig
        self.agentState = agentState
    }

    // MARK: - Derived layout

    private var indicator: PetStatusIndicator? {
        guard showIndicator else { return nil }
        return PetStatusIndicator.indicator(for: agentState, petState: animator.state)
    }

    /// Scales with the pet but never collapses below a legible size.
    private var iconSize: CGFloat { max(12, displaySize * 0.24) }

    /// A deliberate, tight breathing space between glyph and ears.
    ///
    /// Small because SF Symbols already carry internal padding inside their own
    /// box — measured against the rendered cat, this lands the glyph about six
    /// points off the ears rather than the sixty the old emoji sat at.
    private var gap: CGFloat { max(1, displaySize * 0.02) }

    /// Distance from the top of the sprite frame to the top of the icon, so the
    /// icon's bottom edge lands exactly `gap` above the cat's head.
    private var iconTopInset: CGFloat {
        max(0, displaySize * Self.spriteHeadroom - gap - iconSize)
    }

    /// The session hue, brightened enough to hold up against a bright terminal.
    private var iconTint: Color {
        guard let tintColor else { return .white }
        return Color(nsColor: tintColor)
    }

    public var body: some View {
        // A ZStack, not a VStack: the indicator lives *inside* the sprite's own
        // frame, so the cat never shifts when the glyph appears or disappears.
        ZStack(alignment: .top) {
            spriteLayer

            if let indicator {
                indicatorIcon(indicator)
                    .padding(.top, iconTopInset)
                    .transition(.scale(scale: 0.55).combined(with: .opacity))
            }
        }
        .frame(width: displaySize, height: displaySize)
        .animation(.spring(response: 0.32, dampingFraction: 0.68), value: indicator)
        .onTapGesture {
            animator.playOrQueue(.petted)
        }
    }

    @ViewBuilder
    private var spriteLayer: some View {
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

    private func indicatorIcon(_ indicator: PetStatusIndicator) -> some View {
        Image(systemName: indicator.systemImage)
            .font(.system(size: iconSize * 0.82, weight: .semibold))
            // An explicit box is what pins the glyph. `Text` sized itself by the
            // font's ascender/descender, which is what let the old emoji drift.
            .frame(width: iconSize, height: iconSize)
            .foregroundStyle(iconTint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, options: .repeating,
                          isActive: indicator.motion == .pulse)
            .symbolEffect(.variableColor.iterative.reversing, options: .repeating,
                          isActive: indicator.motion == .variableColor)
            .symbolEffect(.bounce, options: .repeating.speed(0.4),
                          isActive: indicator.motion == .bounce)
            // Two tight shadows form a dark contour, so a light-hued tint still
            // reads against a white terminal without needing a backing chip.
            .shadow(color: .black.opacity(0.55), radius: 1.5, y: 0.5)
            .shadow(color: .black.opacity(0.40), radius: 0.5)
            .accessibilityLabel(indicator.accessibilityLabel)
    }
}
