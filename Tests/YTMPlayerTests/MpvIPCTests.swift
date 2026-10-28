import Foundation
import Testing

@testable import YTMPlayer

@Suite struct MpvIPCTests {
    @Test func `decodes newline-framed messages across chunks`() {
        var decoder = MpvLineDecoder()
        let chunk1 = Data(
            ("{\"event\":\"property-change\",\"id\":2,\"name\":\"duration\",\"data\":213.061}\n"
                + "{\"event\":\"file-loa").utf8)
        let chunk2 = Data(
            ("ded\"}\n{\"request_id\":6,\"error\":\"success\",\"data\":{\"playlist_entry_id\":1}}\n"
                + "{\"event\":\"end-file\",\"reason\":\"eof\"}\n").utf8)
        let first = decoder.feed(chunk1)
        #expect(first == [.propertyChange(name: "duration", value: .double(213.061))])
        let second = decoder.feed(chunk2)
        #expect(
            second == [
                .event(name: "file-loaded", reason: nil),
                .reply(requestId: 6, error: "success", data: .other),
                .event(name: "end-file", reason: "eof"),
            ])
    }

    @Test func `a null property value becomes nil`() {
        let m = MpvLineDecoder.decode(
            line: Data("{\"event\":\"property-change\",\"id\":1,\"name\":\"time-pos\",\"data\":null}".utf8))
        #expect(m == .propertyChange(name: "time-pos", value: nil))
        let p = MpvLineDecoder.decode(
            line: Data("{\"event\":\"property-change\",\"id\":3,\"name\":\"pause\",\"data\":false}".utf8))
        #expect(p == .propertyChange(name: "pause", value: .bool(false)))
    }

    @Test func `encodes commands with a request id and trailing newline`() throws {
        let data = try encodeMpvCommand(["loadfile", "https://x", "replace"], requestId: 3)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["request_id"] as? Int == 3)
        #expect(object?["command"] as? [String] == ["loadfile", "https://x", "replace"])
        #expect(data.last == UInt8(ascii: "\n"))
    }

    @Test func `finds tools on PATH and honours YTM_ overrides`() {
        let env = ["PATH": "/definitely/not/here"]
        #expect(ExternalTools.find(name: "no-such-tool-xyz", environment: env) == nil)
        #expect(ExternalTools.find(name: "ls", environment: ["PATH": "/bin"]) == "/bin/ls")
        #expect(ExternalTools.find(name: "ls", environment: ["PATH": "/nope", "YTM_LS": "/bin/ls"]) == "/bin/ls")
    }
}
