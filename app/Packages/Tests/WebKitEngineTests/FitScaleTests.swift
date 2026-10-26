import Foundation
import Testing
import WebKit
@testable import WebKitEngine

@MainActor @Test func fitScaleLaysThePageOutWiderWithoutChangingTheZoom() async throws {
    let engine = WebKitEngine(configuration: .init(storage: .ephemeral))
    let tab = try #require(engine.makeTab(url: nil) as? WebKitTab)
    defer { tab.close() }
    tab.webView.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
    tab.webView.loadHTMLString("<html><head><meta name=\"viewport\" content=\"width=device-width\"></head><body>Wide</body></html>", baseURL: nil)
    for _ in 0..<100 where tab.webView.isLoading || tab.webView.url == nil {
        try await Task.sleep(for: .milliseconds(50))
    }

    tab.setPageZoom(1.25)
    tab.setFitScale(0.5)
    #expect(tab.webView.pageZoom == 0.625)
    #expect(tab.state.pageZoom == 1.25)
    let width = try await tab.webView.evaluateJavaScript("window.innerWidth") as? Int
    #expect(width == 960, "600 points at 62.5 percent")

    tab.setPageZoom(1)
    #expect(tab.webView.pageZoom == 0.5, "zooming keeps the fit")
    tab.setFitScale(1)
    #expect(tab.webView.pageZoom == 1)
}
