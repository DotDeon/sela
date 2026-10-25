import Foundation
import PageTranslation

/// A translator that wraps each text in brackets with the target language, and records what it was asked.
@MainActor
final class FakeTranslator: Translator {
    var availabilityAnswer = TranslationAvailability.installed
    var prepareFails = false
    var translateFails = false
    var supported: [Locale.Language] = [Locale.Language(identifier: "en"), Locale.Language(identifier: "fr"), Locale.Language(identifier: "de")]
    private(set) var prepareCount = 0
    private(set) var batches: [[String]] = []
    /// Holds each batch until `release` is called, so a test can look at the page mid-way.
    var holds = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationAvailability {
        availabilityAnswer
    }

    func prepare(from source: Locale.Language, to target: Locale.Language) async throws {
        prepareCount += 1
        if prepareFails { throw Declined() }
    }

    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String] {
        batches.append(texts)
        if holds {
            await withCheckedContinuation { waiting.append($0) }
        }
        if translateFails { throw Declined() }
        return texts.map { "[\(target.minimalIdentifier)] \($0)" }
    }

    func supportedLanguages() async -> [Locale.Language] { supported }

    /// Lets one held batch through.
    func release() {
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }

    var heldCount: Int { waiting.count }

    private struct Declined: Error {}
}
