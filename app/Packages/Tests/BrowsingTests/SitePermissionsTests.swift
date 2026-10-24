import BrowserEngine
import Foundation
import Testing
import Browsing

private func fresh() -> SitePermissions {
    SitePermissions(defaults: UserDefaults(suiteName: "brow-perm-\(UUID().uuidString)")!)
}
private let meet = URL(string: "https://meet.google.com")!
private let accounts = URL(string: "https://accounts.google.com")!
private let other = URL(string: "https://example.com")!

@Test func unknownUntilRemembered() {
    #expect(fresh().decision(for: .camera, on: meet) == nil)
}

@Test func rememberedPerSite() {
    let permissions = fresh()
    permissions.remember(true, for: .camera, on: meet)
    #expect(permissions.decision(for: .camera, on: accounts) == true)
    #expect(permissions.decision(for: .camera, on: other) == nil)
    permissions.remember(false, for: .microphone, on: other)
    #expect(permissions.decision(for: .microphone, on: other) == false)
}

@Test func bothNeedsBoth() {
    let permissions = fresh()
    permissions.remember(true, for: .camera, on: meet)
    #expect(permissions.decision(for: .cameraAndMicrophone, on: meet) == nil)
    permissions.remember(true, for: .cameraAndMicrophone, on: meet)
    #expect(permissions.decision(for: .microphone, on: meet) == true)
    #expect(permissions.decision(for: .cameraAndMicrophone, on: meet) == true)
    permissions.remember(false, for: .microphone, on: meet)
    #expect(permissions.decision(for: .cameraAndMicrophone, on: meet) == false)
}

@Test func forgetClears() {
    let permissions = fresh()
    permissions.remember(true, for: .cameraAndMicrophone, on: meet)
    permissions.forget(siteOf: accounts)
    #expect(permissions.decision(for: .camera, on: meet) == nil)
}
