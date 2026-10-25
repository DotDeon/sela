import BrowserEngine
import Foundation
import Observation

/// Translates one page in place and puts it back. Made once a page's language is known, it collects the page's
/// text through the tab, translates it in batches, writes each batch back as it finishes, and keeps translating
/// text the page adds afterwards. `status` drives the Translate button.
@MainActor
@Observable
public final class PageTranslator {
    public enum Status: Equatable, Sendable {
        /// Not translated. The page shows its own text.
        case idle
        /// Finding out whether the pair can be translated here.
        case checking
        /// macOS is downloading the languages, or asking whether to.
        case downloading
        /// Translating, with the share of the page's text done so far.
        case translating(Double)
        case translated
        /// This Mac can't translate the pair.
        case unsupported
        /// The pair needs a download the user turned down, or that failed.
        case downloadNeeded
        /// Translation stopped part way. The page shows its own text again.
        case failed

        /// True while the page shows translated text, or is getting it.
        public var isActive: Bool {
            switch self {
            case .checking, .downloading, .translating, .translated: true
            case .idle, .unsupported, .downloadNeeded, .failed: false
            }
        }

        /// True while a batch is on its way.
        public var isBusy: Bool {
            switch self {
            case .checking, .downloading, .translating: true
            default: false
            }
        }
    }

    public let tab: any BrowserTab
    public let sourceLanguage: Locale.Language
    public let targetLanguage: Locale.Language
    public private(set) var status = Status.idle
    /// True while the Translate button shows for this page. Turning the offer down hides it; translating from the
    /// menu still works.
    public var isOffered: Bool

    @ObservationIgnored private let translator: any Translator
    /// Counts up each time translation starts or stops, so a run that was stopped doesn't touch the page or the
    /// status after it resumes from an await.
    @ObservationIgnored private var generation = 0
    /// Text the page added that's waiting for the translator.
    @ObservationIgnored private var pending: [TextSegment] = []
    @ObservationIgnored private var isDraining = false

    public init(tab: any BrowserTab, translator: any Translator, from source: Locale.Language, to target: Locale.Language, isOffered: Bool) {
        self.tab = tab
        self.translator = translator
        sourceLanguage = source
        targetLanguage = target
        self.isOffered = isOffered
    }

    /// Translates the page, downloading the languages first when they aren't on the Mac. Returns once the text
    /// that was on the page is done, or translation stopped; text the page adds later follows on its own.
    public func translate() async {
        guard !status.isActive else { return }
        generation += 1
        let run = generation
        status = .checking
        switch await translator.availability(from: sourceLanguage, to: targetLanguage) {
        case .unsupported:
            guard run == generation else { return }
            status = .unsupported
            return
        case .supported:
            guard run == generation else { return }
            status = .downloading
            do {
                try await translator.prepare(from: sourceLanguage, to: targetLanguage)
            } catch {
                guard run == generation else { return }
                status = .downloadNeeded
                return
            }
        case .installed:
            break
        }
        guard run == generation else { return }
        let segments = await tab.collectPageText { [weak self] added in self?.pageDidAddText(added) }
        guard run == generation else { return }
        let total = max(TextBatching.characterCount(segments), 1)
        var done = 0
        status = .translating(0)
        for batch in TextBatching.batches(segments) {
            guard await translate(batch, run: run) else { return }
            done += TextBatching.characterCount(batch)
            status = .translating(Double(done) / Double(total))
        }
        status = .translated
        await drainPending(run: run)
    }

    /// Puts the page's own text back and stops translating anything more.
    public func showOriginal() {
        generation += 1
        pending = []
        isDraining = false
        tab.restorePageText()
        status = .idle
    }

    /// Stops without touching the page, for when the page itself has gone.
    func cancel() {
        generation += 1
        pending = []
        isDraining = false
    }

    /// One batch to the translator and back into the page. False when the run was stopped or the translator failed.
    private func translate(_ batch: [TextSegment], run: Int) async -> Bool {
        do {
            let translated = try await translator.translate(batch.map(\.text), from: sourceLanguage, to: targetLanguage)
            guard run == generation else { return false }
            guard translated.count == batch.count else { throw TranslatorMismatch() }
            tab.replacePageText(zip(batch, translated).map { TextSegment(id: $0.id, text: $1) })
            return true
        } catch {
            guard run == generation else { return false }
            generation += 1
            pending = []
            tab.restorePageText()
            status = .failed
            return false
        }
    }

    private func pageDidAddText(_ segments: [TextSegment]) {
        guard status == .translated || status.isBusy else { return }
        pending.append(contentsOf: segments)
        guard status == .translated, !isDraining else { return }
        Task { await drainPending(run: generation) }
    }

    /// Translates text the page added, in the order it came, until there's none waiting.
    private func drainPending(run: Int) async {
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        while run == generation, !pending.isEmpty {
            let next = pending
            pending = []
            for batch in TextBatching.batches(next) {
                guard await translate(batch, run: run) else { return }
            }
        }
    }
}

private struct TranslatorMismatch: Error {}
