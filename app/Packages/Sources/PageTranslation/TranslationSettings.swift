import Foundation

/// Which language pages are translated into, and whether Sela offers to, stored in `UserDefaults`.
public struct TranslationSettings {
    public static let targetKey = "TranslateToLanguage"
    public static let offersKey = "OffersTranslation"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The language pages are translated into. The Mac's language until you choose.
    public var targetLanguage: Locale.Language {
        get {
            guard let stored = defaults.string(forKey: Self.targetKey), !stored.isEmpty else { return Locale.current.language }
            return Locale.Language(identifier: stored)
        }
        nonmutating set { defaults.set(newValue.minimalIdentifier, forKey: Self.targetKey) }
    }

    /// Whether the Translate button appears for pages in other languages. View > Translate Page works either way.
    public var offersTranslation: Bool {
        get { defaults.object(forKey: Self.offersKey) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.offersKey) }
    }
}
