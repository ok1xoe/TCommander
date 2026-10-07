import AppKit
import TCCore

@MainActor
final class DuplicatesWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var current: DuplicatesWindow?

    static func show(root: URL, goTo: @escaping (URL) -> Void, onChange: @escaping () -> Void) {
        current?.window.close()
        let w = DuplicatesWindow(root: root, goTo: goTo, onChange: onChange)
        current = w
        w.window.makeKeyAndOrderFront(nil)
        w.scan()
    }

    private struct Row { let group: Int; let url: URL; let size: Int64; let first: Bool }

    private let root: URL
    private let goTo: (URL) -> Void
    private let onChange: () -> Void
    private let window: NSWindow
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private var rows: [Row] = []

    private init(root: URL, goTo: @escaping (URL) -> Void, onChange: @escaping () -> Void) {
        self.root = root; self.goTo = goTo; self.onChange = onChange
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Duplicitní soubory v \(root.path)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        for (id, title, w) in [("group", "Skupina", 70.0), ("name", "Název", 250.0), ("dir", "Adresář", 400.0), ("size", "Velikost", 100.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = w; table.addTableColumn(c)
        }
        table.dataSource = self; table.delegate = self; table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.target = self; table.doubleAction = #selector(goToSelected)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        let extras = NSButton(title: "Vybrat nadbytečné kopie", target: self, action: #selector(selectExtras))
        let go = NSButton(title: "Přejít na soubor", target: self, action: #selector(goToSelected))
        let trash = NSButton(title: "Vybrané do koše", target: self, action: #selector(trashSelected))
        let bottom = NSStackView(views: [status, NSView(), extras, go, trash]); bottom.spacing = 8
        let c = window.contentView!
        for v in [scroll, bottom] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; c.addSubview(v) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: c.topAnchor), scroll.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            bottom.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            bottom.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14), bottom.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),
            bottom.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -12),
        ])
    }

    func scan() {
        status.stringValue = "Hledám duplicity…"
        let root = self.root
        Task {
            let groups = await Task.detached { DuplicateFinder.find(in: root) }.value
            self.rows = groups.enumerated().flatMap { gi, g in g.files.enumerated().map { Row(group: gi + 1, url: $1, size: g.size, first: $0 == 0) } }
            let wasted = groups.reduce(Int64(0)) { $0 + $1.size * Int64($1.files.count - 1) }
            self.status.stringValue = groups.isEmpty ? "Žádné duplicity" : "\(groups.count) skupin, zbytečně zabraných \(Fmt.human(wasted))"
            self.table.reloadData()
        }
    }

    @objc private func selectExtras() {
        table.selectRowIndexes(IndexSet(rows.indices.filter { !rows[$0].first }), byExtendingSelection: false)
    }

    @objc private func goToSelected() {
        let r = table.clickedRow >= 0 ? table.clickedRow : table.selectedRow
        if rows.indices.contains(r) { goTo(rows[r].url) }
    }

    @objc private func trashSelected() {
        let urls = table.selectedRowIndexes.map { rows[$0].url }
        guard !urls.isEmpty, Dialogs.confirm(title: "Přesunout do koše?", message: "\(urls.count) souborů", ok: "Do koše", destructive: true) else { return }
        let rep = FileOperations().delete(urls, toTrash: true)
        if !rep.failures.isEmpty { Dialogs.error("Některé soubory se nepodařilo smazat", rep.failures.prefix(5).map(\.message).joined(separator: "\n")) }
        onChange()
        scan()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let col, rows.indices.contains(row) else { return nil }
        let r = rows[row]
        let cell = (tv.makeView(withIdentifier: col.identifier, owner: nil) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: ""); f.identifier = col.identifier; f.lineBreakMode = .byTruncatingMiddle; return f
        }()
        cell.alignment = .left
        switch col.identifier.rawValue {
        case "group": cell.stringValue = r.first ? "#\(r.group)" : ""
        case "name": cell.stringValue = r.url.lastPathComponent
        case "dir": cell.stringValue = r.url.deletingLastPathComponent().path
        default: cell.stringValue = Fmt.bytes(r.size); cell.alignment = .right
        }
        return cell
    }

    func windowWillClose(_ notification: Notification) { Self.current = nil }
}
