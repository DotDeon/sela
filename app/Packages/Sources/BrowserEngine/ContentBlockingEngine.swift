import Foundation

/// A WebKit content blocker rule list, in WebKit's JSON format.
public struct ContentRuleSet: Equatable, Sendable {
    /// Stays the same while `json` does, so a compiled copy can be reused.
    public var identifier: String
    public var json: String

    public init(identifier: String, json: String) {
        self.identifier = identifier
        self.json = json
    }
}

/// A scriptlet call: a named snippet from AdGuard's scriptlet library and its arguments.
public struct PageScriptlet: Codable, Equatable, Sendable {
    public var name: String
    public var args: [String]

    public init(name: String, args: [String]) {
        self.name = name
        self.args = args
    }
}

/// Blocking rules a page script applies inside a page, for what content rules can't express.
public struct PageScripts: Codable, Equatable, Sendable {
    /// Selectors to hide, or full CSS rules.
    public var css: [String]
    /// Selectors and rules that need AdGuard's Extended CSS.
    public var extendedCss: [String]
    public var js: [String]
    public var scriptlets: [PageScriptlet]

    public init(css: [String], extendedCss: [String], js: [String], scriptlets: [PageScriptlet]) {
        self.css = css
        self.extendedCss = extendedCss
        self.js = js
        self.scriptlets = scriptlets
    }
}

/// An engine that can block ads and trackers. Optional: the UI checks for it with `as?`.
@MainActor
public protocol ContentBlockingEngine: BrowserEngine {
    /// Replaces the rule sets every tab uses, compiling any the engine hasn't seen. Can take seconds the first time.
    func installContentRules(_ ruleSets: [ContentRuleSet]) async throws
    /// Asked before each top-level page load. False loads that page with no rules and no page scripts. Nil means always.
    var isContentBlockingEnabled: (@MainActor (URL) -> Bool)? { get set }
    /// The page scripts for a page or frame, given its URL and its top page's URL. Nil adds nothing.
    var pageScripts: (@MainActor (_ page: URL, _ top: URL?) -> PageScripts?)? { get set }
}
