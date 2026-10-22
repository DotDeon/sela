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
}
