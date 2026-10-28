import Foundation

/// A thin, non-throwing wrapper over `JSONSerialization` output.
///
/// InnerTube responses are deeply nested and change shape often, so parsing is
/// written as "navigate; if anything is missing, return nil" rather than as
/// strict `Codable` models.
struct JSON {
    let raw: Any?

    init(_ raw: Any?) { self.raw = raw }

    static func parse(_ data: Data) throws -> JSON {
        do {
            return JSON(try JSONSerialization.jsonObject(with: data))
        } catch {
            throw YTMError.unexpectedResponse("response was not JSON")
        }
    }

    subscript(key: String) -> JSON {
        JSON((raw as? [String: Any])?[key])
    }

    subscript(index: Int) -> JSON {
        guard let array = raw as? [Any], index >= 0, index < array.count else { return JSON(nil) }
        return JSON(array[index])
    }

    var string: String? { raw as? String }
    var bool: Bool? { raw as? Bool }
    var int: Int? { raw as? Int }
    var double: Double? { (raw as? NSNumber)?.doubleValue }
    var array: [JSON] { (raw as? [Any])?.map(JSON.init) ?? [] }
    var dictionary: [String: JSON] { (raw as? [String: Any])?.mapValues(JSON.init) ?? [:] }
    var isNil: Bool { raw == nil }
    var exists: Bool { raw != nil }

    /// Concatenated text of a `{"runs": [{"text": ...}]}` object.
    var runsText: String? {
        let texts = self["runs"].array.compactMap { $0["text"].string }
        return texts.isEmpty ? nil : texts.joined()
    }

    /// Every value found under `key` anywhere in the tree, in document order
    /// for arrays. Dictionaries are unordered, so siblings under one object
    /// may appear in any order relative to each other.
    func findAll(_ key: String) -> [JSON] {
        var out: [JSON] = []
        collect(key, into: &out)
        return out
    }

    private func collect(_ key: String, into out: inout [JSON]) {
        if let dict = raw as? [String: Any] {
            if let hit = dict[key] { out.append(JSON(hit)) }
            for (_, value) in dict {
                JSON(value).collect(key, into: &out)
            }
        } else if let array = raw as? [Any] {
            for value in array {
                JSON(value).collect(key, into: &out)
            }
        }
    }

    /// First value found under `key` anywhere in the tree.
    func findFirst(_ key: String) -> JSON? {
        if let dict = raw as? [String: Any] {
            if let hit = dict[key] { return JSON(hit) }
            for (_, value) in dict {
                if let hit = JSON(value).findFirst(key) { return hit }
            }
        } else if let array = raw as? [Any] {
            for value in array {
                if let hit = JSON(value).findFirst(key) { return hit }
            }
        }
        return nil
    }
}
