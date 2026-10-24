import Foundation
import Testing
import Downloads

private let folder = URL(fileURLWithPath: "/tmp/downloads-test", isDirectory: true)

@Test func takenNamesGetANumber() {
    let taken: Set<String> = ["report.pdf", "report 2.pdf", "report 3.pdf"]
    let url = availableDestination(for: "report.pdf", in: folder) { taken.contains($0.lastPathComponent) }
    #expect(url.lastPathComponent == "report 4.pdf")
    #expect(url.deletingLastPathComponent().path == folder.path)
}

@Test func freeNamesStayAsTheyAre() {
    #expect(availableDestination(for: "photo.jpg", in: folder) { _ in false }.lastPathComponent == "photo.jpg")
}

@Test func namesWithoutExtensions() {
    let url = availableDestination(for: "README", in: folder) { $0.lastPathComponent == "README" }
    #expect(url.lastPathComponent == "README 2")
}

@Test func unsafeNamesAreCleaned() {
    #expect(availableDestination(for: "../../etc/passwd", in: folder) { _ in false }.lastPathComponent == "passwd")
    #expect(availableDestination(for: "", in: folder) { _ in false }.lastPathComponent == "download")
    #expect(availableDestination(for: ".hidden", in: folder) { _ in false }.lastPathComponent == "hidden")
}

@Test func partialFilesEndInDownload() {
    #expect(partialURL(for: folder.appending(path: "a.zip")).lastPathComponent == "a.zip.download")
}
