import AppKit
import TCCore

@MainActor
final class ConnectForm: NSObject {
    struct Result { var connection: SavedConnection; var password: String; var save: Bool }

    private let saved: [SavedConnection]
    private let kind = NSPopUpButton(frame: .zero, pullsDown: false)
    private let host = NSTextField(), port = NSTextField(), user = NSTextField()
    private let password = NSSecureTextField(), path = NSTextField(), name = NSTextField()
    private let identity = NSTextField(), proxy = NSTextField()
    private let selfSigned = NSButton(checkboxWithTitle: "Povolit self-signed certifikát", target: nil, action: nil)
    private let save = NSButton(checkboxWithTitle: "Uložit připojení (heslo do Klíčenky)", target: nil, action: nil)
    private let picker = NSPopUpButton(frame: .zero, pullsDown: false)
    private var currentID = UUID()

    init(saved: [SavedConnection]) { self.saved = saved }

    func run() -> Result? {
        kind.addItems(withTitles: SavedConnection.Kind.available.map(\.rawValue))
        kind.target = self; kind.action = #selector(kindChanged)
        picker.addItem(withTitle: "Nové připojení")
        picker.addItems(withTitles: saved.map(\.name))
        picker.target = self; picker.action = #selector(pickSaved)
        host.placeholderString = "ftp.example.com"; port.placeholderString = "výchozí"
        user.placeholderString = "prázdné = anonymní"; path.stringValue = "/"
        name.placeholderString = "název pro uložení"
        identity.placeholderString = "SFTP: soubor klíče, např. ~/.ssh/id_ed25519 (volitelné)"
        proxy.placeholderString = "např. socks5://127.0.0.1:1080, http://proxy:3128 (volitelné)"
        func row(_ l: String, _ v: NSView) -> NSStackView {
            let t = NSTextField(labelWithString: l); t.alignment = .right
            t.widthAnchor.constraint(equalToConstant: 110).isActive = true
            v.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
            return NSStackView(views: [t, v])
        }
        let stack = NSStackView(views: [
            row("Uložená:", picker), row("Typ:", kind), row("Server:", host), row("Port:", port), row("Uživatel:", user),
            row("Heslo:", password), row("Cesta / sdílená složka:", path), row("Klíč (SFTP):", identity), row("Proxy (FTP, SFTP):", proxy), row("", selfSigned), row("Název:", name), row("", save),
        ])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6

        let alert = NSAlert()
        alert.messageText = "Připojit k serveru"
        alert.informativeText = "FTP/FTPS se otevře v panelu; SMB a WebDAV se připojí jako svazek."
        alert.accessoryView = Dialogs.fit(stack, minWidth: 460)
        alert.addButton(withTitle: "Připojit")
        alert.addButton(withTitle: "Zrušit")
        alert.window.initialFirstResponder = host
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let h = host.stringValue.trimmingCharacters(in: .whitespaces)
        guard !h.isEmpty else { Dialogs.error("Připojení", "Zadejte adresu serveru."); return nil }
        let k = SavedConnection.Kind.available[max(0, kind.indexOfSelectedItem)]
        let n = name.stringValue.trimmingCharacters(in: .whitespaces)
        let c = SavedConnection(id: currentID, name: n.isEmpty ? h : n, kind: k, host: h, port: Int(port.stringValue),
                                user: user.stringValue.trimmingCharacters(in: .whitespaces),
                                path: path.stringValue.isEmpty ? "/" : path.stringValue, allowSelfSigned: selfSigned.state == .on,
                                identityFile: identity.stringValue.trimmingCharacters(in: .whitespaces), proxy: proxy.stringValue.trimmingCharacters(in: .whitespaces))
        return Result(connection: c, password: password.stringValue, save: save.state == .on)
    }

    @objc private func kindChanged() {
        let k = SavedConnection.Kind.available[max(0, kind.indexOfSelectedItem)]
        port.placeholderString = k.defaultPort.map(String.init) ?? "výchozí"
        if k == .sftp && path.stringValue == "/" { path.stringValue = ""; path.placeholderString = "prázdné = domovský adresář" }
        if k != .sftp && path.stringValue.isEmpty { path.stringValue = "/" }
    }

    @objc private func pickSaved() {
        let i = picker.indexOfSelectedItem - 1
        guard saved.indices.contains(i) else { currentID = UUID(); return }
        let c = saved[i]
        currentID = c.id
        kind.selectItem(at: SavedConnection.Kind.available.firstIndex(of: c.kind) ?? 0)
        host.stringValue = c.host; port.stringValue = c.port.map(String.init) ?? ""; user.stringValue = c.user
        path.stringValue = c.path; name.stringValue = c.name
        selfSigned.state = c.allowSelfSigned ? .on : .off
        identity.stringValue = c.identityFile; proxy.stringValue = c.proxy
        password.stringValue = Keychain.password(for: c.id) ?? ""
        save.state = .on
        kindChanged()
    }
}
