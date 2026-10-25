import BrowserEngine
import Foundation
import NaturalLanguage

/// Works out what language a page is in: what the page declares, or failing that, what its text reads like.
public enum LanguageDetection {
    /// Fewer characters than this say too little to recognise a language from.
    public static let minimumSampleLength = 40
    /// How sure the recogniser has to be before its answer overrides what a page declares.
    static let overrideConfidence = 0.95

    /// What the recogniser makes of a text: its best guess and how sure it is, nil when it has no idea.
    public typealias Recognizer = (String) -> (language: Locale.Language, confidence: Double)?

    /// The page's language, or nil when it can't be told. A declared language wins unless the text very clearly
    /// reads as another, since many pages declare `en` whatever they're written in.
    public static func detect(_ sample: PageLanguageSample, recognizer: Recognizer = recognize) -> Locale.Language? {
        let declared = declaredLanguage(sample.declared)
        let text = sample.text
        let recognized = text.count >= minimumSampleLength ? recognizer(text) : nil
        if let declared {
            if let recognized, recognized.confidence >= overrideConfidence, !recognized.language.isSameLanguage(as: declared) {
                return recognized.language
            }
            return declared
        }
        return recognized?.language
    }

    /// A `lang` attribute as a language, nil when it's empty or isn't one.
    static func declaredLanguage(_ declared: String) -> Locale.Language? {
        let trimmed = declared.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: "-")
        guard !trimmed.isEmpty else { return nil }
        let language = Locale.Language(identifier: trimmed)
        guard let code = language.languageCode?.identifier, code.count >= 2, code.count <= 3, code.allSatisfy(\.isLetter) else { return nil }
        return language
    }

    /// Apple's language recogniser, on the Mac.
    public static func recognize(_ text: String) -> (language: Locale.Language, confidence: Double)? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first else { return nil }
        return (Locale.Language(identifier: language.rawValue), confidence)
    }
}
