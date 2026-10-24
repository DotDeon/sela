import Foundation
import Testing
@testable import WebKitEngine

@Test func applicationNameUsesSafariVersion() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "sela-ua-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let plist = folder.appending(path: "Info.plist")
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "27.0"], format: .xml, options: 0).write(to: plist)
    #expect(safariApplicationName(infoPlistURL: plist) == "Version/27.0 Safari/605.1.15")
}

@Test func applicationNameFallsBackWhenMissing() {
    let missing = URL(fileURLWithPath: "/nonexistent/Info.plist")
    #expect(safariApplicationName(infoPlistURL: missing) == "Version/27.0 Safari/605.1.15")
}
