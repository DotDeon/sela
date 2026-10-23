import CoreGraphics
import Foundation
import Testing
import Browsing

@Test func twoEqualPanesSideBySide() {
    let frames = paneFrames(in: CGRect(x: 0, y: 0, width: 1008, height: 600), orientation: .horizontal, fractions: [0.5, 0.5], gap: 8)
    #expect(frames == [CGRect(x: 0, y: 0, width: 500, height: 600), CGRect(x: 508, y: 0, width: 500, height: 600)])
}

@Test func verticalStacksTopToBottomInFlippedSpace() {
    let frames = paneFrames(in: CGRect(x: 0, y: 0, width: 800, height: 1008), orientation: .vertical, fractions: [0.5, 0.5], gap: 8)
    #expect(frames == [CGRect(x: 0, y: 0, width: 800, height: 500), CGRect(x: 0, y: 508, width: 800, height: 500)])
}

@Test func roundingLeavesNoGapAtTheEnd() {
    let third = 1.0 / 3
    let frames = paneFrames(in: CGRect(x: 10, y: 0, width: 1016, height: 600), orientation: .horizontal, fractions: [third, third, third], gap: 8)
    #expect(frames.map(\.width).reduce(0, +) == 1000)
    #expect(frames.last?.maxX == 1026)
    #expect(frames.allSatisfy { $0.minX == $0.minX.rounded() && $0.width == $0.width.rounded() })
}

@Test func draggingMovesOnlyTheNeighbours() {
    let bounds = CGRect(x: 0, y: 0, width: 1016, height: 600)
    let third = 1.0 / 3
    let result = fractions(afterDragging: 0, to: 300, in: bounds, orientation: .horizontal, fractions: [third, third, third], gap: 8, minimum: 240)
    #expect(abs(result.reduce(0, +) - 1) < 0.0001)
    #expect(abs(result[2] - third) < 0.0001)
    #expect(paneFrames(in: bounds, orientation: .horizontal, fractions: result, gap: 8)[0].width == 296)
}

@Test func draggingStopsAtTheMinimum() {
    let bounds = CGRect(x: 0, y: 0, width: 1008, height: 600)
    let result = fractions(afterDragging: 0, to: 10, in: bounds, orientation: .horizontal, fractions: [0.5, 0.5], gap: 8, minimum: 240)
    #expect(paneFrames(in: bounds, orientation: .horizontal, fractions: result, gap: 8)[0].width == 240)
    let other = fractions(afterDragging: 0, to: 1000, in: bounds, orientation: .horizontal, fractions: [0.5, 0.5], gap: 8, minimum: 240)
    #expect(paneFrames(in: bounds, orientation: .horizontal, fractions: other, gap: 8)[1].width == 240)
}
