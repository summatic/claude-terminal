import Foundation

// MARK: - Security Validation Helpers
//
// 이 파일의 함수들은 `internal` 가시성으로 선언되어 있습니다.
// `private`으로 선언하면 `@testable import`로도 테스트할 수 없기 때문입니다.
// AppState, Session 등 내부 소비자가 이 함수를 직접 호출합니다.

/// 파일 경로가 path traversal 공격과 민감한 시스템 경로로부터 안전한지 검증합니다.
///
/// 다음 조건 중 하나라도 해당하면 `false`를 반환합니다:
/// - 절대경로(`/`로 시작)가 아닌 경우
/// - `URL.standardized` 이후에도 `..` 컴포넌트가 남아있는 경우
/// - `/etc/`, `/private/etc/`, `/usr/`, `/bin/`, `/sbin/` 하위인 경우
///
/// - Parameter path: 검증할 절대 파일 경로
/// - Returns: 안전하면 `true`, 위험하면 `false`
///
/// ```swift
/// isValidFilePath("/Users/alice/file.swift")  // true
/// isValidFilePath("/etc/passwd")              // false — 시스템 경로
/// isValidFilePath("/Users/../../etc/shadow")  // false — path traversal
/// isValidFilePath("relative/path")            // false — 상대 경로
/// ```
func isValidFilePath(_ path: String) -> Bool {
    guard path.hasPrefix("/") else { return false }
    let normalized = URL(fileURLWithPath: path).standardized.path
    guard !normalized.contains("..") else { return false }
    let blocked = ["/etc/", "/private/etc/", "/usr/", "/bin/", "/sbin/"]
    return !blocked.contains(where: { normalized.hasPrefix($0) })
}

/// SSH 포트 번호가 유효한 범위(1–65535)인지 검증합니다.
///
/// - Parameter port: 검증할 포트 번호
/// - Returns: 1 이상 65535 이하이면 `true`
///
/// ```swift
/// isValidSSHPort(22)     // true
/// isValidSSHPort(0)      // false — 예약된 포트
/// isValidSSHPort(65536)  // false — 범위 초과
/// ```
func isValidSSHPort(_ port: Int) -> Bool {
    return (1...65535).contains(port)
}

/// 호스트명 또는 IP 주소에 제어 문자나 NUL 바이트가 없는지 검증합니다.
///
/// 이 함수는 HTTP 헤더 인젝션 방어를 목적으로 합니다.
/// `\r\n` 같은 제어 문자가 포함되면 SSH 명령 또는 HTTP 요청에 헤더가 삽입될 수 있습니다.
///
/// - Parameter host: 검증할 호스트명 또는 IP 문자열 (예: "server.example.com", "192.168.1.1")
/// - Returns: 비어있지 않고 제어 문자가 없으면 `true`
///
/// ```swift
/// isValidHost("server.example.com")           // true
/// isValidHost("server.com\r\nX-Evil: yes")    // false — CRLF 인젝션
/// isValidHost("")                              // false — 빈 문자열
/// ```
func isValidHost(_ host: String) -> Bool {
    guard !host.isEmpty else { return false }
    return host.unicodeScalars.allSatisfy {
        !CharacterSet.controlCharacters.contains($0)
    }
}

/// URL 문자열의 스킴이 `http` 또는 `https`인지 검증합니다.
///
/// 터미널 출력에서 감지된 URL을 열기 전에 호출합니다.
/// `file://`, `javascript:`, `data:` 등 악의적인 스킴을 차단합니다.
///
/// - Parameter urlString: 검증할 URL 문자열
/// - Returns: 파싱 가능하고 스킴이 http/https이면 `true`
///
/// ```swift
/// isSafeURLScheme("https://example.com")   // true
/// isSafeURLScheme("file:///etc/passwd")     // false
/// isSafeURLScheme("javascript:alert(1)")   // false
/// ```
func isSafeURLScheme(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString) else { return false }
    return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
}
