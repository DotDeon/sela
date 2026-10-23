import BrowserEngine
import FilterEngine
import Foundation

/// Finds the advanced rules for a page with AdGuard's filtering engine, which it keeps in `folder`.
@MainActor
public final class PageScriptLookup {
    private let webExtension: WebExtension

    public init(advancedRules: String, folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        webExtension = try WebExtension(containerURL: folder)
        _ = try webExtension.buildFilterEngine(rules: advancedRules)
    }

    /// The page scripts for a page or frame, or nil when no rule applies there.
    public func scripts(page: URL, top: URL?) -> PageScripts? {
        guard let configuration = webExtension.lookup(pageUrl: page, topUrl: top) else { return nil }
        let scripts = PageScripts(
            css: configuration.css,
            extendedCss: configuration.extendedCss,
            js: configuration.js,
            scriptlets: configuration.scriptlets.map { PageScriptlet(name: $0.name, args: $0.args) }
        )
        let isEmpty = scripts.css.isEmpty && scripts.extendedCss.isEmpty && scripts.js.isEmpty && scripts.scriptlets.isEmpty
        return isEmpty ? nil : scripts
    }
}
