import BrowserEngine
import Extensions
import Foundation
import Testing

@Test func grantingTakesBackARefusal() {
    let refused = ExtensionPermissions(denied: ["tabs": .distantFuture], deniedMatchPatterns: ["<all_urls>": .distantFuture])
    let granted = refused.granting(["tabs"], matchPatterns: ["<all_urls>"])
    #expect(granted.granted == ["tabs": .distantFuture])
    #expect(granted.grantedMatchPatterns == ["<all_urls>": .distantFuture])
    #expect(granted.denied.isEmpty)
    #expect(granted.deniedMatchPatterns.isEmpty)
}

@Test func expiredChoicesAreDropped() {
    let now = Date(timeIntervalSince1970: 1_000)
    let permissions = ExtensionPermissions(
        granted: ["tabs": now.addingTimeInterval(-1), "storage": .distantFuture],
        denied: ["cookies": now.addingTimeInterval(60)],
        grantedMatchPatterns: ["*://a.example/*": now]
    )
    let current = permissions.removingExpired(at: now)
    #expect(current.granted == ["storage": .distantFuture])
    #expect(current.denied == ["cookies": now.addingTimeInterval(60)])
    #expect(current.grantedMatchPatterns.isEmpty)
}

@Test func onlyNewRequestsAreUngranted() {
    let permissions = ExtensionPermissions(granted: ["storage": .distantFuture], grantedMatchPatterns: ["*://a.example/*": .distantFuture])
    let details = ExtensionDetails(name: "X", version: "2", requestedPermissions: ["storage", "tabs"], requestedMatchPatterns: ["*://a.example/*", "*://b.example/*"])
    let ungranted = permissions.ungranted(in: details)
    #expect(ungranted.permissions == ["tabs"])
    #expect(ungranted.matchPatterns == ["*://b.example/*"])
}

@Test func everySiteIsOneLine() {
    #expect(PermissionSummary.lines(permissions: [], matchPatterns: ["<all_urls>"]) == ["Read and change everything on every website"])
    #expect(PermissionSummary.lines(permissions: [], matchPatterns: ["*://*/*", "https://a.example/*"]) == ["Read and change everything on every website"])
}

@Test func namedSitesAreListed() {
    #expect(PermissionSummary.lines(permissions: [], matchPatterns: ["https://*.github.com/*"]) == ["Read and change your data on github.com"])
    #expect(PermissionSummary.lines(permissions: [], matchPatterns: ["https://b.example/*", "https://a.example/*"])
        == ["Read and change your data on a.example and b.example"])
    #expect(PermissionSummary.lines(permissions: [], matchPatterns: ["https://a.example/*", "https://b.example/*", "https://c.example/*", "https://d.example/*"])
        == ["Read and change your data on a.example, b.example and 2 other sites"])
}

@Test func harmlessPermissionsNeedNoLine() {
    #expect(PermissionSummary.lines(permissions: ["storage", "alarms", "contextMenus"], matchPatterns: []).isEmpty)
}

@Test func relatedPermissionsShareALine() {
    let lines = PermissionSummary.lines(permissions: ["tabs", "webNavigation", "declarativeNetRequest", "webRequest", "cookies"], matchPatterns: [])
    #expect(lines == ["See the address and title of every tab", "Read and change cookies", "Block or change what pages load"])
}
