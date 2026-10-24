import Foundation

/// A browser Sela can import bookmarks and history from.
public enum Browser: String, CaseIterable, Sendable {
    case chrome, brave, edge, safari

    public var name: String {
        switch self {
        case .chrome: "Chrome"
        case .brave: "Brave"
        case .edge: "Edge"
        case .safari: "Safari"
        }
    }

    /// The app's bundle identifier, for matching it against the default browser.
    public var bundleIdentifier: String {
        switch self {
        case .chrome: "com.google.Chrome"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .safari: "com.apple.Safari"
        }
    }

    /// Chrome, Brave and Edge share Chromium's file formats.
    public var isChromium: Bool { self != .safari }

    /// Where the browser keeps its profiles, under Application Support. Nil for Safari, which lives in `~/Library/Safari`.
    var applicationSupportPath: String? {
        switch self {
        case .chrome: "Google/Chrome"
        case .brave: "BraveSoftware/Brave-Browser"
        case .edge: "Microsoft Edge"
        case .safari: nil
        }
    }
}

/// One profile of a browser on this Mac: the folder holding its bookmarks and history.
public struct BrowserProfile: Hashable, Identifiable, Sendable {
    public let browser: Browser
    /// The profile's own name, such as "Work". Nil for Safari.
    public let name: String?
    public let folder: URL

    public init(browser: Browser, name: String?, folder: URL) {
        self.browser = browser
        self.name = name
        self.folder = folder
    }

    public var id: String { folder.path }

    /// The file that changes when the browser is used, for guessing which one the user uses most.
    var historyFileURL: URL {
        folder.appending(path: browser.isChromium ? "History" : "History.db")
    }

    /// When the profile was last used, from its history file. Nil when that can't be read.
    public var lastUsedAt: Date? {
        (try? FileManager.default.attributesOfItem(atPath: historyFileURL.path))?[.modificationDate] as? Date
    }
}

/// Where to look for other browsers' data: the live folders or a test copy laid out the same way.
public struct BrowserLocations: Sendable {
    /// `~/Library/Application Support` or a stand-in.
    public let applicationSupport: URL
    /// `~/Library` or a stand-in, holding `Safari`.
    public let library: URL

    public init(applicationSupport: URL, library: URL) {
        self.applicationSupport = applicationSupport
        self.library = library
    }

    public static var live: BrowserLocations {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return BrowserLocations(applicationSupport: support, library: library)
    }

    /// Every profile found, Chrome first, then Brave, Edge and Safari. A Chromium profile counts when it has
    /// bookmarks or history. Safari counts when its folder exists, since reading inside it may need Full Disk Access.
    public func profiles() -> [BrowserProfile] {
        Browser.allCases.flatMap(profiles(of:))
    }

    public func profiles(of browser: Browser) -> [BrowserProfile] {
        let manager = FileManager.default
        guard let path = browser.applicationSupportPath else {
            let folder = library.appending(path: "Safari", directoryHint: .isDirectory)
            return manager.fileExists(atPath: folder.path) ? [BrowserProfile(browser: .safari, name: nil, folder: folder)] : []
        }
        let root = applicationSupport.appending(path: path, directoryHint: .isDirectory)
        let names = profileNames(in: root)
        let folders = (try? manager.contentsOfDirectory(atPath: root.path)) ?? []
        return folders
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .sorted { profileOrder($0) < profileOrder($1) }
            .map { root.appending(path: $0, directoryHint: .isDirectory) }
            .filter { manager.fileExists(atPath: $0.appending(path: "Bookmarks").path) || manager.fileExists(atPath: $0.appending(path: "History").path) }
            .map { BrowserProfile(browser: browser, name: names[$0.lastPathComponent], folder: $0) }
    }

    /// Profile names from Chromium's `Local State`, keyed by folder name.
    private func profileNames(in root: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: root.appending(path: "Local State")),
              let state = try? JSONDecoder().decode(LocalState.self, from: data)
        else { return [:] }
        return (state.profile?.infoCache ?? [:]).compactMapValues { $0.name.flatMap { $0.isEmpty ? nil : $0 } }
    }

    /// "Default" first, then "Profile 1", "Profile 2", … in number order.
    private func profileOrder(_ folder: String) -> Int {
        folder == "Default" ? -1 : Int(folder.dropFirst("Profile ".count)) ?? Int.max
    }
}

private struct LocalState: Decodable {
    struct Profile: Decodable {
        struct Info: Decodable { let name: String? }
        let infoCache: [String: Info]?
        enum CodingKeys: String, CodingKey { case infoCache = "info_cache" }
    }
    let profile: Profile?
}
