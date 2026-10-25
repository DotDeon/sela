import Foundation
import Testing
import WhatsNew

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "sela-whatsnew-\(UUID().uuidString)")!
}

@Test func notesAreReadByVersion() throws {
    let notes = try WhatsNewNotes(json: Data(#"{ "0.1.5": ["One", " Two ", ""], "0.1.4": ["Old"] }"#.utf8))
    #expect(notes.bullets(for: "0.1.5") == ["One", "Two"])
    #expect(notes.bullets(for: "0.1.4") == ["Old"])
    #expect(notes.bullets(for: "0.1.6") == nil)
}

@Test func longListsAreCut() {
    let notes = WhatsNewNotes(bullets: ["1.0": (1...9).map { "Note \($0)" }])
    #expect(notes.bullets(for: "1.0")?.count == WhatsNewNotes.maximumBullets)
}

@Test func emptyListsCountAsNoNotes() {
    #expect(WhatsNewNotes(bullets: ["1.0": [" "]]).bullets(for: "1.0") == nil)
}

@Test(arguments: ["[]", "{ \"0.1.5\": \"text\" }", "not json"])
func badFilesThrow(json: String) {
    #expect(throws: (any Error).self) { try WhatsNewNotes(json: Data(json.utf8)) }
}

@Test func showsAfterAnUpdate() {
    #expect(WhatsNewDecision.shouldShow(current: "0.1.5", lastShown: "0.1.4", isFirstInstall: false, hasNotes: true))
}

@Test func neverShowsOnAFirstInstall() {
    #expect(!WhatsNewDecision.shouldShow(current: "0.1.5", lastShown: nil, isFirstInstall: true, hasNotes: true))
}

/// Someone updating from a Sela that never recorded a version still gets the notes.
@Test func showsWhenNoVersionWasRecordedButSelaRanBefore() {
    #expect(WhatsNewDecision.shouldShow(current: "0.1.5", lastShown: nil, isFirstInstall: false, hasNotes: true))
}

@Test func showsOnceAndNeverWithoutNotes() {
    #expect(!WhatsNewDecision.shouldShow(current: "0.1.5", lastShown: "0.1.5", isFirstInstall: false, hasNotes: true))
    #expect(!WhatsNewDecision.shouldShow(current: "0.1.5", lastShown: "0.1.4", isFirstInstall: false, hasNotes: false))
}

@Test func recordKeepsTheVersion() {
    let defaults = freshDefaults()
    #expect(WhatsNewRecord(defaults: defaults).shownVersion == nil)
    WhatsNewRecord(defaults: defaults).shownVersion = "0.1.5"
    #expect(WhatsNewRecord(defaults: defaults).shownVersion == "0.1.5")
}

/// The file Sela ships reads, and every version in it has 3 to 6 short notes.
@Test func theBundledFileIsWellFormed() throws {
    let file = URL(filePath: #filePath).deletingLastPathComponent()
        .appending(path: "../../../Sela/WhatsNew.json").standardized
    let notes = try WhatsNewNotes(json: try Data(contentsOf: file))
    #expect(notes.bullets.keys.contains("0.1.4"))
    #expect(notes.bullets.keys.contains("0.1.5"))
    for (version, bullets) in notes.bullets {
        #expect((3...6).contains(bullets.count), "\(version) has \(bullets.count) notes")
        for bullet in bullets {
            #expect(bullet.count <= 120, "\(version): \(bullet)")
        }
    }
}
