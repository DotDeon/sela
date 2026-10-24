import BrowserEngine
import Downloads
import FakeEngine
import Foundation
import Observation
import Testing
import BrowTestSupport
import Browsing
import Sidebar
import SidebarModel

@MainActor
@Observable
private final class StubDownload: BrowserDownload {
    let id = UUID()
    let filename = "file.pdf"
    let progress = 0.0
    let state = DownloadState.downloading
    func cancel() {}
}

@MainActor
private func makeModel(permissions: SitePermissions, downloads: DownloadList = DownloadList()) throws -> BrowserWindowModel {
    let folder = try temporaryFolder()
    let store = SidebarStore(fileStore: SidebarDocumentStore(fileURL: folder.appending(path: "Sidebar.json")), saveDelay: .seconds(60), firstRunDocument: { fixtureDocument() })
    return BrowserWindowModel(engine: FakeEngine(), sidebar: store, downloads: downloads, permissions: permissions)
}

private func freshPermissions() -> SitePermissions {
    SitePermissions(defaults: UserDefaults(suiteName: "brow-ess-\(UUID().uuidString)")!)
}

@MainActor @Test func fileChoicesGoThroughTheWindow() async throws {
    let model = try makeModel(permissions: freshPermissions())
    let chosen = URL(fileURLWithPath: "/tmp/photo.jpg")
    model.onChooseFiles = { multiple, _ in multiple ? nil : [chosen] }
    model.select("u1")
    let tab = try #require(model.liveTab(for: "u1") as? FakeTab)
    #expect(await tab.simulateChooseFiles(multiple: false, directories: false) == [chosen])
}

@MainActor @Test func captureRequestsUseRememberedChoices() async throws {
    let permissions = freshPermissions()
    let site = URL(string: "https://meet.google.com")!
    permissions.remember(true, for: .camera, on: site)
    let model = try makeModel(permissions: permissions)
    var asked = 0
    model.onCaptureRequest = { _, _ in asked += 1; return false }
    model.select("u1")
    let tab = try #require(model.liveTab(for: "u1") as? FakeTab)
    #expect(await tab.simulateCaptureRequest(.camera, origin: site))
    #expect(asked == 0)
    #expect(await tab.simulateCaptureRequest(.microphone, origin: site) == false)
    #expect(asked == 1)
    #expect(permissions.decision(for: .microphone, on: site) == false)
}

@MainActor @Test func downloadsAreListed() async throws {
    let downloads = DownloadList()
    let model = try makeModel(permissions: freshPermissions(), downloads: downloads)
    let target = URL(fileURLWithPath: "/tmp/file.pdf")
    model.onDownloadDestination = { _ in target }
    let delegate: any BrowserTabDelegate = model
    model.select("u1")
    let tab = try #require(model.liveTab(for: "u1"))
    let destination = await delegate.tab(tab, didStartDownload: StubDownload(), suggestedFilename: "file.pdf")
    #expect(destination == target)
    #expect(downloads.downloads.map(\.filename) == ["file.pdf"])
}

@MainActor @Test func twoDownloadsWithOneNameGetTwoFiles() async throws {
    let model = try makeModel(permissions: freshPermissions())
    let folder = try temporaryFolder()
    model.downloadsFolder = folder
    model.select("u1")
    let tab = try #require(model.liveTab(for: "u1"))
    let delegate: any BrowserTabDelegate = model
    let first = await delegate.tab(tab, didStartDownload: StubDownload(), suggestedFilename: "report.pdf")
    let second = await delegate.tab(tab, didStartDownload: StubDownload(), suggestedFilename: "report.pdf")
    #expect(first?.lastPathComponent == "report.pdf")
    #expect(second?.lastPathComponent == "report 2.pdf")
}
