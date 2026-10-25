import AppKit
import QuartzCore
import Sidebar

/// Sela's timing and spring parameters, in one place so every part moves the same way.
///
/// Anything the user moves with a gesture settles on a spring, critically damped by default, so it never
/// overshoots, and with a little bounce after a flick. Fixed-length animations are kept for fades only.
public enum Motion {
    /// How long a spring takes to settle, roughly: the period of its undamped oscillation.
    public static let response: CGFloat = 0.35
    /// A critically damped spring: no overshoot.
    public static let damping: CGFloat = 1
    /// A slight bounce for a spring that follows a flick.
    public static let flickDamping: CGFloat = 0.8
    /// Points per second above which a gesture counts as a flick.
    public static let flickVelocity: CGFloat = 600

    /// Fades, for things that appear and disappear in place.
    public static let fadeIn: TimeInterval = 0.18
    public static let fadeOut: TimeInterval = 0.12
    /// How far an overlay moves, and how much it grows, while it fades in, so it seems to come from somewhere.
    public static let settleDistance: CGFloat = 8
    public static let settleScale: CGFloat = 0.97

    /// True when the user asked for less motion. Animations that move things become short cross-fades.
    public static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// True when the user asked for solid surfaces instead of translucent ones.
    public static var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }

    /// Where a flick at `velocity` points per second would stop on its own, measured from where it is now.
    public static func projectedDistance(velocity: CGFloat) -> CGFloat {
        Sidebar.projectedDistance(velocity: velocity)
    }

    /// How far past an edge content moves when it's pulled `overshoot` points past it, as on iOS: the further
    /// it's pulled, the less it moves, and it never goes further than `limit`.
    public static func rubberBand(_ overshoot: CGFloat, limit: CGFloat, stiffness: CGFloat = 0.55) -> CGFloat {
        guard overshoot != 0, limit > 0 else { return 0 }
        let distance = abs(overshoot)
        let banded = (1 - (1 / ((distance * stiffness / limit) + 1))) * limit
        return overshoot < 0 ? -banded : banded
    }

    /// A spring animation for a layer property, starting from the value on screen now rather than the target,
    /// so it can take over from an animation still running.
    @MainActor
    public static func springAnimation(_ keyPath: String, on layer: CALayer, to target: Any, velocity: CGFloat = 0,
                                       damping: CGFloat = damping) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath: keyPath)
        animation.fromValue = (layer.presentation() ?? layer).value(forKeyPath: keyPath)
        animation.toValue = target
        animation.initialVelocity = velocity
        animation.damping = 4 * .pi * damping / response
        animation.stiffness = pow(2 * .pi / response, 2)
        animation.mass = 1
        animation.duration = animation.settlingDuration
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        return animation
    }
}

/// One value on a spring: a position that moves towards its target the way a damped spring would, with the
/// velocity it had when the target changed. Change the target at any time and it carries on from where it is.
///
/// The spring is solved in closed form each frame of a display link, so the motion is exact and doesn't depend
/// on the frame rate. The caller applies `value` to whatever is moving in `onChange`.
@MainActor
public final class SpringAnimator {
    public private(set) var value: CGFloat
    public private(set) var velocity: CGFloat = 0
    public private(set) var target: CGFloat
    public var onChange: ((CGFloat) -> Void)?
    public var onSettle: (() -> Void)?

    private let host: NSView
    private var displayLink: CADisplayLink?
    private var response = Motion.response
    private var damping = Motion.damping
    /// The state the current motion started from, and when.
    private var start: (value: CGFloat, velocity: CGFloat, time: CFTimeInterval) = (0, 0, 0)

    /// `host` provides the display link, so animation only runs while it's on screen.
    public init(value: CGFloat, host: NSView) {
        self.value = value
        target = value
        self.host = host
    }

    public var isAnimating: Bool { displayLink != nil }

