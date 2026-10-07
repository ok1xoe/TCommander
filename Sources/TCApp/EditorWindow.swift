import AppKit
import TCCore

/// Vestavěný textový editor (F4): zachová kódování souboru, hlídá neuložené změny, ⌘S ukládá, ⌘F hledá.
@MainActor
final class EditorWindow: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private static var open: [EditorWindow] = []

    /// `saveBack` se zavolá po uložení (u souborů z archivu a serveru nahrává změněný soubor zpět).
    static func show(_ url: URL, saveBack: ((URL) -> Void)? = nil) {
        if let w = open.first(where: { $0.url == url }) { w.window.makeKeyAndOrderFront(nil); return }
        guard let data = try? Data(contentsOf: url) else { Dialogs.error("Soubor nelze otevřít", url.path); return }
        if data.count > 20_000_000 { Dialogs.error("Soubor je příliš velký pro vestavěný editor", "Použijte externí editor (Nastavení › Obecné)."); return }
        if ListerSupport.looksBinary(data) { Dialogs.error("Binární soubor", "Vestavěný editor je jen pro text. Použijte Lister (F3) nebo externí aplikaci."); return }
        let w = EditorWindow(url: url, data: data, saveBack: saveBack)
        open.append(w)
        w.window.makeKeyAndOrderFront(nil)
    }

    private let url: URL
    private let saveBack: ((URL) -> Void)?
    private var encoding: String
    private let window: NSWindow
    private let textView = NSTextView()
    private let status = NSTextField(labelWithString: "")

    private init(url: URL, data: Data, saveBack: ((URL) -> Void)?) {
        self.url = url; self.saveBack = saveBack
        let decoded = TextDecoding.decode(data)
        encoding = decoded.encoding
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = url.lastPathComponent + " – Editor"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.string = decoded.text
        textView.delegate = self
        scroll.documentView = textView
        let save = NSButton(title: "Uložit (⌘S)", target: self, action: #selector(saveAction))
        save.keyEquivalent = "s"; save.keyEquivalentModifierMask = .command
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        status.stringValue = "Kódování: \(encoding)"
        let bar = NSStackView(views: [status, NSView(), save]); bar.spacing = 8
        let c = window.contentView!
        for v in [scroll, bar] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; c.addSubview(v) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: c.topAnchor), scroll.leadingAnchor.constraint(equalTo: c.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            bar.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            bar.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 12), bar.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -8),
        ])
        window.makeFirstResponder(textView)
    }

    func textDidChange(_ notification: Notification) { window.isDocumentEdited = true }

    @objc private func saveAction() { _ = save() }

    @discardableResult
    private func save() -> Bool {
        var data = TextDecoding.encode(textView.string, as: encoding)
        if data == nil {
            guard Dialogs.confirm(title: "Text nelze uložit v kódování \(encoding)", message: "Některé znaky v něm nejsou. Uložit jako UTF-8?", ok: "Uložit jako UTF-8") else { return false }
            encoding = "UTF-8"; data = Data(textView.string.utf8)
        }
        do {
            try data!.write(to: url, options: .atomic)
            window.isDocumentEdited = false
            status.stringValue = "Uloženo · kódování: \(encoding)"
            saveBack?(url)
            return true
        } catch { Dialogs.error("Uložení selhalo", error.localizedDescription); return false }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard window.isDocumentEdited else { return true }
        let alert = NSAlert()
        alert.messageText = "Uložit změny v souboru „\(url.lastPathComponent)“?"
        alert.addButton(withTitle: "Uložit"); alert.addButton(withTitle: "Zahodit změny"); alert.addButton(withTitle: "Zrušit")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    func windowWillClose(_ notification: Notification) { Self.open.removeAll { $0 === self } }
}
