import AppKit
import BrowserEngine
import Foundation
import Testing
import WebKitEngine

/// Every engine the contract runs against. The Chromium plan adds a case.
enum EngineUnderTest: CaseIterable, CustomTestStringConvertible {
    case webKit

    @MainActor
    func make() -> any BrowserEngine {
        switch self {
        case .webKit:
            WebKitEngine(configuration: .init(storage: .ephemeral, allowsPopupsWithoutUserGesture: true))
        }
    }

    var testDescription: String {
        switch self {
        case .webKit: "WebKit"
        }
    }
}

/// HTML pages in a fresh temporary folder.
struct TestSite {
    let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "brow-site-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func page(_ name: String, _ html: String) throws -> URL {
        let url = folder.appending(path: name)
        try Data(html.utf8).write(to: url)
        return url
    }
}

/// Records what pages ask for and answers dialogs with `answer`.
@MainActor
final class RecordingDelegate: BrowserTabDelegate {
    var answer: JavaScriptDialogResult = .dismissed
    private(set) var opened: [(tab: any BrowserTab, disposition: NewTabDisposition)] = []
    private(set) var closeRequests: [TabID] = []
    private(set) var dialogs: [JavaScriptDialog] = []
    private(set) var stateChanges = 0

    func tabStateDidChange(_ tab: any BrowserTab) {
        stateChanges += 1
    }

    func tab(_ tab: any BrowserTab, didOpen newTab: any BrowserTab, disposition: NewTabDisposition) {
        newTab.delegate = self
        opened.append((newTab, disposition))
    }

    func tabDidRequestClose(_ tab: any BrowserTab) {
        closeRequests.append(tab.id)
    }

    func tab(_ tab: any BrowserTab, runDialog dialog: JavaScriptDialog) async -> JavaScriptDialogResult {
        dialogs.append(dialog)
        return answer
    }
}

/// Polls every 50 ms for up to 10 seconds.
@MainActor
func eventually(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}

/// Loads `url` in a new tab and waits for the page to finish.
@MainActor
func loadedTab(_ engine: any BrowserEngine, _ url: URL, delegate: RecordingDelegate? = nil) async throws -> any BrowserTab {
    let tab = engine.makeTab(url: nil)
    tab.delegate = delegate
    tab.load(url)
    try await eventually { tab.state.url == url && !tab.state.isLoading }
    return tab
}
