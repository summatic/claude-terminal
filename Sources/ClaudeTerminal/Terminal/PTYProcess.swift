import Foundation

#if canImport(Darwin)
import Darwin
#endif

// MARK: - PTY Process

/// Wraps a POSIX PTY + subprocess. Works on macOS only.
final class PTYProcess {

    // MARK: - State

    private(set) var masterFD: Int32 = -1
    private(set) var slaveFD: Int32 = -1
    private(set) var pid: pid_t = 0
    private(set) var isRunning = false

    // MARK: - Callbacks (called on arbitrary background threads)

    /// Called when data arrives from the process stdout/stderr
    var onOutput: ((Data) -> Void)?
    /// Called when the process exits
    var onTermination: ((Int32) -> Void)?

    private var readSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.claudeterminal.pty", qos: .userInteractive)

    // MARK: - Launch

    /// Launch a process inside a PTY.
    /// - Parameters:
    ///   - executable: Full path, e.g. "/bin/zsh"
    ///   - arguments: Arguments (not including argv[0])
    ///   - environment: If nil, inherits current environment
    ///   - workingDirectory: Starting directory
    ///   - columns: Initial terminal width
    ///   - rows: Initial terminal height
    func launch(
        executable: String = "/bin/zsh",
        arguments: [String] = ["-l"],
        environment: [String: String]? = nil,
        workingDirectory: String? = nil,
        columns: UInt16 = 80,
        rows: UInt16 = 24
    ) throws {
        guard !isRunning else { return }

        // 1. Open PTY master
        masterFD = posix_openpt(O_RDWR | O_NOCTTY)
        guard masterFD >= 0 else { throw PTYError.openFailed(errno) }
        guard grantpt(masterFD) == 0 else { throw PTYError.grantFailed(errno) }
        guard unlockpt(masterFD) == 0 else { throw PTYError.unlockFailed(errno) }

        // 2. Get slave PTY path
        guard let slaveName = ptsname(masterFD) else { throw PTYError.ptsnameFailed(errno) }
        slaveFD = open(slaveName, O_RDWR | O_NOCTTY)
        guard slaveFD >= 0 else { throw PTYError.openSlaveFailed(errno) }

        // 3. Set initial window size
        var ws = winsize()
        ws.ws_col = columns
        ws.ws_row = rows
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)

        // 4. Build environment
        let env = buildEnvironment(base: environment, columns: columns, rows: rows)

        // 5. Fork
        pid = fork()
        if pid < 0 {
            throw PTYError.forkFailed(errno)
        }

        if pid == 0 {
            // --- Child process ---
            runChild(
                executable: executable,
                arguments: arguments,
                environment: env,
                workingDirectory: workingDirectory
            )
            // Never returns
        }

        // --- Parent process ---
        close(slaveFD)
        slaveFD = -1
        isRunning = true

        startReading()
        startWaiting()
    }

    // MARK: - Child Process Setup (runs in forked child)

    private func runChild(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String?
    ) {
        // Create new session (detach from parent's controlling terminal)
        _ = setsid()

        // Set slave as controlling terminal
        _ = ioctl(slaveFD, TIOCSCTTY, 0)

        // Redirect stdin/stdout/stderr to slave PTY
        _ = dup2(slaveFD, STDIN_FILENO)
        _ = dup2(slaveFD, STDOUT_FILENO)
        _ = dup2(slaveFD, STDERR_FILENO)

        // Close all other FDs
        if slaveFD > STDERR_FILENO { close(slaveFD) }
        close(masterFD)

        // Change working directory
        if let wd = workingDirectory {
            _ = chdir(wd)
        }

        // Build argv
        let cExecutable = strdup(executable)!
        var argv: [UnsafeMutablePointer<CChar>?] = [cExecutable]
        let argPtrs = arguments.map { strdup($0) }
        argv += argPtrs
        argv.append(nil)

        // Build envp
        let envPairs = environment.map { "\($0.key)=\($0.value)" }
        var envp: [UnsafeMutablePointer<CChar>?] = envPairs.map { strdup($0) }
        envp.append(nil)

        // Exec
        _ = execve(cExecutable, &argv, &envp)

        // If execve fails
        Darwin.exit(1)
    }

    // MARK: - I/O

    /// Send input to the process
    func write(_ data: Data) {
        guard isRunning else { return }
        _ = data.withUnsafeBytes { ptr in
            Darwin.write(masterFD, ptr.baseAddress!, data.count)
        }
    }

    func write(string: String) {
        if let data = string.data(using: .utf8) {
            write(data)
        }
    }

    /// Notify process of terminal resize
    func resize(columns: UInt16, rows: UInt16) {
        guard isRunning else { return }
        var ws = winsize()
        ws.ws_col = columns
        ws.ws_row = rows
        _ = ioctl(masterFD, TIOCSWINSZ, &ws)
        // Send SIGWINCH to child process group
        _ = killpg(pid, SIGWINCH)
    }

    // MARK: - Private: Reading

    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.readAvailable()
        }
        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.masterFD >= 0 {
                close(self.masterFD)
                self.masterFD = -1
            }
        }
        source.resume()
        readSource = source
    }

    private func readAvailable() {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = Darwin.read(masterFD, &buf, buf.count)
        guard n > 0 else {
            readSource?.cancel()
            return
        }
        let data = Data(buf[0..<n])
        DispatchQueue.main.async { [weak self] in
            self?.onOutput?(data)
        }
    }

    // MARK: - Private: Wait for exit

    private func startWaiting() {
        queue.async { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            waitpid(self.pid, &status, 0)
            let code = WIFEXITED(status) ? WEXITSTATUS(status) : -1
            DispatchQueue.main.async {
                self.isRunning = false
                self.onTermination?(code)
            }
        }
    }

    // MARK: - Terminate

    func terminate() {
        guard isRunning else { return }
        kill(pid, SIGTERM)
    }

    func kill() {
        guard isRunning else { return }
        Darwin.kill(pid, SIGKILL)
    }

    // MARK: - Helpers

    private func buildEnvironment(
        base: [String: String]?,
        columns: UInt16,
        rows: UInt16
    ) -> [String: String] {
        var env = base ?? ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["COLUMNS"] = "\(columns)"
        env["LINES"] = "\(rows)"
        env["LC_ALL"] = "en_US.UTF-8"
        env["LANG"] = "en_US.UTF-8"
        return env
    }
}

// MARK: - PTY Errors

enum PTYError: LocalizedError {
    case openFailed(Int32)
    case grantFailed(Int32)
    case unlockFailed(Int32)
    case ptsnameFailed(Int32)
    case openSlaveFailed(Int32)
    case forkFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .openFailed(let e): return "posix_openpt failed: errno \(e)"
        case .grantFailed(let e): return "grantpt failed: errno \(e)"
        case .unlockFailed(let e): return "unlockpt failed: errno \(e)"
        case .ptsnameFailed(let e): return "ptsname failed: errno \(e)"
        case .openSlaveFailed(let e): return "open(slave) failed: errno \(e)"
        case .forkFailed(let e): return "fork failed: errno \(e)"
        }
    }
}
