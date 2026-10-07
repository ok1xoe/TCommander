import AppKit
import Darwin
import TCCore

/// Shell na pseudoterminálu (posix_spawn se samostatnou relací, aby měl řídicí terminál a fungovalo Ctrl+C).
final class PTYShell: @unchecked Sendable {
    let master: Int32
    private(set) var pid: pid_t = 0
    private var source: DispatchSourceRead?
    var onOutput: ((Data) -> Void)?
    var onExit: (() -> Void)?

    init?(directory: String, shell: String = "/bin/zsh") {
        let m = posix_openpt(O_RDWR | O_NOCTTY)
        guard m >= 0, grantpt(m) == 0, unlockpt(m) == 0, let name = ptsname(m) else { return nil }
        master = m
        let slavePath = String(cString: name)

        var fa: posix_spawn_file_actions_t? = nil
        posix_spawn_file_actions_init(&fa)
        defer { posix_spawn_file_actions_destroy(&fa) }
        posix_spawn_file_actions_addopen(&fa, 0, slavePath, O_RDWR, 0)
        posix_spawn_file_actions_adddup2(&fa, 0, 1)
        posix_spawn_file_actions_adddup2(&fa, 0, 2)
        posix_spawn_file_actions_addchdir_np(&fa, directory)

        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"                                         // barvy; zpracování řízení kurzoru viz TerminalTextBuffer
        env["PROMPT_EOL_MARK"] = ""
        env["CLICOLOR"] = "1"; env["CLICOLOR_FORCE"] = "1"
        env["GIT_CONFIG_COUNT"] = "1"; env["GIT_CONFIG_KEY_0"] = "color.ui"; env["GIT_CONFIG_VALUE_0"] = "always"
        env["LC_ALL"] = env["LC_ALL"] ?? "en_US.UTF-8"
        let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
        let argv = [strdup(shell), strdup("-i"), strdup("-l"), nil]
        defer { envp.forEach { free($0) }; argv.forEach { free($0) } }
        var p: pid_t = 0
        guard posix_spawn(&p, shell, &fa, &attr, argv, envp) == 0 else { close(m); return nil }
        pid = p

        let src = DispatchSource.makeReadSource(fileDescriptor: m, queue: .global())
        src.setEventHandler { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 8192)
            let n = read(self.master, &buf, buf.count)
            if n > 0 { self.onOutput?(Data(buf[0..<n])) } else { self.source?.cancel(); self.onExit?() }
        }
        src.resume()
        source = src
    }

    func send(_ s: String) { let d = Array(s.utf8); _ = d.withUnsafeBufferPointer { write(master, $0.baseAddress, d.count) } }

    func interrupt() { send("\u{03}") }

    /// Oznámí shellu velikost okna (sloupce × řádky), aby programy správně zalamovaly výstup.
    func resize(columns: Int, rows: Int) {
        var ws = winsize(ws_row: UInt16(max(1, min(rows, 1000))), ws_col: UInt16(max(1, min(columns, 1000))), ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(master, UInt(TIOCSWINSZ), &ws)
        if pid > 0 { kill(pid, SIGWINCH) }
    }

    func stop() {
        source?.cancel()
        if pid > 0 { kill(-pid, SIGHUP); kill(pid, SIGKILL); var st: Int32 = 0; waitpid(pid, &st, WNOHANG) }
        close(master)
    }
}

final class TerminalTextView: NSTextView {
    var sendInput: ((String) -> Void)?
    var interrupt: (() -> Void)?
    /// Program zapnul aplikační režim šipek (ESC O A…), např. vim, less, top.
    var applicationCursor = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with e: NSEvent) {
        let f = e.modifierFlags
        if f.contains(.command) { super.keyDown(with: e); return }       // ⌘C kopíruje, ⌘V se řeší v paste
        if f.contains(.control), let c = e.charactersIgnoringModifiers?.lowercased().unicodeScalars.first, c.value >= 97, c.value <= 122 {
            if c == "c" { interrupt?() } else { sendInput?(String(UnicodeScalar(c.value - 96)!)) }
            return
        }
        switch e.keyCode {
        case 36, 76: sendInput?("\r")
        case 51: sendInput?("\u{7F}")
        case 48: sendInput?("\t")
        case 53: sendInput?("\u{1B}")
        case 126: sendInput?(applicationCursor ? "\u{1B}OA" : "\u{1B}[A")
        case 125: sendInput?(applicationCursor ? "\u{1B}OB" : "\u{1B}[B")
        case 124: sendInput?(applicationCursor ? "\u{1B}OC" : "\u{1B}[C")
        case 123: sendInput?(applicationCursor ? "\u{1B}OD" : "\u{1B}[D")
        case 115: sendInput?(applicationCursor ? "\u{1B}OH" : "\u{1B}[H")
        case 119: sendInput?(applicationCursor ? "\u{1B}OF" : "\u{1B}[F")
        case 116: sendInput?("\u{1B}[5~")
        case 121: sendInput?("\u{1B}[6~")
        case 117: sendInput?("\u{1B}[3~")
        case 122: sendInput?("\u{1B}OP")
        case 120: sendInput?("\u{1B}OQ")
        case 99: sendInput?("\u{1B}OR")
        case 118: sendInput?("\u{1B}OS")
        case 96: sendInput?("\u{1B}[15~")
        case 97: sendInput?("\u{1B}[17~")
        case 98: sendInput?("\u{1B}[18~")
        case 100: sendInput?("\u{1B}[19~")
        case 101: sendInput?("\u{1B}[20~")
        case 109: sendInput?("\u{1B}[21~")
        default: if let s = e.characters, !s.isEmpty { sendInput?(s) }
        }
    }

    override func paste(_ sender: Any?) {
        if let s = NSPasteboard.general.string(forType: .string) { sendInput?(s) }
    }
}

