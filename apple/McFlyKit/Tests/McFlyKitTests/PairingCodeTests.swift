import XCTest
@testable import McFlyKit

final class PairingCodeTests: XCTestCase {
    func testNormalizeKeepsSixDigits() {
        XCTAssertEqual(PairingCode.normalize("123 456"), "123456")
        XCTAssertEqual(PairingCode.normalize("12-34-56-78"), "123456")
        XCTAssertEqual(PairingCode.normalize("abc"), "")
    }

    func testValidity() {
        XCTAssertTrue(PairingCode.isValid("000000"))
        XCTAssertFalse(PairingCode.isValid("12345"))
        XCTAssertFalse(PairingCode.isValid("1234567"))
        XCTAssertFalse(PairingCode.isValid("12345a"))
    }

    func testLinksCarryTheCode() throws {
        XCTAssertEqual(PairingCode.code(from: try XCTUnwrap(URL(string: "https://mcfly.bot/pair?code=123456"))), "123456")
        XCTAssertEqual(PairingCode.code(from: try XCTUnwrap(URL(string: "https://MCFLY.bot/pair/?code=123456&x=1"))), "123456")
        XCTAssertEqual(PairingCode.code(from: try XCTUnwrap(URL(string: "mcfly://pair?code=654321"))), "654321")
        XCTAssertNil(PairingCode.code(from: try XCTUnwrap(URL(string: "https://mcfly.bot/pair?code=12"))))
        XCTAssertNil(PairingCode.code(from: try XCTUnwrap(URL(string: "https://example.com/pair?code=123456"))))
        XCTAssertNil(PairingCode.code(from: try XCTUnwrap(URL(string: "mcfly://auth-callback?code=abc"))))
        XCTAssertEqual(PairingCode.link(for: "123456").absoluteString, "https://mcfly.bot/pair?code=123456")
    }

    func testScannedPayloads() {
        XCTAssertEqual(PairingCode.code(fromScanned: "https://mcfly.bot/pair?code=123456"), "123456")
        XCTAssertEqual(PairingCode.code(fromScanned: " 123456\n"), "123456")
        XCTAssertNil(PairingCode.code(fromScanned: "hello"))
        XCTAssertNil(PairingCode.code(fromScanned: "1234567"))
    }
}
