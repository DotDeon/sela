import Foundation
import Testing
import ArcImport

@Test func reportSummarisesFixture() throws {
    let report = inspectReport(try importFixture())
    #expect(report == """
    Spaces: 2
      Work: 2 pinned (1 folder), 1 unpinned
      Untitled space: 0 pinned (0 folders), 0 unpinned
    Favourites: 1
    Warnings: 3
      Skipped unsupported item easel-1 (easel)
      Dropped missing child missing-id from folder-1
      Dropped 1 item not reachable from any space
    """)
}
