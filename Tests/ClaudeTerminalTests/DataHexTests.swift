import XCTest
@testable import ClaudeTerminal

// MARK: - Data Hex Encoding/Decoding Tests
// Covers Data.hexString and Data(hexString:) used by HMAC signing.

final class DataHexTests: XCTestCase {

    // MARK: - hexString encoding

    func testEmptyDataHexString() {
        XCTAssertEqual(Data().hexString, "")
    }

    func testSingleByteHexString() {
        XCTAssertEqual(Data([0x00]).hexString, "00")
        XCTAssertEqual(Data([0xff]).hexString, "ff")
        XCTAssertEqual(Data([0x0f]).hexString, "0f")
        XCTAssertEqual(Data([0xab]).hexString, "ab")
    }

    func testMultiByteHexString() {
        XCTAssertEqual(Data([0xde, 0xad, 0xbe, 0xef]).hexString, "deadbeef")
    }

    func testAllZeroesHexString() {
        XCTAssertEqual(Data([0x00, 0x00, 0x00]).hexString, "000000")
    }

    func testAllOnesHexString() {
        XCTAssertEqual(Data([0xff, 0xff]).hexString, "ffff")
    }

    func testKnownHMACPatternHexString() {
        // SHA-256 output is 32 bytes → 64 hex chars
        let bytes = [UInt8](repeating: 0xca, count: 32)
        let hex = Data(bytes).hexString
        XCTAssertEqual(hex.count, 64)
        XCTAssertTrue(hex.allSatisfy { "0123456789abcdef".contains($0) })
    }

    // MARK: - hexString decoding

    func testDecodeEmptyString() {
        XCTAssertEqual(Data(hexString: ""), Data())
    }

    func testDecodeSingleByte() {
        XCTAssertEqual(Data(hexString: "ff"), Data([0xff]))
        XCTAssertEqual(Data(hexString: "00"), Data([0x00]))
        XCTAssertEqual(Data(hexString: "0f"), Data([0x0f]))
    }

    func testDecodeMultiByte() {
        XCTAssertEqual(Data(hexString: "deadbeef"), Data([0xde, 0xad, 0xbe, 0xef]))
    }

    func testDecodeUppercase() {
        XCTAssertEqual(Data(hexString: "DEADBEEF"), Data([0xde, 0xad, 0xbe, 0xef]))
    }

    func testDecodeMixedCase() {
        XCTAssertEqual(Data(hexString: "DeAdBeEf"), Data([0xde, 0xad, 0xbe, 0xef]))
    }

    func testDecodeOddLengthReturnsNil() {
        XCTAssertNil(Data(hexString: "abc"))   // odd
        XCTAssertNil(Data(hexString: "a"))     // odd
    }

    func testDecodeInvalidCharsReturnsNil() {
        XCTAssertNil(Data(hexString: "zz"))
        XCTAssertNil(Data(hexString: "gg"))
        XCTAssertNil(Data(hexString: "0x0f")) // "0x" is not valid hex pair
    }

    func testDecodeSpaceReturnsNil() {
        XCTAssertNil(Data(hexString: "de ad")) // spaces
    }

    // MARK: - Round-trip

    func testRoundTripEncodeDecode() {
        let original = Data((0...255).map { UInt8($0) })
        let hex = original.hexString
        let decoded = Data(hexString: hex)
        XCTAssertEqual(decoded, original)
    }

    func testRoundTripDecodeEncode() {
        let hex = "cafebabe0102030405060708090a0b0c0d0e0f"
        let data = Data(hexString: hex)!
        XCTAssertEqual(data.hexString, hex)
    }

    // MARK: - HMAC key material (32 bytes = 64 hex chars)

    func testHMACKeyHexLength() {
        // IPCServer generates a 256-bit key = 32 bytes = 64 hex chars
        let server = IPCServer()
        XCTAssertEqual(server.hmacKeyHex.count, 64)
        XCTAssertTrue(server.hmacKeyHex.allSatisfy { "0123456789abcdef".contains($0) })
    }

    func testHMACKeyHexIsUniquePerInstance() {
        let s1 = IPCServer()
        let s2 = IPCServer()
        // Extremely unlikely to collide — 2^256 keyspace
        XCTAssertNotEqual(s1.hmacKeyHex, s2.hmacKeyHex)
    }

    // MARK: - WebSocket Bearer Token

    func testBearerTokenLength() {
        let server = WebSocketEventServer()
        // 32 random bytes → 64 hex chars
        XCTAssertEqual(server.bearerToken.count, 64)
    }

    func testBearerTokenIsUniquePerInstance() {
        let s1 = WebSocketEventServer()
        let s2 = WebSocketEventServer()
        XCTAssertNotEqual(s1.bearerToken, s2.bearerToken)
    }

    func testBearerTokenIsHexOnly() {
        let server = WebSocketEventServer()
        XCTAssertTrue(server.bearerToken.allSatisfy { "0123456789abcdef".contains($0) })
    }
}
