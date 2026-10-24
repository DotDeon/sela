import Foundation
import Testing
import Browsing

private let report = ProblemReport(
    appVersion: "1.2",
    appBuild: "34",
    macOSVersion: "Version 26.0 (Build 25A354)",
    macModel: "Mac15,6",
    chip: "arm64"
)

private func decodedBody(_ url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "body" }?.value
}

@Test func opensANewIssueOnTheSelaRepo() {
    let components = URLComponents(url: report.issueURL, resolvingAgainstBaseURL: false)
    #expect(components?.scheme == "https")
    #expect(components?.host == "github.com")
    #expect(components?.path == "/DotDeon/sela/issues/new")
    #expect(components?.queryItems?.map(\.name) == ["body"])
}

@Test func bodyRoundTripsThroughTheURL() {
    #expect(decodedBody(report.issueURL) == report.body)
}

@Test func bodyHasTheHeadingsAndTheMac() {
    let body = report.body
    for heading in ["### What happened", "### What you expected", "### Steps to reproduce", "### Your Mac"] {
        #expect(body.contains(heading))
    }
    #expect(body.contains("- Sela: 1.2 (34)"))
    #expect(body.contains("- macOS: Version 26.0 (Build 25A354)"))
    #expect(body.contains("- Mac: Mac15,6"))
    #expect(body.contains("- Chip: arm64"))
}

/// Characters that would end or split the query value if left as they are.
@Test func encodesCharactersThatEndAQueryValue() {
    let tricky = ProblemReport(appVersion: "1&2=3", appBuild: "4+5#6", macOSVersion: "a b\nc", macModel: "%", chip: "?")
    let query = tricky.issueURL.query ?? ""
    #expect(query.hasPrefix("body="))
    let value = query.dropFirst("body=".count)
    for raw in ["&", "=", "+", "#", " ", "\n", "?"] {
        #expect(!value.contains(raw))
    }
    #expect(decodedBody(tricky.issueURL) == tricky.body)
}

/// Only the five fields go in. Nothing about the person, their files or their pages.
@Test func currentReportHoldsNothingPersonal() {
    let current = ProblemReport.current()
    let body = current.body
    #expect(!body.contains(NSUserName()))
    #expect(!body.contains(NSHomeDirectory()))
    #expect(!body.contains("http"))
    #expect(!body.contains("/Users/"))
    #expect(["arm64", "x86_64"].contains(current.chip))
    #expect(!current.macModel.isEmpty)
    #expect(!current.macOSVersion.isEmpty)
}
