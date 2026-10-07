import AppKit
import SwiftUI
import TCCore
import UniformTypeIdentifiers

final class KeyTableView: NSTableView {
    var keyHandler: ((NSEvent) -> Bool)?
    var focusHandler: (() -> Void)?
    /// PageUp/PageDown/Home/End: posun kurzoru (o `delta` řádků, nebo na začátek či konec při `toEnd`).
    var cursorMove: ((_ delta: Int, _ toEnd: Bool) -> Void)?
    /// Dlouhé podržení pravého tlačítka nad řádkem (index řádku).
    var rightLongPress: ((Int) -> Void)?
    private var pressTimer: Timer?

    override func rightMouseDown(with event: NSEvent) {
        pressTimer?.invalidate()
        let r = row(at: convert(event.locationInWindow, from: nil))
        guard r >= 0 else { return }
        pressTimer = Timer.scheduledTimer(withTimeInterval: RightLongPress.delay, repeats: false) { [weak self] _ in self?.rightLongPress?(r) }
    }

    override func rightMouseUp(with event: NSEvent) { pressTimer?.invalidate(); pressTimer = nil }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            let page = max(1, Int(visibleRect.height / max(1, rowHeight + intercellSpacing.height)) - 1)
            switch event.keyCode {
            case 116: cursorMove?(-page, false); return        // PageUp
            case 121: cursorMove?(page, false); return         // PageDown
            case 115: cursorMove?(-1, true); return            // Home
            case 119: cursorMove?(1, true); return             // End
            default: break
            }
        }
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

/// Vzhled seznamu souborů (z nastavení).
struct PanelStyle: Equatable {
    var fontSize: Double = 12
    var rowHeight: Double = 20
    var colorRules: [ColorRule] = []
}

struct FileTableView: NSViewRepresentable {
    var style = PanelStyle()
    let tab: PanelTab
    let revision: Int
    let isActive: Bool
    let onFocus: () -> Void
    let onKey: (NSEvent) -> Bool
    let onOpen: () -> Void
    var onRightLongPress: (Int) -> Void = { _ in }
    var onDrop: ([URL], URL, Bool) -> Void = { _, _, _ in }
    var onRename: (FileEntry, String) -> Void = { _, _ in }

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

        c.installColumns(on: table, tab.columns)

        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.dataSource = c
        table.delegate = c
        table.target = c
        table.doubleAction = #selector(Coordinator.doubleClicked)
        table.keyHandler = { [weak c] e in c?.parent.onKey(e) ?? false }
        table.focusHandler = { [weak c] in c?.parent.onFocus() }
        table.rightLongPress = { [weak c] row in c?.parent.onRightLongPress(row) }
        table.cursorMove = { [weak c] delta, toEnd in
            guard let tab = c?.parent.tab else { return }
            tab.moveCursor(to: toEnd ? (delta < 0 ? 0 : tab.entries.count - 1) : tab.cursor + delta)
        }
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
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var parent: FileTableView
        weak var table: KeyTableView?
        private var lastRevision = -1
        private var lastActive = false
        private var syncing = false
        private var lastStyle = PanelStyle()
        private var installedColumns: [PanelColumn] = []

        private var renamingRow: Int?

