import BrowserEngine
import ContentBlockerConverter
import CryptoKit
import Foundation

/// Filter lists converted for WebKit: one content rule set per list, plus the rules only a page script can apply.
public struct CompiledFilters: Sendable {
    public let ruleSets: [ContentRuleSet]
    /// AdGuard rules for `PageScriptLookup`, one per line.
    public let advancedRules: String

    public init(ruleSets: [ContentRuleSet], advancedRules: String) {
        self.ruleSets = ruleSets
        self.advancedRules = advancedRules
    }
}

/// Converts each list with AdGuard's converter. Takes up to a few seconds for big lists, so run it off the main actor.
/// Each rule set's identifier is `sela-<id>-` and the first 16 hex characters of its JSON's SHA-256.
public func compileFilters(_ lists: [(id: String, text: String)]) -> CompiledFilters {
    var ruleSets: [ContentRuleSet] = []
    var advanced: [String] = []
    var seen: Set<String> = []
    for list in lists {
        let lines = list.text.components(separatedBy: .newlines)
        let result = ContentBlockerConverter().convertArray(rules: lines, safariVersion: .autodetect(), advancedBlocking: true)
        let digest = SHA256.hash(data: Data(result.safariRulesJSON.utf8)).map { String(format: "%02x", $0) }.joined()
        ruleSets.append(ContentRuleSet(identifier: "sela-\(list.id)-\(digest.prefix(16))", json: result.safariRulesJSON))
        // A rule in more than one list would otherwise run twice on a page.
        for rule in (result.advancedRulesText ?? "").components(separatedBy: .newlines) where !rule.isEmpty && seen.insert(rule).inserted {
            advanced.append(rule)
        }
    }
    return CompiledFilters(ruleSets: ruleSets, advancedRules: advanced.joined(separator: "\n"))
}
