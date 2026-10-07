import AppKit
import TCCore

enum RightLongPress {
    /// Jak dlouho se musí držet pravé tlačítko, aby se nabídla záložka.
    static let delay: TimeInterval = 0.6
}

extension AppModel {
    /// Dlouhé podržení pravého tlačítka nad adresářem: zeptá se, zda ho otevřít v nové záložce stejného panelu.
    func offerTab(forEntryAt index: Int, side: Side) {
        let g = group(side)
        let tab = g.active
        guard tab.entries.indices.contains(index) else { return }
        let entry = tab.entries[index]
        guard entry.isDirectory, !entry.isParentLink else { return }
        activeSide = side
        tab.moveCursor(to: index)
        guard Dialogs.confirm(title: "Otevřít adresář jako záložku?", message: "Adresář „\(entry.name)“ se otevře v nové záložce.", ok: "Otevřít záložku") else { return }
        g.newTab(at: entry.url)
    }
}
