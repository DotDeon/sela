import Testing
@testable import WebKitEngine

/// The test runner isn't signed with the browser passkey entitlement, like the shipping build today.
@MainActor @Test func anUnentitledEngineDoesntServePasskeys() {
    let engine = WebKitEngine(configuration: .init(storage: .ephemeral))
    #expect(!engine.servesPasskeys)
}
