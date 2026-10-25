import Foundation
import Testing
import Browsing

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sela-devtools-\(UUID().uuidString)")!
}

@Test func developerToolsStartOff() {
    #expect(DeveloperToolsSettings(defaults: freshDefaults()).isEnabled == false)
}

@Test func developerToolsRememberBeingTurnedOn() {
    let defaults = freshDefaults()
    DeveloperToolsSettings(defaults: defaults).isEnabled = true
    #expect(DeveloperToolsSettings(defaults: defaults).isEnabled)
    DeveloperToolsSettings(defaults: defaults).isEnabled = false
    #expect(!DeveloperToolsSettings(defaults: defaults).isEnabled)
}
