import BrowserEngine
import Foundation
import Testing
import Browsing

private let a = TabID.make()
private let b = TabID.make()

@Test func leavingATabFloatsItAndComingBackReturnsIt() {
    var pip = AutoPictureInPicture(isEnabled: true)
    #expect(pip.update(visible: [a], windowIsActive: true).isEmpty)
    #expect(pip.update(visible: [b], windowIsActive: true) == [.enter(a)])
    #expect(pip.didEnter(a, floated: true).isEmpty)
    #expect(pip.floating == [a])
    #expect(pip.update(visible: [a], windowIsActive: true) == [.exit(a), .enter(b)])
    #expect(pip.floating.isEmpty)
}

@Test func losingFocusFloatsWhatsOnScreen() {
    var pip = AutoPictureInPicture(isEnabled: true)
    _ = pip.update(visible: [a], windowIsActive: true)
    #expect(pip.update(visible: [a], windowIsActive: false) == [.enter(a)])
    _ = pip.didEnter(a, floated: true)
    #expect(pip.update(visible: [a], windowIsActive: true) == [.exit(a)])
}

@Test func tabsWithNothingPlayingArentTracked() {
    var pip = AutoPictureInPicture(isEnabled: true)
    _ = pip.update(visible: [a], windowIsActive: true)
    _ = pip.update(visible: [b], windowIsActive: true)
    #expect(pip.didEnter(a, floated: false).isEmpty)
    #expect(pip.update(visible: [a], windowIsActive: true) == [.enter(b)])
}

@Test func comingBackBeforeTheVideoFloatsBringsItStraightBack() {
    var pip = AutoPictureInPicture(isEnabled: true)
    _ = pip.update(visible: [a], windowIsActive: true)
    _ = pip.update(visible: [b], windowIsActive: true)
    _ = pip.update(visible: [a], windowIsActive: true)
    #expect(pip.didEnter(a, floated: true) == [.exit(a)])
    #expect(pip.floating.isEmpty)
}

@Test func splitPanesStayPutWhileTheyShow() {
    var pip = AutoPictureInPicture(isEnabled: true)
    _ = pip.update(visible: [a, b], windowIsActive: true)
    #expect(pip.update(visible: [a, b], windowIsActive: true).isEmpty)
    #expect(pip.update(visible: [a], windowIsActive: true) == [.enter(b)])
}

@Test func turnedOffFloatsNothingButStillBringsVideosBack() {
    var pip = AutoPictureInPicture(isEnabled: true)
    _ = pip.update(visible: [a], windowIsActive: true)
    _ = pip.update(visible: [b], windowIsActive: true)
    _ = pip.didEnter(a, floated: true)
    pip.isEnabled = false
    #expect(pip.update(visible: [a], windowIsActive: true) == [.exit(a)])
    #expect(pip.update(visible: [b], windowIsActive: true).isEmpty)
}

@Test func forgottenTabsAreNeverBroughtBack() {
    var pip = AutoPictureInPicture(isEnabled: true)
    _ = pip.update(visible: [a], windowIsActive: true)
    _ = pip.update(visible: [b], windowIsActive: true)
    _ = pip.didEnter(a, floated: true)
    pip.forget(a)
    #expect(pip.update(visible: [a], windowIsActive: true) == [.enter(b)])
}

@Test func settingIsOnUntilTurnedOff() throws {
    let defaults = try #require(UserDefaults(suiteName: "sela-pip-\(UUID().uuidString)"))
    let settings = PictureInPictureSettings(defaults: defaults)
    #expect(settings.isEnabled)
    settings.isEnabled = false
    #expect(!PictureInPictureSettings(defaults: defaults).isEnabled)
}
