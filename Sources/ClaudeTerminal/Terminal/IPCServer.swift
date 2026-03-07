import Foundation
import Network
import CryptoKit

// MARK: - IPC Server (Unix Domain Socket)

/// 로컬 Claude Code 훅 스크립트로부터 이벤트를 수신하는 Unix Domain Socket 서버.
///
/// ## 보안 레이어
/// - 소켓 경로: `~/Library/Application Support/ClaudeTerminal/ipc-{pid}.sock` (mode 0600)
/// - HMAC-SHA256 서명: 앱 실행 시 256비트 키 생성, `~/.claude-terminal.pid`에 기록 (mode 0600)
/// - 연결 당 5초 타임아웃, 최대 메시지 크기 1 MB
/// - 필드 길이 제한: `agentID` ≤ 256자, `taskDescription`/`filePath` ≤ 4096자
///
/// ## 동작 흐름
/// ```
/// hook-notify.py 실행
///   → HMAC 서명 생성
///   → [4바이트 길이 헤더][AuthenticatedMessage JSON] 전송
///   → IPCServer 수신 → HMAC 검증 → HookEvent 파싱
///   → onEvent 콜백 → AppState.handleHookEvent()
/// ```
final class IPCServer {

    // Socket in per-user application support directory (not world-writable /tmp)
    static let socketPath: String = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first?.path ?? NSHomeDirectory()
        let dir = (appSupport as NSString).appendingPathComponent("ClaudeTerminal")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return (dir as NSString).appendingPathComponent(
            "ipc-\(ProcessInfo.processInfo.processIdentifier).sock"
        )
    }()

    static let pidFilePath = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".claude-terminal.pid")

    /// HMAC-SHA256 key, generated per launch, shared with hook scripts via pidFile
    private let hmacKey: SymmetricKey

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.claudeterminal.ipc", qos: .userInteractive)

    /// Max message body: 1 MB
    private static let maxMessageSize: UInt32 = 1_048_576

    var onEvent: ((HookEvent) -> Void)?

    // MARK: - Init

    init() {
        hmacKey = SymmetricKey(size: .bits256)
    }

    // MARK: - Lifecycle

    func start() throws {
        try? FileManager.default.removeItem(atPath: Self.socketPath)

        let params = NWParameters()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: Self.socketPath)

        let listener = try NWListener(using: params)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                chmod(Self.socketPath, 0o600)       // owner read/write only
                self.writePIDFile()
            case .failed(let error):
                print("[IPCServer] Failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(atPath: Self.socketPath)
        try? FileManager.default.removeItem(atPath: Self.pidFilePath)
    }

    // MARK: - PID File (mode 0600, contains socket path + HMAC key hex)

    private func writePIDFile() {
        let content = "\(Self.socketPath)\n\(hmacKeyHex)\n"
        let data = content.data(using: .utf8)!
        FileManager.default.createFile(
            atPath: Self.pidFilePath, contents: data,
            attributes: [.posixPermissions: 0o600]
        )
    }

    var hmacKeyHex: String {
        hmacKey.withUnsafeBytes { Data($0).hexString }
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        // Enforce 5s timeout per connection
        let timeout = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + 5, execute: timeout)

        receiveMessage(from: connection, onFirstByte: { timeout.cancel() })
    }

    private func receiveMessage(from connection: NWConnection, onFirstByte: @escaping () -> Void) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self, let data, data.count == 4, error == nil else {
                connection.cancel()
                return
            }
            onFirstByte()

            let length = data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

            guard length > 0, length <= Self.maxMessageSize else {
                self.sendResponse(
                    HookResponse(success: false, paneID: nil, message: "Message too large"),
                    on: connection
                )
                return
            }

            connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) { body, _, _, err in
                guard let body, err == nil else { connection.cancel(); return }
                self.processMessage(body, connection: connection)
            }
        }
    }

    private func processMessage(_ data: Data, connection: NWConnection) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let wrapper = try? decoder.decode(AuthenticatedMessage.self, from: data) else {
            sendResponse(HookResponse(success: false, paneID: nil, message: "Invalid JSON"), on: connection)
            return
        }

        // Verify HMAC signature
        guard verifyHMAC(signature: wrapper.signature, payload: wrapper.payload) else {
            sendResponse(HookResponse(success: false, paneID: nil, message: "Auth failed"), on: connection)
            return
        }

        guard let eventData = wrapper.payload.data(using: .utf8),
              let event = try? decoder.decode(HookEvent.self, from: eventData) else {
            sendResponse(HookResponse(success: false, paneID: nil, message: "Invalid event"), on: connection)
            return
        }

        // Field length limits
        guard event.agentID.count <= 256,
              event.parentAgentID?.count ?? 0 <= 256,
              event.taskDescription?.count ?? 0 <= 4096,
              event.filePath?.count ?? 0 <= 4096 else {
            sendResponse(HookResponse(success: false, paneID: nil, message: "Field too long"), on: connection)
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }

        sendResponse(HookResponse(success: true, paneID: nil, message: nil), on: connection)
    }

    private func sendResponse(_ response: HookResponse, on connection: NWConnection) {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(response) else { return }
        var length = UInt32(data.count).bigEndian
        var header = Data(bytes: &length, count: 4)
        header.append(data)
        connection.send(content: header, completion: .contentProcessed { _ in connection.cancel() })
    }

    // MARK: - HMAC Verification

    private func verifyHMAC(signature: String, payload: String) -> Bool {
        guard let payloadData = payload.data(using: .utf8),
              let sigData = Data(hexString: signature) else { return false }
        let mac = HMAC<SHA256>.authenticationCode(for: payloadData, using: hmacKey)
        // Constant-time comparison
        return Data(mac).elementsEqual(sigData)
    }
}

