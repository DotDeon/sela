import BrowserEngine
import Foundation
import WebKit

/// The rule lists every tab uses, compiled by WebKit and kept between launches by identifier.
@MainActor
final class WebKitContentRules {
    static let identifierPrefix = "brow-"

    private let store: WKContentRuleListStore
    private(set) var lists: [WKContentRuleList] = []

    init(store: WKContentRuleListStore) {
        self.store = store
    }

    /// Looks each set up by identifier, compiling only the ones WebKit doesn't have, then forgets old Brow lists.
    func install(_ ruleSets: [ContentRuleSet]) async throws {
        var compiled: [WKContentRuleList] = []
        for ruleSet in ruleSets {
            if let existing = try? await store.contentRuleList(forIdentifier: ruleSet.identifier) {
                compiled.append(existing)
            } else if let list = try await store.compileContentRuleList(forIdentifier: ruleSet.identifier, encodedContentRuleList: ruleSet.json) {
                compiled.append(list)
            }
        }
        lists = compiled
        let wanted = Set(ruleSets.map(\.identifier))
        for identifier in await store.availableIdentifiers() ?? [] where identifier.hasPrefix(Self.identifierPrefix) && !wanted.contains(identifier) {
            try? await store.removeContentRuleList(forIdentifier: identifier)
        }
    }

    /// Puts the lists on a tab's content controller, or takes them all off.
    func apply(to controller: WKUserContentController, blocking: Bool) {
        controller.removeAllContentRuleLists()
        guard blocking else { return }
        for list in lists { controller.add(list) }
    }
}

/// AdGuard's content script, bundled by `scripts/content-blocking/build.sh`, and the bridge it asks for rules.
@MainActor
enum PageScriptInjection {
    static let world = WKContentWorld.world(name: "BrowContentBlocking")
    static let handlerName = "browContentBlocking"

    static let script: WKUserScript? = {
        guard let url = Bundle.module.url(forResource: "content-blocking", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world)
    }()

    /// Adds the bridge, once per content controller, and the scripts.
    static func install(on controller: WKUserContentController, bridge: PageScriptBridge) {
        controller.addScriptMessageHandler(bridge, contentWorld: world, name: handlerName)
        installScripts(on: controller, early: nil)
    }

    /// Replaces the controller's scripts. `early` holds the main frame's rules, known before the page loads, which
    /// the content script then applies before any of the page's own scripts.
    static func installScripts(on controller: WKUserContentController, early: PageScripts?) {
        controller.removeAllUserScripts()
        guard let script else { return }
        if let early, let data = try? JSONEncoder().encode(early), let json = String(data: data, encoding: .utf8) {
            controller.addUserScript(WKUserScript(source: "window.__browEarlyRules = \(json);", injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        }
        controller.addUserScript(script)
    }
}

/// Answers the page script's request for rules. The content controller keeps its handlers alive,
/// so this holds the tab weakly instead of being the tab.
@MainActor
final class PageScriptBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var tab: WebKitTab?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let pageText = body["page"] as? String,
              let page = URL(string: pageText), let tab
        else { return (nil, nil) }
        let top = (body["top"] as? String).flatMap(URL.init(string:))
        guard let scripts = tab.pageScripts(page: page, top: top),
              let data = try? JSONEncoder().encode(scripts),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return (nil, nil) }
        return (object, nil)
    }
}
