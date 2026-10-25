import BrowserEngine
import Foundation
import PageTranslation
import Testing

private let english = Locale.Language(identifier: "en")
private let britishEnglish = Locale.Language(identifier: "en-GB")
private let french = Locale.Language(identifier: "fr")
private let german = Locale.Language(identifier: "de")
private let simplifiedChinese = Locale.Language(identifier: "zh-Hans")
private let traditionalChinese = Locale.Language(identifier: "zh-Hant")

private let frenchText = String(repeating: "Le gouvernement a annoncé mardi une série de mesures pour soutenir les agriculteurs touchés par la sécheresse. ", count: 3)

private func sure(_ language: Locale.Language) -> LanguageDetection.Recognizer {
    { _ in (language, 0.99) }
}

private func unsure(_ language: Locale.Language) -> LanguageDetection.Recognizer {
    { _ in (language, 0.6) }
}

@Test func declaredLanguageWins() {
    let sample = PageLanguageSample(declared: "fr-FR", text: frenchText)
    #expect(LanguageDetection.detect(sample, recognizer: unsure(german)) == Locale.Language(identifier: "fr-FR"))
}

@Test func textVeryClearlyInAnotherLanguageOverridesTheDeclaration() {
    let sample = PageLanguageSample(declared: "en", text: frenchText)
    #expect(LanguageDetection.detect(sample, recognizer: sure(french))?.isSameLanguage(as: french) == true)
}

@Test func anUnsureRecognizerDoesntOverrideTheDeclaration() {
    let sample = PageLanguageSample(declared: "en", text: frenchText)
    #expect(LanguageDetection.detect(sample, recognizer: unsure(french))?.isSameLanguage(as: english) == true)
}

@Test func withoutADeclarationTheTextDecides() {
    let sample = PageLanguageSample(declared: "", text: frenchText)
    #expect(LanguageDetection.detect(sample, recognizer: unsure(french))?.isSameLanguage(as: french) == true)
}

@Test func shortTextWithoutADeclarationIsUnknown() {
    let sample = PageLanguageSample(declared: "", text: "Bonjour")
    #expect(LanguageDetection.detect(sample, recognizer: sure(french)) == nil)
}

@Test func nonsenseDeclarationsAreIgnored() {
    #expect(LanguageDetection.detect(PageLanguageSample(declared: "x-default", text: ""), recognizer: { _ in nil }) == nil)
    #expect(LanguageDetection.detect(PageLanguageSample(declared: "   ", text: ""), recognizer: { _ in nil }) == nil)
    #expect(LanguageDetection.detect(PageLanguageSample(declared: "pt_BR", text: ""), recognizer: { _ in nil }) == Locale.Language(identifier: "pt-BR"))
}

@Test func appleRecognizerReadsFrench() {
    let sample = PageLanguageSample(declared: "", text: frenchText)
    #expect(LanguageDetection.detect(sample)?.isSameLanguage(as: french) == true)
}

@Test func offersPagesInLanguagesTheUserDoesntRead() {
    #expect(TranslationOffer.shouldOffer(pageLanguage: french, target: english, preferred: [english], neverTranslate: []))
    #expect(TranslationOffer.shouldOffer(pageLanguage: german, target: britishEnglish, preferred: [britishEnglish, french], neverTranslate: []))
}

@Test func doesntOfferTheTargetLanguageOrAPreferredOne() {
    #expect(!TranslationOffer.shouldOffer(pageLanguage: Locale.Language(identifier: "en-US"), target: britishEnglish, preferred: [britishEnglish], neverTranslate: []))
    #expect(!TranslationOffer.shouldOffer(pageLanguage: french, target: english, preferred: [english, Locale.Language(identifier: "fr-CA")], neverTranslate: []))
}

@Test func doesntOfferLanguagesTheUserTurnedDown() {
    #expect(!TranslationOffer.shouldOffer(pageLanguage: Locale.Language(identifier: "fr-FR"), target: english, preferred: [english], neverTranslate: ["fr"]))
}

@Test func chineseScriptsAreDifferentLanguagesForTranslation() {
    #expect(!simplifiedChinese.isSameLanguage(as: traditionalChinese))
    #expect(TranslationOffer.shouldOffer(pageLanguage: traditionalChinese, target: simplifiedChinese, preferred: [simplifiedChinese], neverTranslate: []))
}

@Test func languageNamesReadWell() {
    #expect(french.displayName.hasPrefix("Fr"))
    #expect(!britishEnglish.displayName.isEmpty)
}
