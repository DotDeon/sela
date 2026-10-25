import BrowserEngine
import Foundation

/// Groups a page's text into batches of a size the translator handles well: many short strings together, long
/// ones on their own, in page order so the top of the page translates first.
public enum TextBatching {
    public static let maximumCharacters = 4000
    public static let maximumCount = 120

    public static func batches(_ segments: [TextSegment], maximumCharacters: Int = maximumCharacters,
                               maximumCount: Int = maximumCount) -> [[TextSegment]] {
        var batches: [[TextSegment]] = []
        var current: [TextSegment] = []
        var characters = 0
        for segment in segments {
            let length = segment.text.count
            if !current.isEmpty && (characters + length > maximumCharacters || current.count >= maximumCount) {
                batches.append(current)
                current = []
                characters = 0
            }
            current.append(segment)
            characters += length
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    /// How much text the segments hold, for measuring progress.
    public static func characterCount(_ segments: [TextSegment]) -> Int {
        segments.reduce(0) { $0 + $1.text.count }
    }
}