    /// Starts moving towards `target` from the current value and velocity. `velocity` replaces the current one,
    /// for handing a gesture's speed to the spring. Jumps straight there with Reduce Motion on, or off screen.
    public func animate(to target: CGFloat, velocity: CGFloat? = nil, response: CGFloat = Motion.response, damping: CGFloat = Motion.damping) {
        self.target = target
        if let velocity { self.velocity = velocity }
        if Motion.reduceMotion || host.window?.isVisible != true {
            set(target)
            onSettle?()
            return
        }
        self.response = response
        self.damping = min(max(damping, 0.1), 1)
        start = (value, self.velocity, CACurrentMediaTime())
        if displayLink == nil {
            let link = host.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    /// Stops and puts the value there, with no motion.
    public func set(_ newValue: CGFloat) {
        stop()
        target = newValue
        if value != newValue {
            value = newValue
            onChange?(newValue)
        }
    }

    /// Stops where it is, keeping the value on screen. A gesture taking over calls this first.
    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
        velocity = 0
    }

    @objc private func tick(_ link: CADisplayLink) {
        let elapsed = CGFloat(link.targetTimestamp - start.time)
        let (position, speed) = Self.solve(
            offset: start.value - target, velocity: start.velocity, elapsed: max(elapsed, 0), response: response, damping: damping
        )
        value = target + position
        velocity = speed
        if abs(position) < 0.5 && abs(speed) < 20 {
            displayLink?.invalidate()
            displayLink = nil
            velocity = 0
            value = target
            onChange?(value)
            onSettle?()
        } else {
            onChange?(value)
        }
    }

    /// The spring's displacement from its target and its velocity after `elapsed` seconds, starting `offset`
    /// away and moving at `velocity`. `damping` is the damping ratio: 1 is critically damped, less bounces.
    public nonisolated static func solve(offset: CGFloat, velocity: CGFloat, elapsed t: CGFloat, response: CGFloat, damping zeta: CGFloat) -> (position: CGFloat, velocity: CGFloat) {
        let omega = 2 * .pi / response
        if zeta >= 1 {
            // Critically damped: x = (A + C t) e^(-ω t).
            let c = velocity + omega * offset
            let decay = exp(-omega * t)
            return ((offset + c * t) * decay, (c - omega * (offset + c * t)) * decay)
        }
        let damped = omega * sqrt(1 - zeta * zeta)
        let b = (velocity + zeta * omega * offset) / damped
        let decay = exp(-zeta * omega * t)
        let cosine = cos(damped * t)
        let sine = sin(damped * t)
        let position = decay * (offset * cosine + b * sine)
        let speed = decay * ((-zeta * omega * offset + damped * b) * cosine + (-zeta * omega * b - damped * offset) * sine)
        return (position, speed)
    }
}

/// Fades an overlay in and out along the same path. On the way in it grows a little, from `scale`, and moves
/// from `offset`, as if it came from whatever opened it; on the way out it goes back the same way, from
/// wherever it is on screen at that moment, so a quick open and close never jumps. With Reduce Motion on it
/// only fades. `moving` is the part that grows and moves, when that isn't the whole overlay: a panel over a
/// dimmed backdrop, say.
@MainActor
public enum OverlayTransition {
    public static func appear(_ view: NSView, moving mover: NSView? = nil, scale: CGFloat = Motion.settleScale, offset: CGPoint = .zero) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.add(fade(layer, to: 1, duration: Motion.fadeIn, curve: .easeOut), forKey: "opacity")
        view.alphaValue = 1
        let moving = mover ?? view
        moving.wantsLayer = true
        guard let movingLayer = moving.layer else { return }
        guard !Motion.reduceMotion else {
            movingLayer.transform = CATransform3DIdentity
            return
        }
        // Start from the small, offset shape only when nothing's already on the way in or out.
        if movingLayer.animation(forKey: "transform") == nil {
            movingLayer.transform = transform(scale: scale, offset: offset, in: moving)
        }
        movingLayer.add(Motion.springAnimation("transform", on: movingLayer, to: CATransform3DIdentity), forKey: "transform")
        movingLayer.transform = CATransform3DIdentity
    }

    /// Takes the overlay off screen, then removes it from its superview.
    public static func disappear(_ view: NSView, moving mover: NSView? = nil, scale: CGFloat = Motion.settleScale, offset: CGPoint = .zero) {
        guard let layer = view.layer else {
            view.removeFromSuperview()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            MainActor.assumeIsolated { view.removeFromSuperview() }
        }
        layer.add(fade(layer, to: 0, duration: Motion.fadeOut, curve: .easeIn), forKey: "opacity")
        view.alphaValue = 0
        let moving = mover ?? view
        if !Motion.reduceMotion, let movingLayer = moving.layer {
            let target = transform(scale: scale, offset: offset, in: moving)
            let spring = Motion.springAnimation("transform", on: movingLayer, to: target)
            // The fade is over by then, so the spring needn't settle before the view goes.
            spring.duration = Motion.fadeOut
            movingLayer.add(spring, forKey: "transform")
            movingLayer.transform = target
        }
        CATransaction.commit()
    }

    private static func fade(_ layer: CALayer, to opacity: Float, duration: TimeInterval, curve: CAMediaTimingFunctionName) -> CABasicAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = (layer.presentation() ?? layer).opacity
        fade.toValue = opacity
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: curve)
        return fade
    }

    /// Scales about the view's middle, since a view's layer is anchored at its corner, then moves it by `offset`.
    private static func transform(scale: CGFloat, offset: CGPoint, in view: NSView) -> CATransform3D {
        let center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        var transform = CATransform3DMakeTranslation(center.x + offset.x, center.y + offset.y, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -center.x, -center.y, 0)
    }
}
