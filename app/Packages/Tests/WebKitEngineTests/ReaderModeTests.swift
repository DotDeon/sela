import Foundation
import Testing
import WebKit
@testable import WebKitEngine

private func signals(paragraphs: Int, characters: Int, article: Bool = false, marked: Bool = false, fields: Int = 0, path: String = "/2026/10/story") -> ArticleSignals {
    ArticleSignals(longParagraphs: paragraphs, paragraphCharacters: characters, hasArticleElement: article, isMarkedAsArticle: marked, formFields: fields, path: path)
}

@Test func plainPagesNeedPlentyOfProse() {
    #expect(signals(paragraphs: 6, characters: 2400).looksLikeArticle)
    #expect(!signals(paragraphs: 4, characters: 2400).looksLikeArticle)
    #expect(!signals(paragraphs: 6, characters: 1500).looksLikeArticle)
}

@Test func pagesThatSayTheyreArticlesNeedLess() {
    #expect(signals(paragraphs: 3, characters: 1100, marked: true).looksLikeArticle)
    #expect(signals(paragraphs: 3, characters: 1100, article: true).looksLikeArticle)
    #expect(!signals(paragraphs: 2, characters: 1100, marked: true).looksLikeArticle)
}

@Test func homePagesAndFormsAreArticlesOnlyWhenTheySaySo() {
    #expect(!signals(paragraphs: 10, characters: 6000, path: "/").looksLikeArticle)
    #expect(!signals(paragraphs: 10, characters: 6000, fields: 12).looksLikeArticle)
    #expect(signals(paragraphs: 10, characters: 6000, marked: true, path: "/").looksLikeArticle)
}

@Test func signalsDecodeFromTheScriptsJSON() throws {
    let json = #"{"longParagraphs":4,"paragraphCharacters":1800,"hasArticleElement":true,"isMarkedAsArticle":false,"formFields":1,"path":"/a"}"#
    let decoded = try JSONDecoder().decode(ArticleSignals.self, from: Data(json.utf8))
    #expect(decoded == signals(paragraphs: 4, characters: 1800, article: true, fields: 1, path: "/a"))
}

@Test func escapingCoversTagsQuotesAndAmpersands() {
    #expect(escapeHTML(#"<b class="x">Tom & Jerry's</b>"#) == "&lt;b class=&quot;x&quot;&gt;Tom &amp; Jerry&#39;s&lt;/b&gt;")
}

@Test func readerPageEscapesWhatThePageSaysAboutItself() {
    let article = ReaderArticle(title: "<script>alert(1)</script>", byline: "A & B", siteName: "Site", content: "<p>Body</p>", textLength: 500, language: "en\" onload=\"x")
    let html = readerPageHTML(for: article)
    #expect(!html.contains("<script>"))
    #expect(html.contains("<h1>&lt;script&gt;alert(1)&lt;/script&gt;</h1>"))
    #expect(html.contains(#"<p class="byline">A &amp; B</p>"#))
    #expect(html.contains(#"<html lang="en&quot; onload=&quot;x">"#))
    #expect(html.contains("<p>Body</p>"))
    #expect(html.contains("Content-Security-Policy"))
    #expect(html.contains("prefers-color-scheme: dark"))
}

@Test func readerPageLeavesOutAMissingByline() {
    let article = ReaderArticle(title: "T", byline: "", siteName: "S", content: "", textLength: 500, language: "")
    #expect(!readerPageHTML(for: article).contains("byline\">"))
    #expect(readerPageHTML(for: article).contains("<html>"))
}

@MainActor @Test func extractionKeepsTheStoryAndDropsTheRest() async throws {
    let engine = WebKitEngine(configuration: .init(storage: .ephemeral))
    let tab = try #require(engine.makeTab(url: nil) as? WebKitTab)
    defer { tab.close() }
    tab.webView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
    let paragraph = "<p>The river keeps its own time, rising in the wet months and falling back, and the town has learned to build with it.</p>"
    let html = """
        <html lang="en"><head><title>A river town | The Paper</title><meta name="author" content="Ada Lane"></head><body>
        <nav class="menu"><a href="/">Home</a><a href="/news">News</a></nav>
        <div class="article-body"><h1>A river town</h1>\(String(repeating: paragraph, count: 6))
        <img data-src="/photo.jpg" src="data:image/gif;base64,R0lGODlhAQABAAAAACw=" alt="The river">
        <p>Read <a href="/more" onclick="steal()">more</a>.</p>
        <script>window.tracking = "tracking"</script><div class="share-buttons"><a href="#">Share</a></div></div>
        <footer>Subscribe</footer></body></html>
        """
    tab.webView.loadHTMLString(html, baseURL: URL(string: "https://paper.example.com/2026/river")!)
    for _ in 0..<100 where tab.webView.isLoading || tab.webView.url == nil {
        try await Task.sleep(for: .milliseconds(50))
    }
    let script = try #require(ReaderScripts.extract)
    let result = try await tab.webView.evaluateJavaScript(script, contentWorld: ReaderScripts.world)
    let json = try #require(result as? String)
    let article = try JSONDecoder().decode(ReaderArticle.self, from: Data(json.utf8))
    #expect(article.title == "A river town")
    #expect(article.byline == "Ada Lane")
    #expect(article.language == "en")
    #expect(article.siteName == "paper.example.com")
    #expect(article.content.contains("The river keeps its own time"))
    #expect(article.content.contains(#"<img src="https://paper.example.com/photo.jpg" alt="The river">"#))
    #expect(article.content.contains(#"<a href="https://paper.example.com/more">more</a>"#))
    for unwanted in ["<script", "onclick", "tracking", "Share", "Subscribe", "News", "<h2>A river town"] {
        #expect(!article.content.contains(unwanted), "\(unwanted)")
    }
}

@Test func fragmentsDontMakeANewDocument() {
    let page = URL(string: "https://example.com/story?id=1")!
    #expect(isSameDocument(page, URL(string: "https://example.com/story?id=1#notes")!))
    #expect(!isSameDocument(page, URL(string: "https://example.com/story?id=2")!))
}
