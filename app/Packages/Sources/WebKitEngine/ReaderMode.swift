import Foundation
import WebKit

/// What `reader-signals.js` measures about a page once it has loaded.
struct ArticleSignals: Decodable, Equatable {
    /// Visible paragraphs of 80 characters or more that aren't mostly links.
    var longParagraphs: Int
    var paragraphCharacters: Int
    var hasArticleElement: Bool
    /// The page calls itself an article, in its Open Graph type or its schema.org data.
    var isMarkedAsArticle: Bool
    var formFields: Int
    var path: String

    /// Enough running prose to be worth reading on its own. Home pages and forms need to say they're articles,
    /// and pages that do, or that wrap their text in `<article>`, need less prose to count.
    var looksLikeArticle: Bool {
        let isHome = path.isEmpty || path == "/"
        if (isHome || formFields > 10) && !isMarkedAsArticle { return false }
        if isMarkedAsArticle || hasArticleElement {
            return longParagraphs >= 3 && paragraphCharacters >= 1000
        }
        return longParagraphs >= 5 && paragraphCharacters >= 2000
    }
}

/// An article as `reader-extract.js` found it. `content` is HTML the script rebuilt from safe elements only.
struct ReaderArticle: Decodable, Equatable {
    var title: String
    var byline: String
    var siteName: String
    var content: String
    var textLength: Int
    var language: String

    /// Shorter than this, the reader would show a fragment of the page rather than its article.
    static let minimumLength = 250
}

/// The reader page for an article: a serif column of comfortable width that follows light and dark mode.
/// The page runs no scripts, and its policy lets in nothing but images and its own style.
func readerPageHTML(for article: ReaderArticle) -> String {
    let language = article.language.isEmpty ? "" : #" lang="\#(escapeHTML(article.language))""#
    let byline = article.byline.isEmpty ? "" : #"<p class="byline">\#(escapeHTML(article.byline))</p>"#
    return """
        <!doctype html>
        <html\(language)>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http: data:; style-src 'unsafe-inline'">
        <title>\(escapeHTML(article.title))</title>
        <style>\(readerStyle)</style>
        </head>
        <body>
        <main>
        <p class="site">\(escapeHTML(article.siteName))</p>
        <h1>\(escapeHTML(article.title))</h1>
        \(byline)
        <div class="content">\(article.content)</div>
        </main>
        </body>
        </html>
        """
}

/// Text made safe to put between HTML tags or inside a quoted attribute.
func escapeHTML(_ text: String) -> String {
    var escaped = ""
    escaped.reserveCapacity(text.count)
    for character in text {
        switch character {
        case "&": escaped += "&amp;"
        case "<": escaped += "&lt;"
        case ">": escaped += "&gt;"
        case "\"": escaped += "&quot;"
        case "'": escaped += "&#39;"
        default: escaped.append(character)
        }
    }
    return escaped
}

private let readerStyle = """
    :root { --text: #1d1d1f; --muted: #6e6e73; --background: #fbfaf7; --rule: rgba(0, 0, 0, 0.12); --code: rgba(0, 0, 0, 0.05); --link: #1d5bbf; }
    @media (prefers-color-scheme: dark) {
        :root { --text: #e5e3de; --muted: #9a9995; --background: #1c1c1e; --rule: rgba(255, 255, 255, 0.14); --code: rgba(255, 255, 255, 0.07); --link: #8ab4f8; }
    }
    html { background: var(--background); }
    body { margin: 0; color: var(--text); font: 20px/1.65 ui-serif, "New York", Georgia, serif; -webkit-font-smoothing: antialiased; text-rendering: optimizeLegibility; }
    main { max-width: 34em; margin: 0 auto; padding: 64px 32px 120px; overflow-wrap: break-word; }
    .site { margin: 0 0 12px; color: var(--muted); font: 600 13px/1.4 -apple-system, system-ui, sans-serif; letter-spacing: 0.04em; text-transform: uppercase; }
    h1 { margin: 0 0 12px; font-size: 1.9em; line-height: 1.2; }
    .byline { margin: 0 0 12px; color: var(--muted); font: 15px/1.4 -apple-system, system-ui, sans-serif; }
    .content { margin-top: 36px; }
    h2, h3, h4, h5, h6 { margin: 1.8em 0 0.6em; line-height: 1.3; }
    h2 { font-size: 1.35em; } h3 { font-size: 1.15em; } h4, h5, h6 { font-size: 1em; }
    p, ul, ol, dl, blockquote, pre, figure, table { margin: 0 0 1.1em; }
    li { margin-bottom: 0.35em; }
    img { display: block; max-width: 100%; height: auto; margin: 1.4em auto; border-radius: 4px; }
    figure { margin-left: 0; margin-right: 0; }
    figure img { margin-bottom: 0.5em; }
    figcaption, .content small { color: var(--muted); font: 14px/1.45 -apple-system, system-ui, sans-serif; }
    a { color: var(--link); text-decoration-thickness: 1px; text-underline-offset: 2px; }
    blockquote { margin-left: 0; padding-left: 1em; border-left: 3px solid var(--rule); color: var(--muted); }
    pre, code, kbd, samp { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.8em; }
    pre { padding: 14px 16px; overflow-x: auto; border-radius: 6px; background: var(--code); line-height: 1.5; }
    :not(pre) > code { padding: 0.1em 0.3em; border-radius: 4px; background: var(--code); }
    hr { margin: 2em 0; border: 0; border-top: 1px solid var(--rule); }
    table { width: 100%; border-collapse: collapse; font-size: 0.85em; }
    th, td { padding: 6px 8px; border-bottom: 1px solid var(--rule); text-align: left; vertical-align: top; }
    """

/// The scripts that find and measure articles, run in a world of their own so pages can't see or change them.
@MainActor
enum ReaderScripts {
    static let world = WKContentWorld.world(name: "SelaReader")
    static let signals = resource("reader-signals")
    static let extract = resource("reader-extract")

    private static func resource(_ name: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

/// Sends the reader's links back to its tab. Links within the article, such as to footnotes, stay in the reader.
@MainActor
final class ReaderNavigation: NSObject, WKNavigationDelegate {
    weak var tab: WebKitTab?
    /// The page the reader shows, which is also the reader's own address.
    var pageURL: URL?

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else { return .allow }
        if let pageURL, isSameDocument(url, pageURL) { return .allow }
        tab?.followReaderLink(to: url, modifiers: navigationAction.modifierFlags, buttonNumber: navigationAction.buttonNumber)
        return .cancel
    }
}

/// True when two addresses differ only in their fragment.
func isSameDocument(_ a: URL, _ b: URL) -> Bool {
    func withoutFragment(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }
    return withoutFragment(a) == withoutFragment(b)
}
