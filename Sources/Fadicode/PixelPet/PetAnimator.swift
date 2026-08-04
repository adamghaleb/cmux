import SwiftUI
import AppKit
import Combine
import QuartzCore

/// Drives the pixel pet animation — manages state transitions and frame cycling.
/// Uses CADisplayLink (macOS 14+) for vsync-aligned rendering. Pet animations run
/// at 2-8 fps, so the display link is capped at 15 fps to save energy while the
/// accumulator governs actual frame advances at the animation's configured fps.
public class PetAnimator: ObservableObject {
    @Published public private(set) var currentFrame: NSImage?
    @Published public var state: PetState = .idle {
        didSet {
            if oldValue != state {
                transitionTo(state)
            }
        }
    }

    /// Animation speed multiplier (1.0 = normal, 2.0 = double speed).
    @Published public var speed: Double = 1.0

    /// State to return to when a one-shot animation finishes with nothing queued.
    /// Set this to the "ambient" state so celebrations return to what the pet should be doing.
    public var fallbackState: PetState = .idle

    /// Queued state to play immediately after current one-shot finishes.
    private var queuedState: PetState?

    private let spriteSheet: SpriteSheet
    private let animationSet: PetAnimationSet
    private var frameIndex: Int = 0
    private var currentAnimation: PetAnimation?
    private var displayLink: CADisplayLink?
    private var lastFrameTime: CFTimeInterval = 0
    private var accumulated: CFTimeInterval = 0
    private var cachedFrames: [Int: NSImage] = [:]

    public init(spriteSheet: SpriteSheet, animationSet: PetAnimationSet) {
        self.spriteSheet = spriteSheet
        self.animationSet = animationSet
        setupDisplayLink()
        transitionTo(.idle)
    }

    /// Queue a state to play after the current one-shot animation finishes.
    /// If not currently in a one-shot, plays immediately.
    public func playOrQueue(_ newState: PetState) {
        if let anim = currentAnimation, !anim.loops {
            queuedState = newState
        } else {
            state = newState
        }
    }

    /// Replay the current state's animation from the beginning.
    public func replay() {
        transitionTo(state)
    }

    /// Create an animator using the bundled sprite sheet and default animations.
    public static func bundledDefault() -> PetAnimator? {
        guard let sheet = SpriteSheet.bundledDefault() else { return nil }
        return PetAnimator(spriteSheet: sheet, animationSet: .defaultSet)
    }

    // MARK: - Display Link

    private func setupDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired(_:)))
        // Pet animations are 2-8 fps; cap the display link at 15 fps to save energy.
        // The accumulator still governs actual frame advances at the animation's fps.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 2, maximum: 15, preferred: 8)
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        // Use targetTimestamp for better vsync alignment (when the frame will display).
        let now = link.targetTimestamp
        tick(now: now)
    }

    private func tick(now: CFTimeInterval) {
        guard let anim = currentAnimation else {
            lastFrameTime = now
            return
        }

        if lastFrameTime == 0 {
            lastFrameTime = now
            return
        }

        let delta = now - lastFrameTime
        lastFrameTime = now

        let interval = 1.0 / (anim.fps * max(speed, 0.1))
        accumulated += delta

        if accumulated >= interval {
            accumulated -= interval
            if accumulated > interval { accumulated = 0 }
            advanceFrame()
        }
    }

    // MARK: - Animation

    private func transitionTo(_ newState: PetState) {
        frameIndex = 0
        accumulated = 0

        guard let anim = animationSet.animation(for: newState) else { return }
        currentAnimation = anim

        showFrame(anim.frames[0])
    }

    private func advanceFrame() {
        guard let anim = currentAnimation else { return }

        frameIndex += 1

        if frameIndex >= anim.frames.count {
            if anim.loops {
                frameIndex = 0
            } else {
                // One-shot done — check queue before returning to idle
                if let queued = queuedState {
                    queuedState = nil
                    let wasState = state
                    state = queued
                    if wasState == queued {
                        transitionTo(queued)
                    }
                } else {
                    state = fallbackState
                }
                return
            }
        }

        showFrame(anim.frames[frameIndex])
    }

    private func showFrame(_ index: Int) {
        if let cached = cachedFrames[index] {
            currentFrame = cached
        } else if let frame = spriteSheet.frame(at: index) {
            cachedFrames[index] = frame
            currentFrame = frame
        }
    }

    deinit {
        displayLink?.invalidate()
        displayLink = nil
    }
}
