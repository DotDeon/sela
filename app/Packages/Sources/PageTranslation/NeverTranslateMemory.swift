import Foundation

/// The languages the user has turned down translating, stored in `UserDefaults`. Turning down the offer twice for
/// the same language puts it here, and Settings can clear the list.
public struct NeverTranslateMemory {
    public static let languagesKey = "NeverTranslateLanguages"
    public static let dismissalsKey = "TranslationOfferDismissals"
    /// How many times the offer is turned down before a language is remembered.
    public static let dismissalsBeforeRemembering = 2

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// How a language is stored: its code, and its script when it isn't the language's usual one, so French
    /// from anywhere is "fr" while traditional Chinese stays apart from simplified.
    public static func key(for language: Locale.Language) -> String {
        guard let code = language.languageCode?.identifier else { return language.minimalIdentifier }
        if let script = language.script, script != Locale.Language(identifier: code).script { return "\(code)-\(script.identifier)" }
        return code
    }

    /// The remembered languages, in the order they were remembered.
    public var languages: [Locale.Language] {
        (defaults.stringArray(forKey: Self.languagesKey) ?? []).map { Locale.Language(identifier: $0) }
    }

    /// The remembered languages as `TranslationOffer` takes them.
    public var keys: Set<String> {
        Set(defaults.stringArray(forKey: Self.languagesKey) ?? [])
    }

    public func contains(_ language: Locale.Language) -> Bool {
        keys.contains(Self.key(for: language))
    }

    /// Notes that the user turned down translating `language`. True when that was enough to remember it.
    @discardableResult
    public func recordDismissal(of language: Locale.Language) -> Bool {
        let key = Self.key(for: language)
        var counts = defaults.dictionary(forKey: Self.dismissalsKey) as? [String: Int] ?? [:]
        counts[key, default: 0] += 1
        defaults.set(counts, forKey: Self.dismissalsKey)
        guard counts[key, default: 0] >= Self.dismissalsBeforeRemembering, !keys.contains(key) else { return false }
        defaults.set((defaults.stringArray(forKey: Self.languagesKey) ?? []) + [key], forKey: Self.languagesKey)
        return true
    }

    /// Offers every language again.
    public func reset() {
        defaults.removeObject(forKey: Self.languagesKey)
        defaults.removeObject(forKey: Self.dismissalsKey)
    }
}
