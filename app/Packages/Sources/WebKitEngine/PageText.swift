import BrowserEngine
import Foundation
import WebKit

/// The script that numbers a page's text nodes and writes translations into them, run in a world of its own
/// so pages can't see or change what it keeps.
@MainActor
enum PageTextScripts {
    static let world = WKContentWorld.world(name: "SelaText")
    static let handlerName = "selaText"
    static let setup: String? = {
        guard let url = Bundle.module.url(forResource: "page-text", withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }()
    static let languageSample = """
        (() => {
            const body = document.body;
            const text = body ? (body.innerText || "").replace(/\\s+/g, " ").trim().slice(0, 3000) : "";
            return JSON.stringify({ declared: document.documentElement.lang || "", text });
        })()
        """
}

/// Receives text that appeared in a page after its text was collected. The content controller keeps its
/// handlers alive, so this holds the tab weakly instead of being the tab.
@MainActor
final class PageTextBridge: NSObject, WKScriptMessageHandler {
    weak var tab: WebKitTab?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let list = body["segments"] as? [[String: Any]] else { return }
        let segments = list.compactMap { entry -> TextSegment? in
            guard let id = entry["id"] as? Int, let text = entry["text"] as? String else { return nil }
            return TextSegment(id: id, text: text)
        }
        guard !segments.isEmpty else { return }
        tab?.pageDidAddText(segments)
    }
}

/// Segments as the page script takes them.
func pageTextJSON(_ segments: [TextSegment]) -> String? {
    guard let data = try? JSONEncoder().encode(segments) else { return nil }
    return String(data: data, encoding: .utf8)
}
