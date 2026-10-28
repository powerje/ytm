import Foundation
import Testing

@testable import YTMCore

@Suite struct AuthTests {
    @Test func `SHA-1 matches the FIPS test vectors`() {
        #expect(SAPISIDHash.sha1Hex("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(SAPISIDHash.sha1Hex("") == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
    }

    @Test func `authorization header is SAPISIDHASH <time>_<sha1>`() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let header = SAPISIDHash.authorization(sapisid: "abc123", now: now)
        let expectedHash = SAPISIDHash.sha1Hex("1700000000 abc123 https://music.youtube.com")
        #expect(header == "SAPISIDHASH 1700000000_" + expectedHash)
    }

    @Test func `parses request headers copied from developer tools`() throws {
        let raw = """
            :authority: music.youtube.com
            :method: POST
            accept: */*
            cookie: VISITOR_INFO1_LIVE=xyz; SAPISID=abc/def; __Secure-3PAPISID=abc/def; SID=foo
            x-goog-authuser: 1
            x-origin: https://music.youtube.com
            """
        let creds = try Credentials.parse(rawHeaders: raw)
        #expect(creds.sapisid == "abc/def")
        #expect(creds.authUser == "1")
        #expect(creds.cookie.hasPrefix("VISITOR_INFO1_LIVE=xyz;"))
    }

    @Test func `parses headers from a copied curl command`() throws {
        let raw = """
            curl 'https://music.youtube.com/youtubei/v1/browse?prettyPrint=false' \\
              -H 'accept: */*' \\
              -H 'cookie: __Secure-3PAPISID=zzz; SID=foo' \\
              -H 'x-goog-authuser: 0' \\
              --data-raw '{}'
            """
        let creds = try Credentials.parse(rawHeaders: raw)
        #expect(creds.sapisid == "zzz")
        #expect(creds.authUser == "0")
    }

    @Test func `parses Chrome's curl command with a -b cookie argument`() throws {
        let raw = """
            curl 'https://music.youtube.com/youtubei/v1/browse?prettyPrint=false' \\
              -H 'accept: */*' \\
              -b 'VISITOR_INFO1_LIVE=xyz; SAPISID=cookie/val; SID=foo' \\
              -H 'x-goog-authuser: 0' \\
              --data-raw '{}'
            """
        let creds = try Credentials.parse(rawHeaders: raw)
        #expect(creds.sapisid == "cookie/val")
        #expect(creds.cookie == "VISITOR_INFO1_LIVE=xyz; SAPISID=cookie/val; SID=foo")
    }

    @Test func `strips a stray leading quote from a cut-off cookie line`() throws {
        let raw = "-b 'SAPISID=abc; SID=foo\n-H 'x-goog-authuser: 0' \\"
        let creds = try Credentials.parse(rawHeaders: raw)
        #expect(creds.cookie == "SAPISID=abc; SID=foo")
        #expect(creds.sapisid == "abc")
    }

    @Test func `rejects headers without a Cookie`() {
        #expect(throws: YTMError.self) { try Credentials.parse(rawHeaders: "accept: */*\nx-origin: a") }
    }

    @Test func `rejects a Cookie without SAPISID`() {
        #expect(throws: YTMError.self) { try Credentials.parse(rawHeaders: "cookie: SID=foo; HSID=bar") }
    }

    @Test func `store round-trips credentials with 0600 file and 0700 directory`() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ytm-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AuthStore(fileURL: dir.appendingPathComponent("auth.json"))
        #expect(try store.load() == nil)
        let creds = Credentials(cookie: "SAPISID=abc; SID=x", authUser: "0")
        try store.save(creds)
        #expect(try store.load() == creds)
        let perms = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        let dirPerms = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        #expect(dirPerms == 0o700)
        try store.save(Credentials(cookie: "SAPISID=def", authUser: "2"))
        #expect(try store.load()?.authUser == "2")
        try store.delete()
        #expect(try store.load() == nil)
    }
}
