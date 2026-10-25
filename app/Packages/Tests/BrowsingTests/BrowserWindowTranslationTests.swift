import BrowserEngine
import Browsing
import FakeEngine
import Foundation
import PageTranslation
import SelaTestSupport
import Sidebar
import SidebarModel
import Testing

private let english = Locale.Language(identifier: "en")

/// A translator that wraps each text in brackets with the target language.
@MainActor
private final class BracketTranslator: Translator {
    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationAvailability { .installed }
    func prepare(from source: Locale.Language, to target: Locale.Language) async throws {}
    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        texts.map { "[\(target.minimalIdentifier)] \($0)" }
    }
    func supportedLanguages() async -> [Locale.Language] { [english] }
}

@MainActor
private func makeModel() throws -> BrowserWindowModel {
    let folder = try temporaryFolder()
    let store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
    let name = "BrowserWindowTranslationTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    let settings = TranslationSettings(defaults: defaults)
    settings.targetLanguage = english
    let coordinator = TranslationCoordinator(settings: settings, memory: NeverTranslateMemory(defaults: defaults))
    coordinator.translator = BracketTranslator()
    coordinator.preferredLanguages = { [english] }
    return BrowserWindowModel(engine: FakeEngine(), sidebar: store, translation: coordinator)
}

/// Loads a French page in the selected tab and waits for its language to be detected.
@MainActor
private func loadFrenchPage(in model: BrowserWindowModel) async throws -> FakeTab {
    model.select("u1")
    let tab = try #require(model.liveTab(for: "u1") as? FakeTab)
    tab.languageSampleForTesting = PageLanguageSample(declared: "fr", text: "Bonjour tout le monde, voici une page en français.")
    tab.pageTextForTesting = [TextSegment(id: 0, text: "Bonjour")]
    tab.load(URL(string: "https://example.fr/")!)
    tab.finishLoading(title: "Exemple")
    for _ in 0..<100 where model.selectedTranslator == nil {
        try await Task.sleep(for: .milliseconds(10))
    }
    return tab
}

@MainActor @Test func aPageInAnotherLanguageIsOfferedForTranslation() async throws {
    let model = try makeModel()
    _ = try await loadFrenchPage(in: model)
    let translator = try #require(model.selectedTranslator)
    #expect(translator.isOffered)
    #expect(translator.status == .idle)
}

@MainActor @Test func translatingTheSelectedPageAndShowingTheOriginal() async throws {
    let model = try makeModel()
    let tab = try await loadFrenchPage(in: model)
    #expect(await model.translateSelectedPage())
    #expect(tab.replacedText == [0: "[en] Bonjour"])
    #expect(model.selectedTranslator?.status == .translated)
    model.showOriginalSelectedPage()
    #expect(tab.replacedText.isEmpty)
    #expect(model.selectedTranslator?.status == .idle)
}

@MainActor @Test func pagesWithoutADetectedLanguageCantBeTranslated() async throws {
    let model = try makeModel()
    model.select("u1")
    #expect(await model.translateSelectedPage() == false)
    #expect(model.selectedTranslator == nil)
}

@MainActor @Test func closingTheTabForgetsItsTranslator() async throws {
    let model = try makeModel()
    let tab = try await loadFrenchPage(in: model)
    #expect(model.translation.translator(for: tab) != nil)
    model.close("u1")
    #expect(model.translation.translator(for: tab) == nil)
}

@MainActor @Test func loadingAnotherPageDropsTheTranslation() async throws {
    let model = try makeModel()
    let tab = try await loadFrenchPage(in: model)
    await model.translateSelectedPage()
    model.load(URL(string: "https://elsewhere.example.com/")!)
    #expect(model.selectedTranslator == nil)
    #expect(tab.restoreCount == 0)
}
