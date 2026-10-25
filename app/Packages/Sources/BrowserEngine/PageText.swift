import Foundation

/// One run of text in a page: a text node's content, trimmed, with the number the page gave the node so a
/// translation can be written back to it.
public struct TextSegment: Hashable, Sendable, Codable {
    public var id: Int
    public var text: String

    public init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

/// What a page says about its language, and a sample of its visible text for telling when it doesn't say.
public struct PageLanguageSample: Equatable, Sendable, Codable {
    /// The `lang` attribute on the document, empty when the page has none.
    public var declared: String
    public var text: String

    public init(declared: String, text: String) {
        self.declared = declared
        self.text = text
    }
}
