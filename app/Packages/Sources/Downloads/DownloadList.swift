import BrowserEngine
import Foundation
import Observation

/// This session's downloads, newest first. Shared by every window.
@MainActor
@Observable
public final class DownloadList {
    public private(set) var downloads: [any BrowserDownload] = []
    /// Destinations already handed out this session, so two downloads with one name never share a file.
    @ObservationIgnored private var reserved: Set<URL> = []

    public init() {}

    public func add(_ download: any BrowserDownload) {
        downloads.insert(download, at: 0)
    }

    public func reserve(_ destination: URL) {
        reserved.insert(destination.standardizedFileURL)
    }

    public func isReserved(_ destination: URL) -> Bool {
        reserved.contains(destination.standardizedFileURL)
    }

    public func remove(_ id: UUID) {
        downloads.removeAll { $0.id == id }
    }

    /// Removes finished, failed and cancelled downloads, keeping the ones still going.
    public func clearFinished() {
        downloads.removeAll { $0.state != .downloading }
    }
}
