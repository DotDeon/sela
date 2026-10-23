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
    (0, 0.4, 199.0, 3, 0),
    (0, 0.1, 200.0, 3, 1),
    (0, 2.9, 0.0, 3, 1),
] as [(Int, CGFloat, CGFloat, Int, Int)])
func pagingTargets(startPage: Int, offsetInPages: CGFloat, velocity: CGFloat, pageCount: Int, expected: Int) {
    let page = targetPage(startPage: startPage, offset: offsetInPages * width, pageWidth: width, velocity: velocity, pageCount: pageCount)
    #expect(page == expected)
}

@Test func swipeNeverSkipsAPage() {
    #expect(targetPage(startPage: 0, offset: 1.9 * width, pageWidth: width, velocity: 5000, pageCount: 5) == 1)
}
