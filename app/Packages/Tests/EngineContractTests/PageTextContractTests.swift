import AppKit
import BrowserEngine
import Foundation
import Testing
import WebKit

@MainActor
@Suite(.serialized)
struct PageTextContractTests {
    let site: TestSite

    init() throws {
        site = try TestSite()
    }

    private func frenchPage() throws -> URL {
        try site.page("french.html", """
            <html lang="fr"><head><title>Bonjour</title><style>.x { color: red }</style></head>
            <body><h1>Bonjour le monde</h1><p>Voici un <em>paragraphe</em> court.</p>
            <pre>code = 1</pre><code>inline()</code><textarea>texte</textarea><input value="champ">
            <div contenteditable="true">éditable</div><p hidden>caché</p><p>12345</p>
            <script>window.added = () => { const p = document.createElement("p"); p.textContent = "Plus tard"; document.body.appendChild(p) }</script>
            </body></html>
            """)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func pagesReportTheirLanguageAndText(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try frenchPage())
        tab.contentView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let sample = try #require(await tab.languageSample())
        #expect(sample.declared == "fr")
        #expect(sample.text.contains("Bonjour le monde"))
    }

    @Test(arguments: EngineUnderTest.allCases)
    func visibleTextIsCollectedAndCodeAndFieldsAreSkipped(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try frenchPage())
        tab.contentView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let segments = await tab.collectPageText { _ in }
        let texts = segments.map(\.text)
        #expect(texts.contains("Bonjour le monde"))
        #expect(texts.contains("Voici un"))
        #expect(texts.contains("paragraphe"))
        #expect(texts.contains("court."))
        for skipped in ["code = 1", "inline()", "texte", "champ", "éditable", "caché", "12345", ".x { color: red }", "Bonjour"] {
            #expect(!texts.contains(skipped), "\(skipped) should be left alone")
        }
        tab.restorePageText()
    }

    @Test(arguments: EngineUnderTest.allCases)
    func replacedTextShowsAndRestoreBringsTheOriginalBack(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try frenchPage())
        tab.contentView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        let segments = await tab.collectPageText { _ in }
        let heading = try #require(segments.first { $0.text == "Bonjour le monde" })
        tab.replacePageText([TextSegment(id: heading.id, text: "Hello world")])
        try await eventually { (try? await headingText(of: tab)) == "Hello world" }
        tab.restorePageText()
        try await eventually { (try? await headingText(of: tab)) == "Bonjour le monde" }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func textThePageAddsLaterIsReported(engine: EngineUnderTest) async throws {
        let tab = try await loadedTab(engine.make(), try frenchPage())
        tab.contentView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        var added: [TextSegment] = []
        _ = await tab.collectPageText { added.append(contentsOf: $0) }
        try await runScript("window.added()", in: tab)
        try await eventually { added.contains { $0.text == "Plus tard" } }
        tab.restorePageText()
    }

    private func headingText(of tab: any BrowserTab) async throws -> String? {
        try await runScript("document.querySelector('h1').textContent", in: tab) as? String
    }
}

/// Runs a script in the page's own world. The WebKit tab's content view is its web view.
@MainActor
@discardableResult
private func runScript(_ script: String, in tab: any BrowserTab) async throws -> Any? {
    let webView = try #require(tab.contentView as? WKWebView)
    return try await webView.evaluateJavaScript(script)
}

/// Waits for an async condition, polling every 50 ms for up to 10 seconds.
@MainActor
private func eventually(_ condition: @MainActor () async -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<200 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}
