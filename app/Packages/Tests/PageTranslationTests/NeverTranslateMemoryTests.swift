import Foundation
import PageTranslation
import Testing

private let french = Locale.Language(identifier: "fr-FR")
private let german = Locale.Language(identifier: "de")

private func freshDefaults() -> UserDefaults {
    let name = "NeverTranslateMemoryTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Test func twoDismissalsRememberALanguage() {
    let memory = NeverTranslateMemory(defaults: freshDefaults())
    #expect(!memory.recordDismissal(of: french))
    #expect(!memory.contains(french))
    #expect(memory.recordDismissal(of: french))
    #expect(memory.contains(french))
    #expect(memory.keys == ["fr"])
}

@Test func dismissalsCountPerLanguageWhateverTheRegion() {
    let memory = NeverTranslateMemory(defaults: freshDefaults())
    memory.recordDismissal(of: french)
    memory.recordDismissal(of: german)
    #expect(memory.languages.isEmpty)
    #expect(memory.recordDismissal(of: Locale.Language(identifier: "fr-CA")))
    #expect(memory.contains(french))
    #expect(!memory.contains(german))
}

@Test func rememberingTwiceReportsOnlyOnce() {
    let memory = NeverTranslateMemory(defaults: freshDefaults())
    memory.recordDismissal(of: french)
    #expect(memory.recordDismissal(of: french))
    #expect(!memory.recordDismissal(of: french))
    #expect(memory.languages.count == 1)
}

@Test func resetOffersEverythingAgain() {
    let memory = NeverTranslateMemory(defaults: freshDefaults())
    memory.recordDismissal(of: french)
    memory.recordDismissal(of: french)
    memory.reset()
    #expect(memory.languages.isEmpty)
    #expect(!memory.recordDismissal(of: french))
}

@Test func settingsDefaultToTheMacsLanguageAndOffering() {
    let settings = TranslationSettings(defaults: freshDefaults())
    #expect(settings.targetLanguage.isSameLanguage(as: Locale.current.language))
    #expect(settings.offersTranslation)
    settings.targetLanguage = german
    settings.offersTranslation = false
    #expect(settings.targetLanguage == german)
    #expect(!settings.offersTranslation)
}
