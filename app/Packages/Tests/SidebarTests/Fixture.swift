import Foundation
import Testing
@_exported import BrowTestSupport

/// Polls every 10 ms for up to 2 seconds.
@MainActor
func eventually(_ condition: @MainActor () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition never became true", sourceLocation: sourceLocation)
}
