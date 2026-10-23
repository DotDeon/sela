import AppKit
import Testing
import BrowserEngine
@testable import WebKitEngine

@Test func plainClickStaysInTab() {
    #expect(newTabDisposition(modifiers: [], buttonNumber: 0) == nil)
}

@Test func commandClickOpensInBackground() {
    #expect(newTabDisposition(modifiers: [.command], buttonNumber: 0) == .background)
}

@Test func commandShiftClickOpensInForeground() {
    #expect(newTabDisposition(modifiers: [.command, .shift], buttonNumber: 0) == .foreground)
}

@Test func middleClickOpensInBackground() {
    #expect(newTabDisposition(modifiers: [], buttonNumber: 2) == .background)
}
