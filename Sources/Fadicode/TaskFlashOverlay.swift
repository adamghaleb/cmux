import SwiftUI
import AppKit

/// Full-surface flash overlay triggered by OSC 7777 task completion signals.
/// Shows a white flash for short tasks, colored flash + border glow for medium/long.
struct TaskFlashOverlay: View {
    let tier: String?
    var themeColor: NSColor? = nil

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State private var flashOpacity: Double = 0
    @State private var borderOpacity: Double = 0
    @State private var fillColor: Color = .clear
    @State private var borderWidth: CGFloat = 0
    @State private var glowRadius1: CGFloat = 0
    @State private var glowRadius2: CGFloat = 0

    private var celebrationColor: Color {
        if let tc = themeColor { return Color(nsColor: tc) }
        return Color(red: 0.1, green: 0.9, blue: 0.3)
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(fillColor)
                .opacity(flashOpacity)

            Rectangle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            fillColor,
                            fillColor.opacity(0.3),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 500
                    )
                )
                .opacity(borderOpacity * 0.8)

            Rectangle()
                .strokeBorder(fillColor, lineWidth: borderWidth)
                .shadow(color: fillColor, radius: glowRadius1)
                .shadow(color: fillColor.opacity(0.4), radius: glowRadius2)
                .opacity(borderOpacity)
        }
        .allowsHitTesting(false)
        .onChange(of: tier) { newTier in
            if let t = newTier {
                let isShort = t == "short"
                let isLong = t == "long"
                fillColor = isShort ? .white : celebrationColor
                borderWidth = isLong ? 6 : 4
                glowRadius1 = isLong ? 40 : 20
                glowRadius2 = isLong ? 70 : 40

                let mo: Double = isShort ? 0.12 : (isLong ? 0.7 : 0.45)
                let bo: Double = isShort ? 0.0 : (isLong ? 1.0 : 0.7)
                let hold: Double = isShort ? 0.0 : (isLong ? 0.8 : 0.2)
                let fade: Double = isShort ? 0.25 : (isLong ? 3.0 : 0.8)

                withAnimation(reduceMotion ? nil : .easeIn(duration: 0.08)) {
                    flashOpacity = mo
                    borderOpacity = bo
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: fade)) {
                        flashOpacity = 0
                        borderOpacity = 0
                    }
                }
            } else {
                flashOpacity = 0
                borderOpacity = 0
            }
        }
    }

    // MARK: - Completion Sound

    private static var activeSounds: [NSSound] = []

    static func playCompletionSound(tier: String) {
        guard UserDefaults.standard.bool(forKey: "FadicodeCompletionSoundEnabled") else { return }
        activeSounds.removeAll { !$0.isPlaying }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("fadicode/sounds/\(tier).wav").path
        let sound: NSSound?
        if FileManager.default.fileExists(atPath: appSupport) {
            sound = NSSound(contentsOfFile: appSupport, byReference: false)
        } else {
            switch tier {
            case "short":
                sound = NSSound(named: "Pop")
            case "medium":
                sound = NSSound(named: "Glass")
            case "long":
                sound = NSSound(named: "Hero")
            default:
                sound = NSSound(named: "Pop")
            }
        }
        if tier == "long" {
            sound?.volume = 0.5
        }
        if let sound = sound {
            activeSounds.append(sound)
            sound.play()
        }
    }
}
