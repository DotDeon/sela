import Foundation

/// Written as `snapshot-manifest.json` inside each snapshot folder.
public struct SnapshotManifest: Codable, Equatable, Sendable {
    public var createdAt: Date
    public var sourcePath: String
    public var arcVersion: String?
    public var fileCount: Int
    public var totalBytes: Int64
    public var skippedSpecialFiles: Int
    /// True when Arc was open at the start or end of the copy. Such a snapshot may hold inconsistent databases.
    public var takenWhileArcRunning: Bool
}

/// Things the owner should know after a snapshot, most important first.
public func snapshotNotes(for manifest: SnapshotManifest) -> [String] {
    var notes: [String] = []
    if manifest.takenWhileArcRunning {
        notes.append("This snapshot was taken while Arc was running, so some of its databases may be inconsistent. Quit Arc and take another one.")
    }
    notes.append("Arc encrypts saved passwords with a key that stays in this Mac's keychain, so this copy can't recover them on another Mac. Export your passwords to a CSV file from Arc's password settings before Arc shuts down.")
    return notes
}