/// Okno s terminálem (shell v pseudoterminálu) včetně celoobrazovkových programů (vim, top, less…) na mřížce buněk.
@MainActor
final class TerminalWindow: NSObject, NSWindowDelegate {
    private static var open: [TerminalWindow] = []

    static func show(directory: URL) {
        guard let shell = PTYShell(directory: directory.path) else { Dialogs.error("Terminál", "Shell se nepodařilo spustit."); return }
        let w = TerminalWindow(shell: shell, directory: directory)
        open.append(w)
        w.window.makeKeyAndOrderFront(nil)
    }

    private let window: NSWindow
    private let shell: PTYShell
    private let view = TerminalTextView()
    private var buffer = TerminalTextBuffer()
    private var scheduled = false
    /// Pro ladění: celý dosavadní výstup.
    var transcript: String { buffer.text }
    static var latest: TerminalWindow? { open.last }
    func sendDebug(_ s: String) { shell.send(s) }
    var styleSummary: String { let r = buffer.runs; return "runs=\(r.count) colored=\(r.filter { $0.style.foreground != nil }.count)" }

    private init(shell: PTYShell, directory: URL) {
        self.shell = shell
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 520), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Terminál – \(directory.path)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        view.isEditable = false
        view.isSelectable = true
        view.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        view.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1)
        view.textColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        view.insertionPointColor = .white
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        view.sendInput = { [weak shell] s in shell?.send(s) }
        view.interrupt = { [weak shell] in shell?.interrupt() }
        scroll.documentView = view
        scroll.frame = window.contentView!.bounds
        scroll.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(scroll)
        window.makeFirstResponder(view)
        DispatchQueue.main.async { [weak self] in self?.updateSize() }
        shell.onOutput = { [weak self] data in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(data) } }
        }
        shell.onExit = { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.received(Data("\n[shell skončil – zavřete okno]\n".utf8)) } }
        }
    }

    private func received(_ data: Data) {
        buffer.append(data)
        if !buffer.replies.isEmpty { shell.send(buffer.replies); buffer.replies = "" }
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        scheduled = false
        let normal = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), bold = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let defaultColor = NSColor(calibratedWhite: 0.92, alpha: 1)
        let out = NSMutableAttributedString()
        func ns(_ rgb: UInt32) -> NSColor { NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1) }
        let background = view.backgroundColor
        for run in buffer.runs {
            var fg: NSColor? = run.style.rgb().map(ns), bg: NSColor? = run.style.backgroundRGB().map(ns)
            if run.style.inverse { (fg, bg) = (bg ?? background, fg ?? defaultColor) }
            var attrs: [NSAttributedString.Key: Any] = [.font: run.style.bold ? bold : normal, .foregroundColor: fg ?? defaultColor]
            if let bg { attrs[.backgroundColor] = bg }
            if run.style.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: run.text, attributes: attrs))
        }
        view.textStorage?.setAttributedString(out)
        view.applicationCursor = buffer.applicationCursor
        if buffer.isFullScreen { view.scrollToBeginningOfDocument(nil) } else { view.scrollToEndOfDocument(nil) }
    }

    func windowDidResize(_ notification: Notification) { updateSize() }

    /// Počet sloupců a řádků podle velikosti textové oblasti a písma.
    private func updateSize() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let cw = ("M" as NSString).size(withAttributes: [.font: font]).width, lh = NSLayoutManager().defaultLineHeight(for: font)
        guard let scroll = view.enclosingScrollView, cw > 0, lh > 0 else { return }
        let cols = Int((scroll.contentSize.width - 10) / cw), rows = Int(scroll.contentSize.height / lh)
        buffer.resize(columns: cols, rows: rows)
        shell.resize(columns: cols, rows: rows)
    }

    func windowWillClose(_ notification: Notification) {
        shell.onOutput = nil; shell.onExit = nil
        shell.stop()
        Self.open.removeAll { $0 === self }
    }
}
