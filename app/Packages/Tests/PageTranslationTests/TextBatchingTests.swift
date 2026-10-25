import BrowserEngine
import Foundation
import PageTranslation
import Testing

private func segments(_ texts: [String]) -> [TextSegment] {
    texts.enumerated().map { TextSegment(id: $0.offset, text: $0.element) }
}

@Test func shortTextsShareABatch() {
    let batches = TextBatching.batches(segments(["Un", "deux", "trois"]))
    #expect(batches.count == 1)
    #expect(batches[0].map(\.id) == [0, 1, 2])
}

@Test func batchesFillUpByCharacters() {
    let batches = TextBatching.batches(segments(["aaaa", "bbbb", "cccc", "dd"]), maximumCharacters: 8)
    #expect(batches.map { $0.map(\.text) } == [["aaaa", "bbbb"], ["cccc", "dd"]])
}

@Test func batchesFillUpByCount() {
    let batches = TextBatching.batches(segments(["a", "b", "c", "d", "e"]), maximumCount: 2)
    #expect(batches.map { $0.map(\.id) } == [[0, 1], [2, 3], [4]])
}

@Test func aTextLongerThanABatchGetsItsOwn() {
    let long = String(repeating: "x", count: 50)
    let batches = TextBatching.batches(segments(["short", long, "after"]), maximumCharacters: 20)
    #expect(batches.map { $0.map(\.id) } == [[0], [1], [2]])
}

@Test func nothingMakesNoBatches() {
    #expect(TextBatching.batches([]).isEmpty)
    #expect(TextBatching.characterCount(segments(["ab", "cde"])) == 5)
}
