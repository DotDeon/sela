import Foundation

/// The space page a swipe settles on. Positive velocity, in points per second, moves towards later spaces.
/// A fast swipe moves one page in its direction; a slow one settles on the nearest page.
/// Either way the result is at most one page from `startPage`.
public func targetPage(startPage: Int, offset: CGFloat, pageWidth: CGFloat, velocity: CGFloat, pageCount: Int) -> Int {
    guard pageCount > 0, pageWidth > 0 else { return 0 }
    let target: Int
    if abs(velocity) >= 200 {
        target = startPage + (velocity > 0 ? 1 : -1)
    } else {
        target = Int((offset / pageWidth).rounded())
    }
    let oneStep = min(max(target, startPage - 1), startPage + 1)
    return min(max(oneStep, 0), pageCount - 1)
}
