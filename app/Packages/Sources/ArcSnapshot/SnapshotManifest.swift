import Foundation

/// Written as `snapshot-manifest.json` inside each snapshot folder.
public struct SnapshotManifest: Codable, Equatable, Sendable {
    public var createdAt: Date
    public var sourcePath: String
    public var arcVersion: String?
    public var fileCount: Int
    public var totalBytes: Int64
    public var skippedSpecialFiles: Int
}
