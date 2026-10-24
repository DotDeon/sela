import BrowserEngine
import Foundation
import Testing
import ContentBlocking

private let rules = """
    [Adblock Plus 2.0]
    ||ads.example.com^
    example.com##.banner
    example.com#%#//scriptlet('abort-on-property-read', 'adsbygoogle')
    """

@Test func compilingMakesOneRuleSetPerList() {
    let compiled = compileFilters([(id: "a", text: rules), (id: "b", text: rules)])
    #expect(compiled.ruleSets.count == 2)
    #expect(compiled.ruleSets[0].identifier.hasPrefix("sela-a-"))
    #expect(compiled.ruleSets[1].identifier.hasPrefix("sela-b-"))
    #expect(compiled.ruleSets.allSatisfy { $0.json.contains(#"ads\\.example\\.com"#) })
}

@Test func identifiersFollowTheContent() {
    let first = compileFilters([(id: "a", text: rules)]).ruleSets[0].identifier
    let again = compileFilters([(id: "a", text: rules)]).ruleSets[0].identifier
    let changed = compileFilters([(id: "a", text: rules + "\n||more.example.com^")]).ruleSets[0].identifier
    #expect(first == again)
    #expect(first != changed)
    #expect(first.count == "sela-a-".count + 16)
}

@Test func scriptletsBecomeAdvancedRules() {
    #expect(compileFilters([(id: "a", text: rules)]).advancedRules.contains("abort-on-property-read"))
}

@MainActor @Test func lookupFindsScriptletsForTheirSite() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "sela-engine-\(UUID().uuidString)")
    let lookup = try PageScriptLookup(advancedRules: compileFilters([(id: "a", text: rules)]).advancedRules, folder: folder)
    #expect(lookup.scripts(page: URL(string: "https://example.com/")!, top: nil)?.scriptlets.map(\.name) == ["abort-on-property-read"])
    #expect(lookup.scripts(page: URL(string: "https://other.org/")!, top: nil) == nil)
}

@Test func advancedRulesInTwoListsAreKeptOnce() {
    let advanced = compileFilters([(id: "a", text: rules), (id: "b", text: rules)]).advancedRules
    #expect(advanced.components(separatedBy: "abort-on-property-read").count == 2)
}
