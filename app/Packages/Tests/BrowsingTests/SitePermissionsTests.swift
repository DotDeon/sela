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

@Test func sitesListsEveryChoice() {
    let permissions = fresh()
    permissions.remember(true, for: .camera, on: meet)
    permissions.remember(false, for: .microphone, on: other)
    let sites = permissions.sites()
    #expect(sites.map(\.site) == ["example.com", "google.com"])
    #expect(sites[0].camera == nil && sites[0].microphone == false)
    #expect(sites[1].camera == true && sites[1].microphone == nil)
}

@Test func forgetBySiteName() {
    let permissions = fresh()
    permissions.remember(true, for: .camera, on: meet)
    permissions.forget(site: "google.com")
    #expect(permissions.sites().isEmpty)
}
