import Foundation

/// A bookmark or bookmark folder from another browser, in the browser's order.
public indirect enum ImportedBookmark: Equatable, Sendable {
    case link(title: String?, url: URL)
    case folder(title: String, children: [ImportedBookmark])
}

/// A page from another browser's history.
public struct ImportedVisit: Equatable, Sendable {
    public let url: URL
    public let title: String?
    public let visitCount: Int
    public let lastVisitedAt: Date

    public init(url: URL, title: String?, visitCount: Int, lastVisitedAt: Date) {
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.lastVisitedAt = lastVisitedAt
    }
}

/// What a browser profile holds that Sela can bring in.
public struct BrowserData: Equatable, Sendable {
    public var bookmarks: [ImportedBookmark]
    public var visits: [ImportedVisit]

    public init(bookmarks: [ImportedBookmark], visits: [ImportedVisit]) {
        self.bookmarks = bookmarks
        self.visits = visits
    }
}

public enum BrowserImportError: Error, Equatable, Sendable {
    /// macOS refused to let Sela read the files. Safari's need Full Disk Access.
    case needsFullDiskAccess
    case malformed(String)
}

extension BrowserImportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .needsFullDiskAccess: "macOS needs to give Sela Full Disk Access to read these files."
        case .malformed(let detail): detail
        }
    }
}

/// Reads a profile's bookmarks and its history since `historySince`, newest first. Missing files give nothing.
/// Never writes to the browser's files.
public func readBrowserData(from profile: BrowserProfile, historySince cutoff: Date) throws -> BrowserData {
    switch profile.browser {
    case .chrome, .brave, .edge:
        let bookmarksFile = profile.folder.appending(path: "Bookmarks")
        let bookmarks = try readIfPresent(bookmarksFile).map(parseChromiumBookmarks) ?? []
        let visits = try readChromiumHistory(at: profile.folder.appending(path: "History"), since: cutoff)
        return BrowserData(bookmarks: bookmarks, visits: visits)
    case .safari:
        let bookmarks = try readIfPresent(profile.folder.appending(path: "Bookmarks.plist")).map(parseSafariBookmarks) ?? []
        let visits = try readSafariHistory(at: profile.folder.appending(path: "History.db"), since: cutoff)
        return BrowserData(bookmarks: bookmarks, visits: visits)
    }
}

/// The file's contents, or nil when it doesn't exist. A refused read throws `needsFullDiskAccess`.
func readIfPresent(_ file: URL) throws -> Data? {
    do {
        return try Data(contentsOf: file)
    } catch {
        if isMissingFile(error) { return nil }
        if isPermissionDenied(error) { throw BrowserImportError.needsFullDiskAccess }
        throw BrowserImportError.malformed(error.localizedDescription)
    }
}

/// True for the errors macOS gives when privacy settings or file permissions block a read.
func isPermissionDenied(_ error: Error) -> Bool {
    let error = error as NSError
    switch (error.domain, error.code) {
    case (NSCocoaErrorDomain, NSFileReadNoPermissionError), (NSPOSIXErrorDomain, Int(EPERM)), (NSPOSIXErrorDomain, Int(EACCES)):
        return true
    default:
        return (error.userInfo[NSUnderlyingErrorKey] as? Error).map(isPermissionDenied) ?? false
    }
}

private func isMissingFile(_ error: Error) -> Bool {
    let error = error as NSError
    switch (error.domain, error.code) {
    case (NSCocoaErrorDomain, NSFileReadNoSuchFileError), (NSCocoaErrorDomain, NSFileNoSuchFileError), (NSPOSIXErrorDomain, Int(ENOENT)):
        return true
    default:
        return false
    }
}
