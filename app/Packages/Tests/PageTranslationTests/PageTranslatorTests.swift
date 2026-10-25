import BrowserEngine
import FakeEngine
import Foundation
import PageTranslation
import Testing

private let english = Locale.Language(identifier: "en")
private let french = Locale.Language(identifier: "fr")

@MainActor
private func makeTab(text: [String] = ["Bonjour", "Le monde"]) -> FakeTab {
    let tab = FakeEngine().makeTab(url: URL(string: "https://example.fr/")!) as! FakeTab
    tab.finishLoading(title: "Exemple")
    tab.pageTextForTesting = text.enumerated().map { TextSegment(id: $0.offset, text: $0.element) }
    return tab
}

@MainActor @Test func translatesEveryNodeAndReportsDone() async {
    let tab = makeTab()
    let translator = FakeTranslator()
    let page = PageTranslator(tab: tab, translator: translator, from: french, to: english, isOffered: true)
    await page.translate()
    #expect(page.status == .translated)
    #expect(tab.replacedText == [0: "[en] Bonjour", 1: "[en] Le monde"])
    #expect(tab.isWatchingText)
    #expect(translator.prepareCount == 0)
}

@MainActor @Test func showOriginalPutsTheTextBackAndStopsWatching() async {
    let tab = makeTab()
    let page = PageTranslator(tab: tab, translator: FakeTranslator(), from: french, to: english, isOffered: true)
    await page.translate()
    page.showOriginal()
    #expect(page.status == .idle)
    #expect(tab.replacedText.isEmpty)
    #expect(tab.restoreCount == 1)
    #expect(!tab.isWatchingText)
}

@MainActor @Test func progressGrowsBatchByBatch() async throws {
    let tab = makeTab(text: Array(repeating: String(repeating: "a", count: 3000), count: 3))
    let translator = FakeTranslator()
    translator.holds = true
    let page = PageTranslator(tab: tab, translator: translator, from: french, to: english, isOffered: true)
    let run = Task { await page.translate() }
    try await eventually { translator.heldCount == 1 }
    #expect(page.status == .translating(0))
    translator.release()
    try await eventually { translator.heldCount == 1 && translator.batches.count == 2 }
    if case .translating(let fraction) = page.status {
        #expect(abs(fraction - 1.0 / 3) < 0.01)
    } else {
        Issue.record("expected translating, got \(page.status)")
    }
    #expect(tab.replacedText.count == 1)
    translator.release()
    try await eventually { translator.heldCount == 1 }
    translator.release()
    await run.value
    #expect(page.status == .translated)
    #expect(tab.replacedText.count == 3)
}

@MainActor @Test func newTextInThePageIsTranslatedToo() async throws {
    let tab = makeTab()
    let translator = FakeTranslator()
    let page = PageTranslator(tab: tab, translator: translator, from: french, to: english, isOffered: true)
    await page.translate()
    tab.simulateNewText([TextSegment(id: 7, text: "Plus tard")])
    try await eventually { tab.replacedText[7] != nil }
    #expect(tab.replacedText[7] == "[en] Plus tard")
    #expect(page.status == .translated)
}

@MainActor @Test func newTextAfterShowingTheOriginalIsLeftAlone() async throws {
    let tab = makeTab()
    let translator = FakeTranslator()
    let page = PageTranslator(tab: tab, translator: translator, from: french, to: english, isOffered: true)
    await page.translate()
    page.showOriginal()
    tab.simulateNewText([TextSegment(id: 7, text: "Plus tard")])
    try await Task.sleep(for: .milliseconds(50))
    #expect(translator.batches.count == 1)
    #expect(tab.replacedText.isEmpty)
}

@MainActor @Test func unsupportedPairsSaySo() async {
    let tab = makeTab()
    let translator = FakeTranslator()
    translator.availabilityAnswer = .unsupported
    let page = PageTranslator(tab: tab, translator: translator, from: french, to: english, isOffered: true)
    await page.translate()
    #expect(page.status == .unsupported)
    #expect(translator.batches.isEmpty)
    #expect(!tab.isWatchingText)
}

@MainActor @Test func pairsNeedingADownloadPrepareFirst() async {
    let tab = makeTab()
    let translator = FakeTranslator()
    translator.availabilityAnswer = .supported
    let page = PageTranslator(tab: tab, translator: translator, from: french, to: english, isOffered: true)
    await page.translate()
    #expect(translator.prepareCount == 1)
    #expect(page.status == .translated)
}

@MainActor @Test func aDeclinedDownloadLeavesThePageAlone() async {
    let tab = makeTab()
    let translator = FakeTranslator()
    translator.availabilityAnswer = .supported
    translator.prepareFails = true
    let page = PageTranslator(tab: tab, translator: translator, from: french, to: english, isOffered: true)
    await page.translate()
    #expect(page.status == .downloadNeeded)
    #expect(translator.batches.isEmpty)
    // Trying again asks again.
    translator.prepareFails = false
    await page.translate()
    #expect(translator.prepareCount == 2)
    #expect(page.status == .translated)
}

@MainActor @Test func aFailedBatchRestoresThePage() async {
    let tab = makeTab()
    let translator = FakeTranslator()
    translator.translateFails = true
    let page = PageTranslator(tab: tab, translator: translator, from: french, to: english, isOffered: true)
    await page.translate()
    #expect(page.status == .failed)
    #expect(tab.restoreCount == 1)
    #expect(tab.replacedText.isEmpty)
}

@MainActor @Test func showingTheOriginalMidWayStopsTheRest() async throws {
    let tab = makeTab(text: Array(repeating: String(repeating: "a", count: 3000), count: 3))
    let translator = FakeTranslator()
    translator.holds = true
    let page = PageTranslator(tab: tab, translator: translator, from: french, to: english, isOffered: true)
    let run = Task { await page.translate() }
    try await eventually { translator.heldCount == 1 }
    page.showOriginal()
    translator.release()
    await run.value
    #expect(page.status == .idle)
    #expect(translator.batches.count == 1)
    #expect(tab.replacedText.isEmpty)
}

@MainActor @Test func translatingTwiceDoesNothingTheSecondTime() async {
    let tab = makeTab()
    let translator = FakeTranslator()
    let page = PageTranslator(tab: tab, translator: translator, from: french, to: english, isOffered: true)
    await page.translate()
    await page.translate()
    #expect(translator.batches.count == 1)
}

/// Polls every 10 ms for up to 5 seconds.
@MainActor
func eventually(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<500 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}
