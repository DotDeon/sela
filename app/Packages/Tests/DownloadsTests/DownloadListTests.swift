import BrowserEngine
import Foundation
import Observation
import Testing
import Downloads

@MainActor
@Observable
private final class StubDownload: BrowserDownload {
    let id = UUID()
    let filename: String
    var progress = 0.0
    var state: DownloadState
    init(_ name: String, state: DownloadState = .downloading) {
        filename = name
        self.state = state
    }
    func cancel() { state = .cancelled }
}

@MainActor @Test func listKeepsNewestFirst() {
    let list = DownloadList()
    list.add(StubDownload("a"))
    list.add(StubDownload("b"))
    #expect(list.downloads.map(\.filename) == ["b", "a"])
}

@MainActor @Test func clearFinishedKeepsActiveOnes() {
    let list = DownloadList()
    list.add(StubDownload("done", state: .finished(URL(fileURLWithPath: "/tmp/done"))))
    list.add(StubDownload("going"))
    list.add(StubDownload("broken", state: .failed("x")))
    list.clearFinished()
    #expect(list.downloads.map(\.filename) == ["going"])
}
