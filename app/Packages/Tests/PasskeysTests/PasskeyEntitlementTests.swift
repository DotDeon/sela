import Foundation
import Testing
@testable import Passkeys

@Test func onlyTrueGrantsTheEntitlement() {
    #expect(PasskeyEntitlement.isGranted(kCFBooleanTrue))
    #expect(!PasskeyEntitlement.isGranted(kCFBooleanFalse))
    #expect(!PasskeyEntitlement.isGranted(nil))
}

@Test func valuesThatOnlyLookTrueDontCount() {
    #expect(!PasskeyEntitlement.isGranted("true" as CFString))
    #expect(!PasskeyEntitlement.isGranted(1 as CFNumber))
    #expect(!PasskeyEntitlement.isGranted([true] as CFArray))
}

@Test func theTestRunnerHasNoEntitlement() {
    #expect(!PasskeyEntitlement.isPresent)
}
