import Foundation
import Testing
@testable import BrowserImport

private func fixture(_ name: String, _ ext: String) throws -> Data {
    try Data(contentsOf: try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")))
}

@Test func readsChromiumBookmarksBarInOrderWithOtherBookmarksAfter() throws {
    let bookmarks = try parseChromiumBookmarks(try fixture("ChromeBookmarks", "json"))
    #expect(bookmarks == [
        .link(title: "Example", url: URL(string: "https://example.com/")!),
        .folder(title: "Work", children: [
            .link(title: "Docs", url: URL(string: "https://docs.example.com/start")!),
            .folder(title: "Nested", children: [.link(title: nil, url: URL(string: "https://deep.example.com/")!)]),
        ]),
        .link(title: "Settings", url: URL(string: "chrome://settings/")!),
        .link(title: "Example again", url: URL(string: "https://example.com/")!),
        // The empty "Mobile bookmarks" root is left out.
        .folder(title: "Other bookmarks", children: [.link(title: "Recipes", url: URL(string: "https://recipes.example.org/")!)]),
    ])
}

@Test func malformedChromiumBookmarksThrow() {
    #expect(throws: BrowserImportError.self) { try parseChromiumBookmarks(Data("not json".utf8)) }
}

@Test func readsSafariFavouritesBarThenTheMenuAndSkipsTheReadingList() throws {
    let bookmarks = try parseSafariBookmarks(try fixture("SafariBookmarks", "plist"))
    #expect(bookmarks == [
        .link(title: "Example", url: URL(string: "https://example.com/")!),
        .folder(title: "Reading", children: [.link(title: "News", url: URL(string: "https://news.example.com/")!)]),
        .folder(title: "Bookmarks menu", children: [.link(title: "Menu item", url: URL(string: "https://menu.example.com/")!)]),
    ])
}

@Test func readsBinarySafariBookmarks() throws {
    let xml = try fixture("SafariBookmarks", "plist")
    let plist = try PropertyListSerialization.propertyList(from: xml, format: nil)
    let binary = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    #expect(try parseSafariBookmarks(binary) == parseSafariBookmarks(xml))
}

@Test func malformedSafariBookmarksThrow() {
    #expect(throws: BrowserImportError.self) { try parseSafariBookmarks(Data("not a plist".utf8)) }
}

@Test func unreadableSafariFilesAskForFullDiskAccess() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "sela-safari-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: "Bookmarks.plist")
    try fixture("SafariBookmarks", "plist").write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) }

    let profile = BrowserProfile(browser: .safari, name: nil, folder: folder)
    #expect(throws: BrowserImportError.needsFullDiskAccess) { try readBrowserData(from: profile, historySince: .distantPast) }
}

@Test func recognisesPermissionErrors() {
    #expect(isPermissionDenied(CocoaError(.fileReadNoPermission)))
    #expect(isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))))
    let wrapped = NSError(domain: NSCocoaErrorDomain, code: 0, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
    #expect(isPermissionDenied(wrapped))
    #expect(!isPermissionDenied(CocoaError(.fileReadNoSuchFile)))
}

@Test func missingFilesGiveNothing() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "sela-empty-\(UUID().uuidString)")
    for browser in [Browser.chrome, .safari] {
        let data = try readBrowserData(from: BrowserProfile(browser: browser, name: nil, folder: folder), historySince: .distantPast)
        #expect(data == BrowserData(bookmarks: [], visits: []))
    }
}

@Test func findsProfilesOfInstalledBrowsersOnly() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "sela-browsers-\(UUID().uuidString)")
    let support = root.appending(path: "Application Support")
    let chrome = support.appending(path: "Google/Chrome")
    for profile in ["Default", "Profile 2", "Profile 10", "System Profile", "Guest Profile"] {
        try FileManager.default.createDirectory(at: chrome.appending(path: profile), withIntermediateDirectories: true)
    }
    for profile in ["Default", "Profile 2", "Profile 10", "System Profile"] {
        try Data("{}".utf8).write(to: chrome.appending(path: "\(profile)/Bookmarks"))
    }
    try Data(#"{"profile":{"info_cache":{"Default":{"name":"Personal"},"Profile 2":{"name":"Work"}}}}"#.utf8)
        .write(to: chrome.appending(path: "Local State"))
    // Brave is installed but has never been used: no profile has data.
    try FileManager.default.createDirectory(at: support.appending(path: "BraveSoftware/Brave-Browser/Default"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appending(path: "Library/Safari"), withIntermediateDirectories: true)

    let profiles = BrowserLocations(applicationSupport: support, library: root.appending(path: "Library")).profiles()
    #expect(profiles.map(\.browser) == [.chrome, .chrome, .chrome, .safari])
    #expect(profiles.map(\.folder.lastPathComponent) == ["Default", "Profile 2", "Profile 10", "Safari"])
    #expect(profiles.map(\.name) == ["Personal", "Work", nil, nil])
}