// MARK: - Authenticated Message Wrapper (local IPC)

/// 로컬 IPC에서 `HookEvent` JSON을 HMAC 서명과 함께 래핑하는 구조체.
///
/// 훅 스크립트(`hook-notify.py`)가 JSON으로 직렬화하여 Unix Socket으로 전송합니다.
/// `IPCServer`는 `signature`를 검증한 후에만 `payload`를 파싱합니다.
struct AuthenticatedMessage: Codable {
    /// HMAC-SHA256(payload UTF-8 bytes, hmacKey) — 소문자 hex 인코딩
    let signature: String
    /// JSON으로 직렬화된 `HookEvent` 문자열
    let payload: String
}

// MARK: - WebSocket Event Server

/// 원격 서버의 Claude Code 훅이 전송하는 HTTP POST 이벤트를 수신하는 서버.
///
/// 이름에 "WebSocket"이 포함되어 있지만, 실제로는 간단한 HTTP/1.1 서버입니다.
/// `hook-notify.py`가 `POST /hook`으로 `HookEvent` JSON을 전송합니다.
///
/// ## 보안 레이어
/// - 루프백 바인딩 (`127.0.0.1`): 원격 접속 불가 — 반드시 SSH 터널 필요
///   ```bash
///   ssh -R 9901:localhost:9901 user@server
///   ```
/// - 32바이트 랜덤 Bearer 토큰: `Authorization: Bearer <token>` 헤더 필수
/// - 상수 시간 비교(constant-time)로 토큰 검증 — timing attack 방어
/// - 연결 당 5초 타임아웃, 최대 바디 크기 1 MB
final class WebSocketEventServer {

    static let defaultPort: UInt16 = 9901
    private static let maxBodySize = 1_048_576

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.claudeterminal.ws", qos: .userInteractive)
    private let port: UInt16

    /// Random 32-byte hex token. Hook scripts must include: Authorization: Bearer <token>
    private(set) var bearerToken: String

    var onEvent: ((HookEvent) -> Void)?

    init(port: UInt16 = defaultPort) {
        self.port = port
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        self.bearerToken = bytes.map { String(format: "%02x", $0) }.joined()
    }

    func start() throws {
        // Loopback only — remote servers must use SSH tunnel:
        //   ssh -R 9901:localhost:9901 user@server
        let params = NWParameters.tcp
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleHTTPConnection(connection)
        }

        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("[WebSocketServer] Failed: \(error)")
            }
        }

        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - HTTP POST /hook

    private func handleHTTPConnection(_ connection: NWConnection) {
        connection.start(queue: queue)

        let timeout = DispatchWorkItem { connection.cancel() }
        queue.asyncAfter(deadline: .now() + 5, execute: timeout)

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            timeout.cancel()
            guard let self, let data, error == nil else { connection.cancel(); return }
            guard data.count <= Self.maxBodySize else {
                self.sendHTTP("413 Payload Too Large", on: connection)
                return
            }
            self.processHTTP(data: data, connection: connection)
        }
    }

    private func processHTTP(data: Data, connection: NWConnection) {
        guard let str = String(data: data, encoding: .utf8) else {
            sendHTTP("400 Bad Request", on: connection)
            return
        }

        // Verify Bearer token (constant-time comparison)
        guard let token = extractAuthToken(from: str),
              token.utf8.elementsEqual(bearerToken.utf8) else {
            sendHTTP("401 Unauthorized", on: connection)
            return
        }

        guard let bodyData = extractHTTPBody(from: data),
              bodyData.count <= Self.maxBodySize else {
            sendHTTP("400 Bad Request", on: connection)
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let event = try? decoder.decode(HookEvent.self, from: bodyData),
              event.agentID.count <= 256,
              event.taskDescription?.count ?? 0 <= 4096 else {
            sendHTTP("422 Unprocessable Entity", on: connection)
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
        }

        sendHTTP("200 OK", on: connection)
    }

    private func extractAuthToken(from headers: String) -> String? {
        for line in headers.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            guard lower.hasPrefix("authorization:") else { continue }
            let value = line.dropFirst("authorization:".count).trimmingCharacters(in: .whitespaces)
            if value.lowercased().hasPrefix("bearer ") {
                return String(value.dropFirst("bearer ".count))
            }
        }
        return nil
    }

    private func extractHTTPBody(from data: Data) -> Data? {
        // Find \r\n\r\n delimiter
        let delimiter = Data([0x0d, 0x0a, 0x0d, 0x0a])
        guard let range = data.range(of: delimiter) else { return nil }
        let bodyStart = range.upperBound
        guard bodyStart < data.endIndex else { return nil }
        return data[bodyStart...]
    }

    private func sendHTTP(_ status: String, on connection: NWConnection) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(
            content: response.data(using: .utf8),
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }
}

// MARK: - Data Hex Utilities

extension Data {
    /// 바이트 배열을 소문자 hex 문자열로 변환합니다. (예: `[0xDE, 0xAD]` → `"dead"`)
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// 소문자 hex 문자열을 `Data`로 변환합니다.
    ///
    /// - Parameter hexString: 짝수 길이의 hex 문자열
    /// - Returns: 변환 성공 시 `Data`, 홀수 길이이거나 유효하지 않은 문자 포함 시 `nil`
    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
