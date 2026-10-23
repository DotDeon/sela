import Foundation

/// The page shown when a URL can't be loaded: why, a retry link, and a search for what was typed.
func errorPageHTML(for url: URL, error: NSError) -> String {
    let address = url.absoluteString
    let query = url.host() ?? address
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "+&=?#")
    let search = "https://www.google.com/search?q=" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
    return """
    <!doctype html>
    <html><head><meta charset="utf-8"><title>Can’t open this page</title>
    <style>
    body { font: 15px -apple-system, sans-serif; color: #333; max-width: 560px; margin: 18vh auto; padding: 0 24px; }
    h1 { font-size: 22px; } p { line-height: 1.5; } a { color: #0a64d6; }
    @media (prefers-color-scheme: dark) { body { background: #1e1e1e; color: #ddd; } a { color: #5aa2ff; } }
    </style></head>
    <body><h1>Can’t open this page</h1>
    <p>Brow couldn’t open <strong>\(escaped(address))</strong>. \(escaped(error.localizedDescription))</p>
    <p><a href="\(escaped(address))">Try again</a> · <a href="\(escaped(search))">Search for \(escaped(query))</a></p>
    </body></html>
    """
}

private func escaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
}
