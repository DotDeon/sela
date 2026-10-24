import Foundation
import Testing
@testable import Browsing

private func freshDefaults() -> UserDefaults {
    let name = "SidebarSettingsTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Test func sidebarStartsDocked() {
    #expect(SidebarSettings(defaults: freshDefaults()).isHidden == false)
}

@Test func sidebarRemembersBeingHidden() {
    let defaults = freshDefaults()
    SidebarSettings(defaults: defaults).isHidden = true
    #expect(SidebarSettings(defaults: defaults).isHidden)
}
