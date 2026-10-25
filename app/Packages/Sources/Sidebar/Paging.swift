import Foundation

/// The scroll deceleration used to project a flick, per millisecond. Apple's normal rate for scroll views.
public let pagingDecay: CGFloat = 0.998

/// Where a swipe moving at `velocity` points per second would stop on its own if it were a scroll, measured
/// from where it is now.
public func projectedDistance(velocity: CGFloat, decay: CGFloat = pagingDecay) -> CGFloat {
    (velocity / 1000) * decay / (1 - decay)
}

/// The space page a swipe settles on. Positive velocity, in points per second, moves towards later spaces.
/// The swipe's momentum is projected forward and the pages settle on the one nearest where it would have
/// stopped, so a flick moves on and a slow drag settles on whatever's nearest.
/// Either way the result is at most one page from `startPage`.
public func targetPage(startPage: Int, offset: CGFloat, pageWidth: CGFloat, velocity: CGFloat, pageCount: Int) -> Int {
    guard pageCount > 0, pageWidth > 0 else { return 0 }
    let projected = offset + projectedDistance(velocity: velocity)
    let target = Int((projected / pageWidth).rounded())
    let oneStep = min(max(target, startPage - 1), startPage + 1)
    return min(max(oneStep, 0), pageCount - 1)
}
