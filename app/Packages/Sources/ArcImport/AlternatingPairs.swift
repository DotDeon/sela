import Foundation

struct OddLengthPairsError: Error {}

/// Decodes Arc's flat `[key, value, key, value, ...]` arrays.
struct AlternatingPairs<Key: Decodable, Value: Decodable>: Decodable {
    var pairs: [(key: Key, value: Value)]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        pairs = []
        while !container.isAtEnd {
            let key = try container.decode(Key.self)
            guard !container.isAtEnd else { throw OddLengthPairsError() }
            let value = try container.decode(Value.self)
            pairs.append((key, value))
        }
    }

    var values: [Value] { pairs.map(\.value) }
}
