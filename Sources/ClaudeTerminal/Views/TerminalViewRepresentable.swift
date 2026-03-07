import SwiftUI
import SwiftTerm

// MARK: - Terminal View (NSViewRepresentable wrapping SwiftTerm)

struct TerminalViewRepresentable: NSViewRepresentable {

    let ptyProcess: PTYProcess
    var onResize: ((Int, Int) -> Void)?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let termView = LocalProcessTerminalView(frame: .zero)

        // Configure terminal appearance
        termView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        termView.nativeForegroundColor = NSColor(white: 0.9, alpha: 1.0)
        termView.nativeBackgroundColor = NSColor(white: 0.07, alpha: 1.0)

        // Wire PTY output → terminal input
        ptyProcess.onOutput = { data in
            DispatchQueue.main.async {
                let bytes = [UInt8](data)
                termView.feed(byteArray: bytes)
            }
        }

        // Wire terminal keyboard input → PTY
        termView.processDelegate = context.coordinator

        return termView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Update font or colors if settings change
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(ptyProcess: ptyProcess, onResize: onResize)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {

        let ptyProcess: PTYProcess
        var onResize: ((Int, Int) -> Void)?

        init(ptyProcess: PTYProcess, onResize: ((Int, Int) -> Void)?) {
            self.ptyProcess = ptyProcess
            self.onResize = onResize
        }

        // Called when user types in the terminal
        func send(source: LocalProcessTerminalView, data: ArraySlice<UInt8>) {
            ptyProcess.write(Data(data))
        }

        // Called when terminal size changes (window resize)
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {
            ptyProcess.resize(columns: UInt16(newCols), rows: UInt16(newRows))
            onResize?(newCols, newRows)
        }

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            // Title updates handled by pane's title property
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            if let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
