import Foundation
import Testing
@testable import SidebarUI

@Test func aCriticallyDampedSpringSettlesWithoutCrossingItsTarget() {
    var lowest = CGFloat.infinity
    for step in 0...100 {
        let t = CGFloat(step) / 100
        let (position, _) = SpringAnimator.solve(offset: 100, velocity: 0, elapsed: t, response: 0.35, damping: 1)
        lowest = min(lowest, position)
    }
    #expect(lowest >= 0)
    let (end, speed) = SpringAnimator.solve(offset: 100, velocity: 0, elapsed: 1, response: 0.35, damping: 1)
    #expect(abs(end) < 0.5)
    #expect(abs(speed) < 20)
}

@Test func aSpringStartsAtItsOffsetAndVelocity() {
    let (position, speed) = SpringAnimator.solve(offset: 40, velocity: -300, elapsed: 0, response: 0.35, damping: 1)
    #expect(position == 40)
    #expect(speed == -300)
    let bouncy = SpringAnimator.solve(offset: 40, velocity: -300, elapsed: 0, response: 0.35, damping: 0.8)
    #expect(abs(bouncy.position - 40) < 0.0001)
    #expect(abs(bouncy.velocity + 300) < 0.0001)
}

@Test func aFlickedSpringOvershootsALittleThenSettles() {
    var crossed = false
    for step in 0...100 {
        let t = CGFloat(step) / 100
        let (position, _) = SpringAnimator.solve(offset: 100, velocity: -2000, elapsed: t, response: 0.35, damping: 0.8)
        if position < -1 { crossed = true }
    }
    #expect(crossed)
    let (end, _) = SpringAnimator.solve(offset: 100, velocity: -2000, elapsed: 1.5, response: 0.35, damping: 0.8)
    #expect(abs(end) < 0.5)
}

@Test func rubberBandGivesLessAndLessAndNeverPassesItsLimit() {
    let short = Motion.rubberBand(20, limit: 80)
    let long = Motion.rubberBand(200, limit: 80)
    let further = Motion.rubberBand(2000, limit: 80)
    #expect(short > 0 && short < 20)
    #expect(long > short && long < 80)
    #expect(further > long && further < 80)
    #expect(Motion.rubberBand(-20, limit: 80) == -short)
    #expect(Motion.rubberBand(0, limit: 80) == 0)
}
