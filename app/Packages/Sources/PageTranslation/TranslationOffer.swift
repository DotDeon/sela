import Foundation

/// Decides whether to offer to translate a page, given its language and what the user reads.
public enum TranslationOffer {
    /// True when the page is in a language the user doesn't read: not the one it would be translated into, and not
    /// one of their preferred languages. Languages they've said never to translate are left alone.
    public static func shouldOffer(pageLanguage: Locale.Language, target: Locale.Language, preferred: [Locale.Language],
                                   neverTranslate: Set<String>) -> Bool {
        if pageLanguage.isSameLanguage(as: target) { return false }
        if preferred.contains(where: { pageLanguage.isSameLanguage(as: $0) }) { return false }
        if neverTranslate.contains(NeverTranslateMemory.key(for: pageLanguage)) { return false }
        return true
    }

    /// The languages the user reads, from System Settings.
    public static var preferredLanguages: [Locale.Language] {
        Locale.preferredLanguages.map { Locale.Language(identifier: $0) }
    }
}
