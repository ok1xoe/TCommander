import AppKit
import SwiftUI
import TCCore
import UniformTypeIdentifiers

final class KeyTableView: NSTableView {
    var keyHandler: ((NSEvent) -> Bool)?
    var focusHandler: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        focusHandler?()
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        focusHandler?()
        return super.becomeFirstResponder()
    }
}

final class FileCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let icon = NSImageView()

    init(identifier: NSUserInterfaceItemIdentifier, withIcon: Bool, alignment: NSTextAlignment, mono: Bool) {
        super.init(frame: .zero)
        self.identifier = identifier
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingMiddle
        label.alignment = alignment
        label.font = mono ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 12)
        addSubview(label)
        textField = label
        if withIcon {
            icon.translatesAutoresizingMaskIntoConstraints = false
            addSubview(icon)
            imageView = icon
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16), icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
            ])
        } else {
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3).isActive = true
        }
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for e: FileEntry) -> NSImage {
        if e.isParentLink {
            return NSImage(systemSymbolName: "arrow.up.left", accessibilityDescription: nil) ?? NSImage()
        }
        let ws = NSWorkspace.shared
        if e.isDirectory && e.url.pathExtension == "app" { return ws.icon(forFile: e.url.path) }
        let key = e.isDirectory ? "\u{0}dir" : e.ext.lowercased()
        if let i = cache[key] { return i }
        let type: UTType = e.isDirectory ? .folder : (UTType(filenameExtension: e.ext) ?? .data)
        let img = ws.icon(for: type)
        cache[key] = img
        return img
    }
}

struct FileTableView: NSViewRepresentable {
    let tab: PanelTab
    let revision: Int
    let isActive: Bool
    let onFocus: () -> Void
    let onKey: (NSEvent) -> Bool
    let onOpen: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let table = KeyTableView()
        table.style = .plain
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.allowsColumnReordering = false
        table.rowHeight = 20
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        func add(_ id: String, _ title: String, _ width: CGFloat, min: CGFloat) {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = min
            if id == "name" { col.resizingMask = .autoresizingMask } else { col.resizingMask = .userResizingMask }
            table.addTableColumn(col)
        }
        add("name", "Název", 140, min: 100)
        add("ext", "Přípona", 55, min: 40)
        add("size", "Velikost", 85, min: 70)
        add("date", "Datum", 125, min: 110)
        add("attr", "Atr", 80, min: 70)

        table.dataSource = c
        table.delegate = c
        table.target = c
        table.doubleAction = #selector(Coordinator.doubleClicked)
        table.keyHandler = { [weak c] e in c?.parent.onKey(e) ?? false }
        table.focusHandler = { [weak c] in c?.parent.onFocus() }
        c.table = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileTableView
        weak var table: KeyTableView?
        private var lastRevision = -1
        private var lastActive = false
        private var syncing = false

        init(_ p: FileTableView) { parent = p }

        func sync() {
            guard let table else { return }
            let tab = parent.tab
            syncing = true
            if parent.revision != lastRevision {
                lastRevision = parent.revision
                table.reloadData()
                updateHeaders()
            }
            if table.selectedRow != tab.cursor, tab.entries.indices.contains(tab.cursor) {
                table.selectRowIndexes(IndexSet(integer: tab.cursor), byExtendingSelection: false)
                table.scrollRowToVisible(tab.cursor)
            }
            syncing = false
            if parent.isActive && !lastActive, let w = table.window, w.firstResponder !== table, !(w.firstResponder is NSText) {
                DispatchQueue.main.async { w.makeFirstResponder(table) }
            }
            lastActive = parent.isActive
        }

        private func updateHeaders() {
            guard let table else { return }
            let s = parent.tab.sort
            let keys: [String: SortKey] = ["name": .name, "ext": .ext, "size": .size, "date": .date]
            let titles = ["name": "Název", "ext": "Přípona", "size": "Velikost", "date": "Datum", "attr": "Atr"]
            for col in table.tableColumns {
                let id = col.identifier.rawValue
                var t = titles[id] ?? id
                if keys[id] == s.key { t += s.ascending ? " ▲" : " ▼" }
                col.title = t
            }
        }

        // MARK: DataSource / Delegate

        func numberOfRows(in tableView: NSTableView) -> Int { parent.tab.entries.count }

        func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
            let tab = parent.tab
            guard let col, tab.entries.indices.contains(row) else { return nil }
            let e = tab.entries[row]
            let id = col.identifier
            let cell = (tv.makeView(withIdentifier: id, owner: nil) as? FileCell) ?? FileCell(
                identifier: id, withIcon: id.rawValue == "name",
                alignment: id.rawValue == "size" ? .right : .left,
                mono: ["size", "date", "attr"].contains(id.rawValue))
            let isMarked = tab.marked.contains(e.url)
            let text: String
            switch id.rawValue {
            case "name": text = e.isParentLink ? ".." : e.baseName; cell.icon.image = IconCache.icon(for: e)
            case "ext": text = e.ext
            case "size": text = Fmt.size(of: e, dirSize: tab.dirSizes[e.url])
            case "date": text = e.isParentLink ? "" : Fmt.date(e.modified)
            default: text = e.isParentLink ? "" : e.permissionString
            }
            cell.label.stringValue = text
            cell.label.textColor = isMarked ? .systemRed : (e.isHidden ? .secondaryLabelColor : .labelColor)
            let base = cell.label.font ?? .systemFont(ofSize: 12)
            cell.label.font = NSFontManager.shared.convert(base, toHaveTrait: isMarked ? .boldFontMask : .unboldFontMask)
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !syncing, let table, table.selectedRow >= 0 else { return }
            parent.tab.cursor = table.selectedRow
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            let map: [String: SortKey] = ["name": .name, "ext": .ext, "size": .size, "date": .date]
            guard let key = map[tableColumn.identifier.rawValue] else { return }
            let tab = parent.tab
            tab.sort = tab.sort.key == key ? SortDescriptor(key: key, ascending: !tab.sort.ascending) : SortDescriptor(key: key)
        }

        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            parent.tab.entries.indices.contains(row) ? parent.tab.entries[row].name : nil
        }

        @objc func doubleClicked() {
            guard let table, table.clickedRow >= 0 else { return }
            parent.tab.cursor = table.clickedRow
            parent.onOpen()
        }
    }
}
