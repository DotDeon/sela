import BrowserEngine
import Foundation
import Observation
import WebKit

/// A `WKDownload`, written to "<name>.download" next to its destination and renamed when it finishes.
@MainActor
@Observable
final class WebKitDownload: NSObject, BrowserDownload, WKDownloadDelegate {
    let id = UUID()
    private(set) var filename = ""
    private(set) var progress = -1.0
    private(set) var state = DownloadState.downloading

    @ObservationIgnored private let download: WKDownload
    @ObservationIgnored private weak var tab: WebKitTab?
    @ObservationIgnored private var destination: URL?
    @ObservationIgnored private var progressObservation: NSKeyValueObservation?
    @ObservationIgnored private var wasCancelled = false
    @ObservationIgnored var onEnd: ((WebKitDownload) -> Void)?

    init(download: WKDownload, tab: WebKitTab) {
        self.download = download
        self.tab = tab
        super.init()
        download.delegate = self
        progressObservation = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.totalUnitCount > 0 ? progress.fractionCompleted : -1
            Task { @MainActor in self?.progress = fraction }
        }
    }

    func cancel() {
        wasCancelled = true
        download.cancel { _ in }
    }

    /// Removes the unfinished file, for example when Brow quits mid-download.
    func discard() {
        cancel()
        removePartialFile()
    }

    private var partialFile: URL? {
        destination?.appendingPathExtension("download")
    }

    private func removePartialFile() {
        if let partialFile { try? FileManager.default.removeItem(at: partialFile) }
    }

    private func end(_ final: DownloadState) {
        state = final
        progressObservation = nil
        onEnd?(self)
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        filename = suggestedFilename
        guard let tab, let delegate = tab.delegate,
              let chosen = await delegate.tab(tab, didStartDownload: self, suggestedFilename: suggestedFilename)
        else {
            end(.cancelled)
            return nil
        }
        destination = chosen
        filename = chosen.lastPathComponent
        return chosen.appendingPathExtension("download")
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let partialFile, let destination else { return end(.failed("No destination")) }
        do {
            try FileManager.default.moveItem(at: partialFile, to: destination)
            progress = 1
            end(.finished(destination))
        } catch {
            removePartialFile()
            end(.failed(error.localizedDescription))
        }
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        removePartialFile()
        end(wasCancelled ? .cancelled : .failed(error.localizedDescription))
    }
}
