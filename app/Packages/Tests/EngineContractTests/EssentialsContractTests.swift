import AppKit
import BrowserEngine
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct EssentialsContractTests {
    let site: TestSite

    init() throws {
        site = try TestSite()
    }

    @Test(arguments: EngineUnderTest.allCases)
    func findMatchesTextOnThePage(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try site.page("text.html", "<p>Hello there</p>"))
        #expect(await tab.find("there", backwards: false))
        #expect(await tab.find("absent", backwards: false) == false)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func findIgnoresCase(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try site.page("text.html", "<p>Hello there</p>"))
        #expect(await tab.find("HELLO", backwards: false))
    }
}
