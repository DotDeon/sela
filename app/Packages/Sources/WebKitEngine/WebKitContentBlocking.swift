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
