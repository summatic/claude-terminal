import Foundation

// MARK: - Security Validation Helpers
// Internal (not private) so @testable import exposes them to tests.

/// Validate an absolute file path against path traversal and sensitive directories.
/// - Must start with /
/// - No ".." components after standardization
/// - Not under system-sensitive prefixes
func isValidFilePath(_ path: String) -> Bool {
    guard path.hasPrefix("/") else { return false }
    let normalized = URL(fileURLWithPath: path).standardized.path
    guard !normalized.contains("..") else { return false }
    let blocked = ["/etc/", "/private/etc/", "/usr/", "/bin/", "/sbin/"]
    return !blocked.contains(where: { normalized.hasPrefix($0) })
}

/// Validate SSH port is in the legal range 1-65535.
func isValidSSHPort(_ port: Int) -> Bool {
    return (1...65535).contains(port)
}

/// Validate a hostname/IP contains no control characters or NUL bytes.
func isValidHost(_ host: String) -> Bool {
    guard !host.isEmpty else { return false }
    return host.unicodeScalars.allSatisfy {
        !CharacterSet.controlCharacters.contains($0)
    }
}

/// Validate a URL string uses only http or https scheme.
func isSafeURLScheme(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString) else { return false }
    return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
}
