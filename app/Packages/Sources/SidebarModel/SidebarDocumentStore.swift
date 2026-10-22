import Foundation

/// Reads and writes the sidebar JSON file. A file that can't be read is moved aside, never overwritten.
public struct SidebarDocumentStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/Brow/Sidebar.json`. Creates the `Brow` folder if needed.
    public static func defaultFileURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let folder = support.appending(path: "Brow", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "Sidebar.json")
    }

    /// Returns nil when no file exists yet.
    /// Throws `unsupportedVersion` for files from a newer Brow, leaving them in place.
    /// Throws `corruptFile` after moving an unreadable or inconsistent file aside.
    public func load(now: Date = .now) throws -> SidebarDocument? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)

        let document: SidebarDocument
        do {
            let header = try JSONDecoder().decode(Header.self, from: data)
            guard header.version <= SidebarDocument.currentVersion else {
                throw SidebarError.unsupportedVersion(header.version)
            }
            document = try Self.decoder.decode(SidebarDocument.self, from: data)
            try document.validate()
        } catch let error as SidebarError where isUnsupportedVersion(error) {
            throw error
        } catch {
            throw SidebarError.corruptFile(backupURL: try moveAside(now: now))
        }
        return document
    }

    public func save(_ document: SidebarDocument) throws {
        let data = try Self.encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: Helpers

    private struct Header: Decodable {
        let version: Int
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    private func isUnsupportedVersion(_ error: SidebarError) -> Bool {
        if case .unsupportedVersion = error { return true }
        return false
    }

    private func moveAside(now: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = fileURL.deletingPathExtension().lastPathComponent
        let backup = fileURL.deletingLastPathComponent()
            .appending(path: "\(name).corrupt-\(formatter.string(from: now)).\(fileURL.pathExtension)")
        try FileManager.default.moveItem(at: fileURL, to: backup)
        return backup
    }
}
