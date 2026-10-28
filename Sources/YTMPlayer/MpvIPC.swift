import Foundation

/// Messages received from mpv over its JSON IPC socket.
public enum MpvMessage: Sendable, Equatable {
    case reply(requestId: Int, error: String, data: MpvValue?)
    case propertyChange(name: String, value: MpvValue?)
    case event(name: String, reason: String?)
}

/// The subset of JSON values mpv sends for the properties this app observes.
public enum MpvValue: Sendable, Equatable {
    case double(Double)
    case bool(Bool)
    case string(String)
    case other

    public var double: Double? { if case .double(let d) = self { return d } else { return nil } }
    public var bool: Bool? { if case .bool(let b) = self { return b } else { return nil } }

    init(_ raw: Any?) {
        switch raw {
        case nil, is NSNull: self = .other
        case let n as NSNumber:
            // JSONSerialization yields NSNumber for both bools and numbers.
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                self = .bool(n.boolValue)
            } else {
                self = .double(n.doubleValue)
            }
        case let s as String: self = .string(s)
        default: self = .other
        }
    }
}

/// Splits a byte stream into newline-delimited JSON messages.
struct MpvLineDecoder {
    private var buffer = Data()

    mutating func feed(_ data: Data) -> [MpvMessage] {
        buffer.append(data)
        var messages: [MpvMessage] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if let message = Self.decode(line: Data(line)) { messages.append(message) }
        }
        return messages
    }

    static func decode(line: Data) -> MpvMessage? {
        guard !line.isEmpty, let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return nil
        }
        if let event = object["event"] as? String {
            if event == "property-change", let name = object["name"] as? String {
                let hasData = object["data"] != nil && !(object["data"] is NSNull)
                return .propertyChange(name: name, value: hasData ? MpvValue(object["data"]) : nil)
            }
            return .event(name: event, reason: object["reason"] as? String)
        }
        if let requestId = object["request_id"] as? Int {
            let hasData = object["data"] != nil && !(object["data"] is NSNull)
            return .reply(
                requestId: requestId, error: object["error"] as? String ?? "",
                data: hasData ? MpvValue(object["data"]) : nil)
        }
        return nil
    }
}

/// Encodes a command for the mpv JSON IPC protocol.
func encodeMpvCommand(_ command: [Any], requestId: Int) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: ["command": command, "request_id": requestId])
    data.append(UInt8(ascii: "\n"))
    return data
}
