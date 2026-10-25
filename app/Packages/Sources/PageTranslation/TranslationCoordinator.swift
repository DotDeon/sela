import BrowserEngine
import Foundation
import Observation

/// Follows a window's tabs, works out each page's language once it has loaded, and keeps a `PageTranslator` for
/// every page that could be translated. The window's model reports tab changes here, and the sidebar reads the
/// selected tab's translator for its button.
@MainActor
@Observable
public final class TranslationCoordinator {
    /// Does the translating. Nil, as in tests without one, means no page is offered.
    @ObservationIgnored public var translator: (any Translator)?
    /// The languages the user reads. Those of System Settings unless a test says otherwise.
    @ObservationIgnored public var preferredLanguages: () -> [Locale.Language] = { TranslationOffer.preferredLanguages }
    public let settings: TranslationSettings
    public let memory: NeverTranslateMemory

    public private(set) var translators: [TabID: PageTranslator] = [:]
    /// The page each tab was last looked at for, so a page is only detected once.
    @ObservationIgnored private var detected: [TabID: URL] = [:]

    public init(settings: TranslationSettings = TranslationSettings(), memory: NeverTranslateMemory = NeverTranslateMemory()) {
        self.settings = settings
        self.memory = memory
    }

    /// The translator for a tab's current page, once its language is known and the pair can be translated.
    public func translator(for tab: any BrowserTab) -> PageTranslator? {
        translators[tab.id]
    }

    /// Call whenever a tab's state changes. A page that starts loading drops the old page's translator, since the
    /// old text goes with it; a page that finishes loading gets its language detected.
    public func tabStateDidChange(_ tab: any BrowserTab) {
        let state = tab.state
        if state.isLoading {
            if let existing = translators.removeValue(forKey: tab.id) { existing.cancel() }
            detected[tab.id] = nil
            return
        }
        guard let url = state.url, ["http", "https", "file"].contains(url.scheme?.lowercased() ?? ""), detected[tab.id] != url else { return }
        detected[tab.id] = url
        Task { await detect(tab, at: url) }
    }

    /// The tab closed or went to sleep.
    public func forget(_ id: TabID) {
        translators.removeValue(forKey: id)?.cancel()
        detected[id] = nil
    }

    /// Translates the tab's page, if its language is known.
    public func translate(_ tab: any BrowserTab) async {
        await translators[tab.id]?.translate()
    }

    public func showOriginal(_ tab: any BrowserTab) {
        translators[tab.id]?.showOriginal()
    }

    /// The user turned down translating the tab's page. Hides the offer, and after enough refusals of the same
    /// language, remembers never to offer it. True when that just happened.
    @discardableResult
    public func dismissOffer(for tab: any BrowserTab) -> Bool {
        guard let translator = translators[tab.id] else { return false }
        translator.isOffered = false
        return memory.recordDismissal(of: translator.sourceLanguage)
    }

    private func detect(_ tab: any BrowserTab, at url: URL) async {
        guard let translator, let sample = await tab.languageSample() else { return }
        // The page may have moved on while the script ran.
        guard detected[tab.id] == url, tab.state.url == url, let language = LanguageDetection.detect(sample) else { return }
        let target = settings.targetLanguage
        guard !language.isSameLanguage(as: target) else { return }
        let offered = settings.offersTranslation
            && TranslationOffer.shouldOffer(pageLanguage: language, target: target, preferred: preferredLanguages(), neverTranslate: memory.keys)
        let availability = await translator.availability(from: language, to: target)
        guard availability != .unsupported, detected[tab.id] == url, tab.state.url == url else { return }
        translators[tab.id] = PageTranslator(tab: tab, translator: translator, from: language, to: target, isOffered: offered)
    }
}
