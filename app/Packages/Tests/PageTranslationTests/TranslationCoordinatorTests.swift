import BrowserEngine
import FakeEngine
import Foundation
import PageTranslation
import Testing

private let english = Locale.Language(identifier: "en")
private let french = Locale.Language(identifier: "fr")
private let frenchText = String(repeating: "Le gouvernement a annoncé mardi une série de mesures pour soutenir les agriculteurs. ", count: 3)

@MainActor
private struct Harness {
    let engine = FakeEngine()
    let translator = FakeTranslator()
    let coordinator: TranslationCoordinator
    let settings: TranslationSettings
    let memory: NeverTranslateMemory

    init(offers: Bool = true) {
        let name = "TranslationCoordinatorTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = TranslationSettings(defaults: defaults)
        settings.targetLanguage = english
        settings.offersTranslation = offers
        memory = NeverTranslateMemory(defaults: defaults)
        coordinator = TranslationCoordinator(settings: settings, memory: memory)
        coordinator.translator = translator
        coordinator.preferredLanguages = { [english] }
    }

    /// A tab that has loaded a page declaring `language`, reported to the coordinator the way a window would.
    func loadedTab(language: String, url: String = "https://example.fr/", text: String = frenchText) async throws -> FakeTab {
        let tab = engine.makeTab(url: URL(string: url)!) as! FakeTab
        tab.languageSampleForTesting = PageLanguageSample(declared: language, text: text)
        coordinator.tabStateDidChange(tab)
        tab.finishLoading(title: "Page")
        coordinator.tabStateDidChange(tab)
        try await Task.sleep(for: .milliseconds(50))
        return tab
    }
}

@MainActor @Test func pagesInOtherLanguagesGetATranslatorAndAnOffer() async throws {
    let harness = Harness()
    let tab = try await harness.loadedTab(language: "fr")
    let translator = try #require(harness.coordinator.translator(for: tab))
    #expect(translator.isOffered)
    #expect(translator.sourceLanguage.isSameLanguage(as: french))
    #expect(translator.targetLanguage == english)
}

@MainActor @Test func pagesInTheUsersLanguageGetNothing() async throws {
    let harness = Harness()
    let tab = try await harness.loadedTab(language: "en-US", text: "Hello there, this is a page in English about rivers and towns.")
    #expect(harness.coordinator.translator(for: tab) == nil)
}

@MainActor @Test func unsupportedPairsGetNothing() async throws {
    let harness = Harness()
    harness.translator.availabilityAnswer = .unsupported
    let tab = try await harness.loadedTab(language: "fr")
    #expect(harness.coordinator.translator(for: tab) == nil)
}

@MainActor @Test func withOffersOffTheMenuStillWorks() async throws {
    let harness = Harness(offers: false)
    let tab = try await harness.loadedTab(language: "fr")
    let translator = try #require(harness.coordinator.translator(for: tab))
    #expect(!translator.isOffered)
}

@MainActor @Test func dismissingTwiceRemembersTheLanguage() async throws {
    let harness = Harness()
    let first = try await harness.loadedTab(language: "fr")
    #expect(!harness.coordinator.dismissOffer(for: first))
    #expect(harness.coordinator.translator(for: first)?.isOffered == false)
    let second = try await harness.loadedTab(language: "fr-CA", url: "https://example.ca/")
    #expect(harness.coordinator.dismissOffer(for: second))
    #expect(harness.memory.contains(french))
    let third = try await harness.loadedTab(language: "fr", url: "https://autre.fr/")
    let translator = try #require(harness.coordinator.translator(for: third))
    #expect(!translator.isOffered)
}

@MainActor @Test func loadingAnotherPageDropsTheTranslator() async throws {
    let harness = Harness()
    let tab = try await harness.loadedTab(language: "fr")
    await harness.coordinator.translate(tab)
    #expect(tab.replacedText.count == 0)
    tab.load(URL(string: "https://example.fr/next")!)
    harness.coordinator.tabStateDidChange(tab)
    #expect(harness.coordinator.translator(for: tab) == nil)
    tab.finishLoading(title: "Next")
    harness.coordinator.tabStateDidChange(tab)
    try await Task.sleep(for: .milliseconds(50))
    #expect(harness.coordinator.translator(for: tab)?.status == .idle)
}

@MainActor @Test func forgettingATabDropsItsTranslator() async throws {
    let harness = Harness()
    let tab = try await harness.loadedTab(language: "fr")
    harness.coordinator.forget(tab.id)
    #expect(harness.coordinator.translator(for: tab) == nil)
}

@MainActor @Test func withoutATranslatorNothingIsOffered() async throws {
    let harness = Harness()
    harness.coordinator.translator = nil
    let tab = try await harness.loadedTab(language: "fr")
    #expect(harness.coordinator.translator(for: tab) == nil)
}

@MainActor @Test func translateAndShowOriginalGoThroughTheCoordinator() async throws {
    let harness = Harness()
    let tab = try await harness.loadedTab(language: "fr")
    tab.pageTextForTesting = [TextSegment(id: 0, text: "Bonjour")]
    await harness.coordinator.translate(tab)
    #expect(tab.replacedText == [0: "[en] Bonjour"])
    harness.coordinator.showOriginal(tab)
    #expect(tab.replacedText.isEmpty)
    #expect(harness.coordinator.translator(for: tab)?.status == .idle)
}