        init(_ p: FileTableView) {
            parent = p
            super.init()
            NotificationCenter.default.addObserver(forName: .macTCBeginRename, object: nil, queue: .main) { [weak self] n in
                MainActor.assumeIsolated {
                    guard let self, n.object as AnyObject === self.parent.tab else { return }
                    self.beginRename()
                }
            }
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        /// Přejmenování přímo v seznamu: buňka s názvem se stane editovatelnou (vybere se název bez přípony).
        func beginRename() {
            guard let table, let col = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" }) else { return }
            let row = parent.tab.cursor
            guard parent.tab.entries.indices.contains(row), !parent.tab.entries[row].isParentLink,
                  let cell = table.view(atColumn: col, row: row, makeIfNecessary: true) as? FileCell else { return }
            renamingRow = row
            cell.label.isEditable = true
            cell.label.delegate = self
            table.window?.makeFirstResponder(cell.label)
            let e = parent.tab.entries[row]
            let showsExt = parent.tab.columns.contains(.ext)
            let len = showsExt ? cell.label.stringValue.utf16.count : (e.isDirectory ? e.name.utf16.count : e.baseName.utf16.count)
            (cell.label.currentEditor() as? NSTextView)?.setSelectedRange(NSRange(location: 0, length: len))
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, let row = renamingRow else { return }
            renamingRow = nil
            field.isEditable = false
            let tab = parent.tab
            guard tab.entries.indices.contains(row) else { return }
            let e = tab.entries[row]
            let cancelled = (obj.userInfo?["NSTextMovement"] as? Int) == NSTextMovement.cancel.rawValue
            let typed = field.stringValue
            let showsExt = tab.columns.contains(.ext)
            let full = showsExt && !e.ext.isEmpty && !e.isDirectory ? typed + "." + e.ext : typed
            if cancelled || full == e.name { table?.reloadData(); return }
            parent.onRename(e, full)
        }

        func sync() {
            guard let table else { return }
            let tab = parent.tab
            syncing = true
            let styleChanged = parent.style != lastStyle
            if styleChanged { lastStyle = parent.style; table.rowHeight = CGFloat(parent.style.rowHeight); lastRevision = -1 }
            if installedColumns != tab.columns { installColumns(on: table, tab.columns); lastRevision = -1 }
            if parent.revision != lastRevision {
                lastRevision = parent.revision
                table.reloadData()
                updateHeaders()
                fillPluginColumns()
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

        /// Hodnoty sloupců z pluginů se zjišťují na pozadí; po doplnění se tabulka překreslí.
        private func fillPluginColumns() {
            let cols = installedColumns.filter(\.isPlugin)
            guard !cols.isEmpty else { return }
            let entries = parent.tab.entries
            Task.detached { [weak self] in
                let added = ContentColumnRegistry.shared.fill(cols, for: entries)
                if added { await MainActor.run { self?.table?.reloadData() } }
            }
        }

        func installColumns(on table: NSTableView, _ columns: [PanelColumn]) {
            for c in table.tableColumns { table.removeTableColumn(c) }
            let list = columns.isEmpty ? PanelColumn.standard : columns
            for pc in list {
                let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(pc.rawValue))
                col.title = pc.title
                col.width = CGFloat(pc.defaultWidth)
                col.minWidth = pc == .name ? 100 : 40
                col.resizingMask = pc == .name ? .autoresizingMask : .userResizingMask
                table.addTableColumn(col)
            }
            installedColumns = columns
            updateHeaders()
        }

        private func updateHeaders() {
            guard let table else { return }
            let s = parent.tab.sort
            let keys: [PanelColumn: SortKey] = [.name: .name, .ext: .ext, .size: .size, .date: .date]
            for col in table.tableColumns {
                let pc = PanelColumn(rawValue: col.identifier.rawValue)
                var t = pc.title
                if keys[pc] == s.key { t += s.ascending ? " ▲" : " ▼" }
                col.title = t
            }
        }

        // MARK: DataSource / Delegate

        static let monoColumns: Set<String> = ["size", "date", "attr", "created", "accessed"]

        func numberOfRows(in tableView: NSTableView) -> Int { parent.tab.entries.count }

        func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
            let tab = parent.tab
            guard let col, tab.entries.indices.contains(row) else { return nil }
            let e = tab.entries[row]
            let id = col.identifier
            let cell = (tv.makeView(withIdentifier: id, owner: nil) as? FileCell) ?? FileCell(
                identifier: id, withIcon: id.rawValue == "name",
                alignment: (id.rawValue == "size" || ContentColumnRegistry.shared.info(for: PanelColumn(rawValue: id.rawValue))?.rightAligned == true) ? .right : .left,
                mono: Self.monoColumns.contains(id.rawValue))
            let isMarked = tab.marked.contains(e.url)
            let text: String
            switch id.rawValue {
            case "name": text = e.isParentLink ? ".." : (tab.columns.contains(.ext) ? e.baseName : e.name); cell.icon.image = IconCache.icon(for: e)
            case "ext": text = e.ext
            case "size": text = Fmt.size(of: e, dirSize: tab.dirSizes[e.url])
            case "date": text = e.isParentLink ? "" : Fmt.date(e.modified)
            case "created": text = e.isParentLink ? "" : Fmt.date(e.created)
            case "accessed": text = e.isParentLink ? "" : Fmt.date(e.accessed)
            case "kind": text = e.isParentLink ? "" : Fmt.kind(of: e)
            case "owner": text = e.isParentLink ? "" : Fmt.owner(e.ownerID)
            case "attr": text = e.isParentLink ? "" : e.permissionString
            default: text = e.isDirectory || e.isParentLink ? "" : (ContentColumnRegistry.shared.cached(PanelColumn(rawValue: id.rawValue), e) ?? "…")
            }
            cell.label.stringValue = text
            var color: NSColor = e.isHidden ? .secondaryLabelColor : .labelColor
            if !e.isHidden, let hex = ColorRule.color(for: e.name, isDirectory: e.isDirectory, rules: parent.style.colorRules), let c = NSColor(hex: hex) { color = c }
            cell.label.textColor = isMarked ? .systemRed : color
            let fs = CGFloat(parent.style.fontSize)
            let base: NSFont = Self.monoColumns.contains(id.rawValue) ? .monospacedDigitSystemFont(ofSize: fs, weight: .regular) : .systemFont(ofSize: fs)
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

        // MARK: Drag & drop

        func tableView(_ tableView: NSTableView, writeRowsWith rowIndexes: IndexSet, to pboard: NSPasteboard) -> Bool {
            let tab = parent.tab
            guard !tab.isVirtual, let row = rowIndexes.first, tab.entries.indices.contains(row), !tab.entries[row].isParentLink else { return false }
            let dragged = tab.entries[row]
            let urls = tab.marked.contains(dragged.url) ? tab.entries.filter { tab.marked.contains($0.url) }.map(\.url) : [dragged.url]
            pboard.clearContents()
            return pboard.writeObjects(urls.map { $0 as NSURL })
        }

        private func dropTarget(row: Int, op: NSTableView.DropOperation) -> URL {
            let tab = parent.tab
            if op == .on, tab.entries.indices.contains(row), tab.entries[row].isDirectory { return tab.entries[row].url }
            return tab.path
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                       proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
            let tab = parent.tab
            if tab.isVirtual { return [] }
            if op == .on, tab.entries.indices.contains(row), tab.entries[row].isDirectory, !tab.entries[row].isParentLink {
                // zůstává na řádku adresáře
            } else {
                tableView.setDropRow(-1, dropOperation: .on)
            }
            let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            guard let first = urls.first else { return [] }
            let dest = dropTarget(row: tableView.selectedRow == -1 ? -1 : row, op: op)
            if urls.contains(where: { $0.deletingLastPathComponent().standardizedFileURL == dest.standardizedFileURL }) && op != .on { return [] }
            return AppModel.dropIsMove(source: first, destination: dest, option: NSEvent.modifierFlags.contains(.option)) ? .move : .copy
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                       dropOperation op: NSTableView.DropOperation) -> Bool {
            let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            guard let first = urls.first else { return false }
            let dest = dropTarget(row: row, op: op)
            parent.onDrop(urls, dest, AppModel.dropIsMove(source: first, destination: dest, option: NSEvent.modifierFlags.contains(.option)))
            return true
        }

        @objc func doubleClicked() {
            guard let table, table.clickedRow >= 0 else { return }
            parent.tab.cursor = table.clickedRow
            parent.onOpen()
        }
    }
}
