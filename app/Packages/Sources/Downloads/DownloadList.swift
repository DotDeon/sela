import BrowserEngine
import Observation

/// This session's downloads, newest first. Shared by every window.
@MainActor
@Observable
public final class DownloadList {
    public private(set) var downloads: [any BrowserDownload] = []

    public init() {}

    public func add(_ download: any BrowserDownload) {
        downloads.insert(download, at: 0)
    }

    /// Removes finished, failed and cancelled downloads, keeping the ones still going.
    public func clearFinished() {
        downloads.removeAll { $0.state != .downloading }
    }
}
