import AuthenticationServices
import Foundation
import Testing
@testable import Passkeys

@MainActor
private final class FakeAccess: PasskeyAccessSource {
    var access: PasskeyAccess
    var answer: PasskeyAccess
    var isDeviceConfigured: Bool?
    private(set) var requests = 0

    init(_ access: PasskeyAccess, answer: PasskeyAccess = .allowed, isDeviceConfigured: Bool? = true) {
        self.access = access
        self.answer = answer
        self.isDeviceConfigured = isDeviceConfigured
    }

    func requestAccess() async -> PasskeyAccess {
        requests += 1
        access = answer
        return answer
    }
}

@MainActor @Test func notAskedYetOffersToAsk() {
    let model = PasskeyAccessModel(source: FakeAccess(.notDetermined))
    #expect(model.status == "Sela hasn't asked yet")
    #expect(model.action == .requestAccess)
    #expect(model.action?.title == "Allow Access")
}

@MainActor @Test func allowedNeedsNoButton() {
    let model = PasskeyAccessModel(source: FakeAccess(.allowed))
    #expect(model.status == "Allowed")
    #expect(model.action == nil)
}

@MainActor @Test func deniedPointsAtSystemSettings() {
    let model = PasskeyAccessModel(source: FakeAccess(.denied))
    #expect(model.action == .openPrivacySettings)
    #expect(model.explanation.contains("Passkeys Access for Web Browsers"))
    #expect(PasskeyAccessModel.privacySettingsURL.absoluteString.hasSuffix("Privacy_PasskeyAccess"))
}

@MainActor @Test func askingRecordsTheAnswer() async {
    let source = FakeAccess(.notDetermined, answer: .denied)
    let model = PasskeyAccessModel(source: source)
    await model.requestAccess()
    #expect(source.requests == 1)
    #expect(model.access == .denied)
    #expect(!model.isRequesting)
}

@MainActor @Test func refreshPicksUpAChangeMadeInSystemSettings() {
    let source = FakeAccess(.denied)
    let model = PasskeyAccessModel(source: source)
    source.access = .allowed
    #expect(model.access == .denied)
    model.refresh()
    #expect(model.access == .allowed)
}

@MainActor @Test func aMacWithNowhereToKeepPasskeysSaysSo() {
    let model = PasskeyAccessModel(source: FakeAccess(.allowed, isDeviceConfigured: false))
    #expect(model.explanation.contains("iCloud Keychain"))
    let unknown = PasskeyAccessModel(source: FakeAccess(.allowed, isDeviceConfigured: nil))
    #expect(!unknown.explanation.contains("iCloud Keychain"))
}

@Test func systemStatesMapToAccess() {
    #expect(SystemPasskeyAccess.access(from: .authorized) == .allowed)
    #expect(SystemPasskeyAccess.access(from: .denied) == .denied)
    #expect(SystemPasskeyAccess.access(from: .notDetermined) == .notDetermined)
}
