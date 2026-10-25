import Foundation
import Testing
import Sidebar

private let width: CGFloat = 260

@Test(arguments: [
    (1, 1.4, 0.0, 3, 1),
    (1, 1.6, 0.0, 3, 2),
    (1, 1.1, 300.0, 3, 2),
    (1, 0.9, -300.0, 3, 0),
    (0, -0.2, -500.0, 3, 0),
    (2, 2.3, 900.0, 3, 2),
    (0, 0.4, 40.0, 3, 0),
    (0, 0.1, 300.0, 3, 1),
    (0, 2.9, 0.0, 3, 1),
] as [(Int, CGFloat, CGFloat, Int, Int)])
func pagingTargets(startPage: Int, offsetInPages: CGFloat, velocity: CGFloat, pageCount: Int, expected: Int) {
    let page = targetPage(startPage: startPage, offset: offsetInPages * width, pageWidth: width, velocity: velocity, pageCount: pageCount)
    #expect(page == expected)
}

@Test func swipeNeverSkipsAPage() {
    #expect(targetPage(startPage: 0, offset: 1.9 * width, pageWidth: width, velocity: 5000, pageCount: 5) == 1)
}

@Test func aFlickProjectsHalfASecondOfTravel() {
    // At the usual deceleration a flick travels about half its speed in points before it stops.
    #expect(abs(projectedDistance(velocity: 1000) - 499) < 1)
    #expect(projectedDistance(velocity: -1000) < 0)
    #expect(projectedDistance(velocity: 0) == 0)
}

@Test func aSlowDragSettlesOnTheNearestPageWhateverItsDirection() {
    // Moving backwards slowly from most of the way to the next page still lands on that page.
    #expect(targetPage(startPage: 0, offset: 0.8 * width, pageWidth: width, velocity: -100, pageCount: 3) == 1)
}
