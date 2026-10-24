import Foundation

/// A folder laid out like Arc's Application Support folder: the live one or a snapshot of it.
public struct ArcDataLocation: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/Library/Application Support/Arc`
    public static var live: ArcDataLocation {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ArcDataLocation(root: support.appending(path: "Arc", directoryHint: .isDirectory))
    }

    public var sidebarFileURL: URL {
        root.appending(path: "StorableSidebar.json")
    }

    /// The `History` database of the default profile and of every `Profile N`, where they exist.
    public var historyFileURLs: [URL] {
        let userData = root.appending(path: "User Data", directoryHint: .isDirectory)
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? []
        return folders
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted()
            .map { userData.appending(path: "\($0)/History") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
