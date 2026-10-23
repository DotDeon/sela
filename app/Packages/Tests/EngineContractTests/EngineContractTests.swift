import AppKit
import BrowserEngine
import Foundation
import Testing

@MainActor
@Suite(.serialized)
struct EngineContractTests {
    let site: TestSite

    init() throws {
        site = try TestSite()
    }

    @Test(arguments: EngineUnderTest.allCases)
    func loadUpdatesURLAndTitle(engine: EngineUnderTest) async throws {
        let a = try site.page("a.html", "<title>A</title>")
        let tab = try await loadedTab(engine.make(), a)
        try await eventually { tab.state.title == "A" }
        #expect(tab.state.url == a)
        #expect(!tab.state.isLoading)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func backAndForward(engine: EngineUnderTest) async throws {
        let a = try site.page("a.html", "<title>A</title>")
        let b = try site.page("b.html", "<title>B</title>")
        let tab = try await loadedTab(engine.make(), a)
        tab.load(b)
        try await eventually { tab.state.title == "B" && tab.state.canGoBack }

        tab.goBack()
        try await eventually { tab.state.title == "A" && tab.state.canGoForward }
        tab.goForward()
        try await eventually { tab.state.title == "B" }
    }

    // Both popup tests keep the opener tab alive, as the window model does. A freed opener can
    // drop `window.opener` before the popup's script runs.
    @Test(arguments: EngineUnderTest.allCases)
    func popupKeepsOpener(engine: EngineUnderTest) async throws {
        _ = try site.page("child.html", "<script>document.title = window.opener ? 'has opener' : 'no opener'</script>")
        let opener = try site.page("opener.html", "<script>window.open('child.html')</script>")
        let delegate = RecordingDelegate()
        let openerTab = try await loadedTab(engine.make(), opener, delegate: delegate)
        try await eventually { delegate.opened.first?.tab.state.title == "has opener" }
        withExtendedLifetime(openerTab) {}
        #expect(delegate.opened.count == 1)
        #expect(delegate.opened.first?.disposition == .foreground)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func popupCanCloseItself(engine: EngineUnderTest) async throws {
        _ = try site.page("closing.html", "<script>setTimeout(() => window.close(), 100)</script>")
        let opener = try site.page("opener.html", "<script>window.open('closing.html')</script>")
        let delegate = RecordingDelegate()
        let openerTab = try await loadedTab(engine.make(), opener, delegate: delegate)
        try await eventually { !delegate.closeRequests.isEmpty }
        withExtendedLifetime(openerTab) {}
        #expect(delegate.closeRequests == delegate.opened.map(\.tab.id))
    }

    @Test(arguments: EngineUnderTest.allCases)
    func confirmUsesDelegateAnswer(engine: EngineUnderTest) async throws {
        let page = try site.page("confirm.html", "<script>document.title = confirm('ok?') ? 'yes' : 'no'</script>")
        let delegate = RecordingDelegate()
        delegate.answer = .accepted(text: nil)
        let tab = try await loadedTab(engine.make(), page, delegate: delegate)
        try await eventually { tab.state.title == "yes" }
        #expect(delegate.dialogs == [.confirm(message: "ok?")])
    }

    @Test(arguments: EngineUnderTest.allCases)
    func promptReturnsDelegateText(engine: EngineUnderTest) async throws {
        let page = try site.page("prompt.html", "<script>document.title = prompt('name?', 'x')</script>")
        let delegate = RecordingDelegate()
        delegate.answer = .accepted(text: "Brow")
        let tab = try await loadedTab(engine.make(), page, delegate: delegate)
        try await eventually { tab.state.title == "Brow" }
        #expect(delegate.dialogs == [.prompt(message: "name?", defaultText: "x")])
    }

    @Test(arguments: EngineUnderTest.allCases)
    func dialogsWithoutDelegateCancel(engine: EngineUnderTest) async throws {
        let page = try site.page("confirm.html", "<script>document.title = confirm('ok?') ? 'yes' : 'no'</script>")
        let tab = try await loadedTab(engine.make(), page)
        try await eventually { tab.state.title == "no" }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func userAgentLooksLikeAFullBrowser(engine: EngineUnderTest) async throws {
        let page = try site.page("ua.html", "<script>document.title = navigator.userAgent</script>")
        let tab = try await loadedTab(engine.make(), page)
        try await eventually { tab.state.title?.contains("Safari/") == true }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func closeDetachesContentView(engine: EngineUnderTest) async throws {
        let a = try site.page("a.html", "<title>A</title>")
        let tab = try await loadedTab(engine.make(), a)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        container.addSubview(tab.contentView)
        tab.close()
        #expect(tab.contentView.superview == nil)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func failedLoadShowsErrorPage(engine: EngineUnderTest) async throws {
        let unreachable = URL(string: "https://brow-test.invalid/")!
        let tab = engine.make().makeTab(url: unreachable)
        try await eventually { tab.state.title == "Can’t open this page" }
        #expect(tab.state.url == unreachable)
    }

    @Test(arguments: EngineUnderTest.allCases)
    func faviconFromLinkTag(engine: EngineUnderTest) async throws {
        let page = try site.page("icon.html", "<link rel='icon' href='icon.png'><title>I</title>")
        let tab = try await loadedTab(engine.make(), page)
        try await eventually { tab.state.faviconURL == site.folder.appending(path: "icon.png") }
    }

    @Test(arguments: EngineUnderTest.allCases)
    func stateChangesReachDelegate(engine: EngineUnderTest) async throws {
        let a = try site.page("a.html", "<title>A</title>")
        let delegate = RecordingDelegate()
        _ = try await loadedTab(engine.make(), a, delegate: delegate)
        #expect(delegate.stateChanges > 0)
    }
}
