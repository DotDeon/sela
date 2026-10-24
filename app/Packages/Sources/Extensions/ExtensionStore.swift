import BrowserEngine
import Foundation

/// One installed extension, as saved on disk.
public struct ExtensionRecord: Codable, Equatable, Identifiable, Sendable {
    /// Also names the extension's folder, and stays the same when it's updated so its saved data survives.
    public var id: String
    public var name: String
    public var version: String?
    public var isEnabled: Bool
    public var installedAt: Date
    public var permissions: ExtensionPermissions

    public init(id: String, name: String, version: String?, isEnabled: Bool = true, installedAt: Date, permissions: ExtensionPermissions = .none) {
        self.id = id
        self.name = name
        self.version = version
        self.isEnabled = isEnabled
        self.installedAt = installedAt
        self.permissions = permissions
    }
}

/// Saves the installed extensions in `Extensions.json`, beside a folder for each extension's files.
public struct ExtensionStore: Sendable {
    public static let currentVersion = 1

    public enum LoadError: Error, Equatable {
        /// Written by a newer Sela. Left alone, and nothing is saved over it.
        case newerVersion
        case unreadable(String)
    }

    private struct File: Codable {
        var version: Int
        var extensions: [ExtensionRecord]
    }

    public let folder: URL
    public var fileURL: URL { folder.appending(path: "Extensions.json") }

    public init(folder: URL) {
        self.folder = folder
    }

    /// The folder holding one extension's files.
    public func contentFolder(for id: String) -> URL {
        folder.appending(path: id, directoryHint: .isDirectory)
    }

    /// No file yet means no extensions.
    public func load() throws(LoadError) -> [ExtensionRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let version = try Self.decoder.decode(VersionOnly.self, from: data).version
            guard version <= Self.currentVersion else { throw LoadError.newerVersion }
            return try Self.decoder.decode(File.self, from: data).extensions
        } catch let error as LoadError {
            throw error
        } catch {
            throw .unreadable(error.localizedDescription)
        }
    }

    public func save(_ records: [ExtensionRecord]) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(File(version: Self.currentVersion, extensions: records)).write(to: fileURL, options: .atomic)
    }

    private struct VersionOnly: Codable {
        var version: Int
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
