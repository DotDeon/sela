import Foundation
import Observation

public enum DownloadState: Equatable, Sendable {
    case downloading
    case finished(URL)
    case failed(String)
    case cancelled
}

/// A file a page is downloading. Implementations are `@Observable`, so progress and state can be watched.
@MainActor
public protocol BrowserDownload: AnyObject, Observable {
    var id: UUID { get }
    var filename: String { get }
    /// From 0 to 1, or -1 while the size is unknown.
    var progress: Double { get }
    var state: DownloadState { get }
    func cancel()
}
