import AppKit
import TCCore

@MainActor
enum Dialogs {
    /// Přizpůsobí obsah dialogu jeho skutečné velikosti; když by přesáhl obrazovku, vloží ho do posuvníku.
    static func fit(_ stack: NSStackView, minWidth: CGFloat = 360) -> NSView {
        stack.layoutSubtreeIfNeeded()
        var size = stack.fittingSize
        size.width = max(size.width, minWidth)
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let maxW = screen.width - 120, maxH = screen.height - 280
        stack.frame = NSRect(origin: .zero, size: size)
        guard size.width > maxW || size.height > maxH else { return stack }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: min(size.width, maxW), height: min(size.height, maxH)))
        scroll.documentView = stack
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = size.width > maxW
        scroll.drawsBackground = false
        return scroll
    }

    /// Okno s formulářem nesmí být menší, než formulář potřebuje (pokud se vejde na obrazovku).
    static func fitWindow(_ window: NSWindow, form: NSView, padding: CGSize = CGSize(width: 28, height: 0)) {
        form.layoutSubtreeIfNeeded()
        let screen = window.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
        let needW = min(form.fittingSize.width + padding.width, screen.width - 40)
        let current = window.contentView?.frame.size ?? .zero
        window.contentMinSize = NSSize(width: needW, height: window.contentMinSize.height)
        if current.width < needW { window.setContentSize(NSSize(width: needW, height: current.height)); window.center() }
    }

    static func prompt(title: String, message: String, initial: String, ok: String = "OK", secure: Bool = false) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: "Zrušit")
        let field: NSTextField = secure ? NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24)) : NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    static func confirm(title: String, message: String, ok: String, destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .warning : .informational
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: "Zrušit")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func conflictPolicy(count: Int, example: String) -> ConflictPolicy? {
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Soubor již existuje" : "Existuje \(count) souborů se stejným názvem"
        alert.informativeText = count == 1 ? example : "Například: \(example)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Přepsat vše")
        alert.addButton(withTitle: "Přepsat starší")
        alert.addButton(withTitle: "Přeskočit existující")
        alert.addButton(withTitle: "Ponechat obě")
        alert.addButton(withTitle: "Zrušit")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .overwrite
        case .alertSecondButtonReturn: return .overwriteOlder
        case .alertThirdButtonReturn: return .skip
        case NSApplication.ModalResponse(rawValue: 1003): return .keepBoth
        default: return nil
        }
    }

    static func info(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    static func error(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    @discardableResult
    static func output(title: String, text: String, extraButton: String? = nil) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Zavřít")
        if let extraButton { alert.addButton(withTitle: extraButton) }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.string = text
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        alert.accessoryView = scroll
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// Výběr z nabídky; vrací index nebo nil při zrušení.
    static func choose(title: String, message: String, options: [String], ok: String = "OK") -> Int? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: "Zrušit")
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        popup.addItems(withTitles: options)
        alert.accessoryView = popup
        return alert.runModal() == .alertFirstButtonReturn ? popup.indexOfSelectedItem : nil
    }

    /// Dialog Vlastnosti: oprávnění (osmičkově) a datum změny; prázdné pole = beze změny.
    static func properties(title: String, info: String, permissions: String, modified: String) -> (permissions: String, modified: String)? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = info
        alert.addButton(withTitle: "Použít")
        alert.addButton(withTitle: "Zrušit")
        let perm = NSTextField(string: permissions), date = NSTextField(string: modified)
        perm.placeholderString = "např. 644"; date.placeholderString = "dd.MM.yyyy HH:mm:ss"
        func line(_ l: String, _ f: NSTextField) -> NSStackView {
            let t = NSTextField(labelWithString: l); t.widthAnchor.constraint(equalToConstant: 130).isActive = true
            f.widthAnchor.constraint(equalToConstant: 220).isActive = true
            return NSStackView(views: [t, f])
        }
        let stack = NSStackView(views: [line("Oprávnění (osmičkově):", perm), line("Datum změny:", date)])
        stack.orientation = .vertical; stack.alignment = .leading
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: 60)
        alert.accessoryView = stack
        alert.window.initialFirstResponder = perm
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return (perm.stringValue, date.stringValue)
    }
}
