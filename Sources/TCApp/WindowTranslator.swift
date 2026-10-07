import AppKit
import TCCore

/// Přeloží texty v oknech a dialozích (popisky, tlačítka, záhlaví tabulek, nabídky) podle jazyka v nastavení.
/// Volá se automaticky při otevření okna a opakovaně, dokud se okno mění (např. doplnění stavových textů).
@MainActor
enum WindowTranslator {
    private static var observers: [NSObjectProtocol] = []

    static func install() {
        guard observers.isEmpty else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didUpdateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { n in
                MainActor.assumeIsolated { if let w = n.object as? NSWindow { translate(w) } }
            })
        }
    }

    private static var language: String { AppModel.shared.settings.language }

    private static func tr(_ s: String) -> String { s.isEmpty ? s : Localization.translate(s, language: language) }

    static func translate(_ window: NSWindow) {
        guard language == "en", window.title != "TCommander" else { return }          // hlavní okno se překládá funkcí L()
        let t = tr(window.title)
        if t != window.title { window.title = t }
        if let v = window.contentView { walk(v) }
    }

    private static func walk(_ v: NSView) {
        switch v {
        case let p as NSPopUpButton:
            for item in p.itemArray { let t = tr(item.title); if t != item.title { item.title = t } }
        case let b as NSButton:
            let t = tr(b.title); if t != b.title { b.title = t }
            let a = tr(b.alternateTitle); if a != b.alternateTitle { b.alternateTitle = a }
            if let tip = b.toolTip, !tip.isEmpty { let t = tr(tip); if t != tip { b.toolTip = t } }
        case let f as NSTextField:
            if !f.isEditable {
                let t = tr(f.stringValue); if t != f.stringValue { f.stringValue = t }
            }
            if let ph = f.placeholderString, !ph.isEmpty { let t = tr(ph); if t != ph { f.placeholderString = t } }
        case let s as NSSegmentedControl:
            for i in 0..<s.segmentCount { if let l = s.label(forSegment: i) { let t = tr(l); if t != l { s.setLabel(t, forSegment: i) } } }
        case let tab as NSTabView:
            for item in tab.tabViewItems { let t = tr(item.label); if t != item.label { item.label = t } }
        case let table as NSTableView:
            for c in table.tableColumns { let t = tr(c.title); if t != c.title { c.title = t } }
            return                                                                  // obsah buněk se nepřekládá (soubory, cesty)
        case is NSOutlineView, is NSCollectionView:
            return
        default: break
        }
        for sub in v.subviews { walk(sub) }
    }
}
