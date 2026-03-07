import XCTest
@testable import ClaudeTerminal

// MARK: - Path Traversal Tests

final class FilePathValidationTests: XCTestCase {

    // MARK: - Valid paths

    func testAbsoluteHomePathIsValid() {
        XCTAssertTrue(isValidFilePath("/Users/alice/Documents/notes.md"))
    }

    func testAbsoluteProjectPathIsValid() {
        XCTAssertTrue(isValidFilePath("/Users/alice/projects/myapp/Sources/main.swift"))
    }

    func testHiddenFileInHomeIsValid() {
        XCTAssertTrue(isValidFilePath("/Users/alice/.claude/settings.json"))
    }

    func testTmpPathIsValid() {
        // /tmp is allowed (not in blocklist); app writes sockets there before security patch
        XCTAssertTrue(isValidFilePath("/tmp/somefile.txt"))
    }

    // MARK: - Relative paths rejected

    func testRelativePathRejected() {
        XCTAssertFalse(isValidFilePath("relative/path/file.txt"))
    }

    func testBareFilenameRejected() {
        XCTAssertFalse(isValidFilePath("file.txt"))
    }

    func testDotSlashRejected() {
        XCTAssertFalse(isValidFilePath("./file.txt"))
    }

    // MARK: - Path traversal rejected

    func testDoubleDotComponentRejected() {
        XCTAssertFalse(isValidFilePath("/Users/alice/../../etc/passwd"))
    }

    func testDoubleDotAtStartRejected() {
        XCTAssertFalse(isValidFilePath("/../etc/passwd"))
    }

    func testDoubleDotInMiddleRejected() {
        XCTAssertFalse(isValidFilePath("/Users/alice/projects/../../../etc/shadow"))
    }

    func testDoubleDotComponentAfterStandardization() {
        // URL.standardized resolves .., result must not still contain ..
        XCTAssertFalse(isValidFilePath("/Users/alice/./../../etc/passwd"))
    }

    // MARK: - Sensitive system paths rejected

    func testEtcPasswdRejected() {
        XCTAssertFalse(isValidFilePath("/etc/passwd"))
    }

    func testEtcShadowRejected() {
        XCTAssertFalse(isValidFilePath("/etc/shadow"))
    }

    func testPrivateEtcRejected() {
        XCTAssertFalse(isValidFilePath("/private/etc/hosts"))
    }

    func testUsrBinRejected() {
        XCTAssertFalse(isValidFilePath("/usr/bin/python3"))
    }

    func testBinShRejected() {
        XCTAssertFalse(isValidFilePath("/bin/sh"))
    }

    func testSbinRejected() {
        XCTAssertFalse(isValidFilePath("/sbin/launchd"))
    }

    func testUsrLocalRejected() {
        XCTAssertFalse(isValidFilePath("/usr/local/bin/brew"))
    }

    // MARK: - Edge cases

    func testEmptyStringRejected() {
        XCTAssertFalse(isValidFilePath(""))
    }

    func testSlashOnlyIsEdgeCase() {
        // "/" is absolute and not blocked — root dir is technically valid
        // but contains no ".." and isn't under blocked prefixes
        XCTAssertTrue(isValidFilePath("/"))
    }

    func testNullByteInPath() {
        // URL parsing with embedded NUL: URL(fileURLWithPath:) may truncate at NUL
        let pathWithNul = "/Users/alice/file\0/etc/passwd"
        // Either rejected as not starting with "/" or sanitized — the important thing
        // is it doesn't pass through to /etc
        let result = isValidFilePath(pathWithNul)
        if result {
            // If it passed, ensure the normalized path isn't under /etc
            let normalized = URL(fileURLWithPath: pathWithNul).standardized.path
            XCTAssertFalse(normalized.hasPrefix("/etc"))
        }
    }
}

// MARK: - SSH Port Validation Tests

final class SSHPortValidationTests: XCTestCase {

    func testPort22IsValid() {
        XCTAssertTrue(isValidSSHPort(22))
    }

    func testPort1IsValid() {
        XCTAssertTrue(isValidSSHPort(1))
    }

    func testPort65535IsValid() {
        XCTAssertTrue(isValidSSHPort(65535))
    }

    func testPort0IsInvalid() {
        XCTAssertFalse(isValidSSHPort(0))
    }

    func testNegativePortIsInvalid() {
        XCTAssertFalse(isValidSSHPort(-1))
    }

    func testPort65536IsInvalid() {
        XCTAssertFalse(isValidSSHPort(65536))
    }

    func testPort99999IsInvalid() {
        XCTAssertFalse(isValidSSHPort(99999))
    }

    func testPortIntMinIsInvalid() {
        XCTAssertFalse(isValidSSHPort(Int.min))
    }

    func testPortIntMaxIsInvalid() {
        XCTAssertFalse(isValidSSHPort(Int.max))
    }
}

// MARK: - Host Validation Tests

final class HostValidationTests: XCTestCase {

    func testValidHostname() {
        XCTAssertTrue(isValidHost("server.example.com"))
    }

    func testValidIP() {
        XCTAssertTrue(isValidHost("192.168.1.1"))
    }

    func testValidLocalhost() {
        XCTAssertTrue(isValidHost("localhost"))
    }

    func testValidUserAtHost() {
        XCTAssertTrue(isValidHost("user@server.example.com"))
    }

    func testEmptyHostRejected() {
        XCTAssertFalse(isValidHost(""))
    }

    func testHostWithNewlineRejected() {
        XCTAssertFalse(isValidHost("server.com\nX-Injected: evil"))
    }

    func testHostWithCarriageReturnRejected() {
        XCTAssertFalse(isValidHost("server.com\r\nX-Injected: evil"))
    }

    func testHostWithNulByteRejected() {
        XCTAssertFalse(isValidHost("server.com\0evil"))
    }

    func testHostWithTabRejected() {
        XCTAssertFalse(isValidHost("server\t.com"))
    }
}

// MARK: - URL Scheme Validation Tests

final class URLSchemeValidationTests: XCTestCase {

    func testHttpsIsAllowed() {
        XCTAssertTrue(isSafeURLScheme("https://example.com/page"))
    }

    func testHttpIsAllowed() {
        XCTAssertTrue(isSafeURLScheme("http://example.com/page"))
    }

    func testFileSchemeRejected() {
        XCTAssertFalse(isSafeURLScheme("file:///etc/passwd"))
    }

    func testJavascriptSchemeRejected() {
        XCTAssertFalse(isSafeURLScheme("javascript:alert(1)"))
    }

    func testFtpSchemeRejected() {
        XCTAssertFalse(isSafeURLScheme("ftp://files.example.com"))
    }

    func testSshSchemeRejected() {
        XCTAssertFalse(isSafeURLScheme("ssh://server.com"))
    }

    func testDataUriRejected() {
        XCTAssertFalse(isSafeURLScheme("data:text/html,<script>alert(1)</script>"))
    }

    func testEmptyStringRejected() {
        XCTAssertFalse(isSafeURLScheme(""))
    }

    func testMalformedURLRejected() {
        XCTAssertFalse(isSafeURLScheme("not a url at all"))
    }

    func testHTTPSCaseInsensitive() {
        XCTAssertTrue(isSafeURLScheme("HTTPS://example.com"))
    }
}
