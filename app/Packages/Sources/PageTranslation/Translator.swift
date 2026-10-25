import Foundation

/// Whether a pair of languages can be translated on this Mac.
public enum TranslationAvailability: Equatable, Sendable {
    /// The languages are on the Mac already.
    case installed
    /// The pair works once its languages are downloaded.
    case supported
    case unsupported
}

/// Translates text between two languages. Sela's app provides one built on Apple's Translation framework, which
/// works on the Mac itself; tests provide a fake.
@MainActor
public protocol Translator: AnyObject {
    func availability(from source: Locale.Language, to target: Locale.Language) async -> TranslationAvailability
    /// Downloads the pair's languages when they aren't on the Mac, asking the user first. Throws when they decline.
    func prepare(from source: Locale.Language, to target: Locale.Language) async throws
    /// Translates each text, answering in the same order.
    func translate(_ texts: [String], from source: Locale.Language, to target: Locale.Language) async throws -> [String]
    /// Every language pages can be translated into.
    func supportedLanguages() async -> [Locale.Language]
}

extension Locale.Language {
    /// The language's name in the user's language, such as "French" or "Chinese (Simplified)".
    public var displayName: String {
        let locale = Locale.current
        if let code = languageCode?.identifier {
            var name = locale.localizedString(forLanguageCode: code) ?? code
            if let script = script?.identifier, let scriptName = locale.localizedString(forScriptCode: script) {
                name += " (\(scriptName))"
            } else if let region = region?.identifier, let regionName = locale.localizedString(forRegionCode: region) {
                name += " (\(regionName))"
            }
            return name
        }
        return locale.localizedString(forIdentifier: minimalIdentifier) ?? minimalIdentifier
    }

    /// True when both are the same language, whatever their regions: British and American English, say.
    public func isSameLanguage(as other: Locale.Language) -> Bool {
        guard let code = languageCode, let otherCode = other.languageCode else { return minimalIdentifier == other.minimalIdentifier }
        guard code == otherCode else { return false }
        // Chinese is only the same language when its script matches too.
        if let script, let otherScript = other.script { return script == otherScript }
        return true
    }
}
