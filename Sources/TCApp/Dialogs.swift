import AppKit
import TCCore

@MainActor
enum Dialogs {
    static func prompt(title: String, message: String, initial: String, ok: String = "OK") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: "Zrušit")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
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

    static func error(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    static func output(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "Zavřít")
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 640, height: 320))
        let tv = NSTextView(frame: scroll.bounds)
        tv.isEditable = false
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.string = text
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        alert.accessoryView = scroll
        alert.runModal()
    }
}
