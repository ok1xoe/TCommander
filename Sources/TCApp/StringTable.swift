import AppKit

/// Jednoduchá editovatelná tabulka textových buněk s tlačítky přidat/odebrat/posunout.
@MainActor
final class StringTable: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    struct Column { let title: String; let width: CGFloat; var editable = true }

    let view = NSView()
    private let table = NSTableView()
    private let columns: [Column]
    private(set) var rows: [[String]]
    private let newRow: () -> [String]
    private let canAddRemove: Bool
    var onChange: (([[String]]) -> Void)?
    /// Vrací false, pokud je změna buňky neplatná (hodnota se vrátí).
    var validate: ((_ row: Int, _ column: Int, _ value: String) -> Bool)?

    init(columns: [Column], rows: [[String]], canAddRemove: Bool = true, newRow: @escaping () -> [String] = { [] }) {
        self.columns = columns; self.rows = rows; self.newRow = newRow; self.canAddRemove = canAddRemove
        super.init()
        for (i, c) in columns.enumerated() {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(i)"))
            col.title = c.title; col.width = c.width; col.minWidth = 40
            table.addTableColumn(col)
        }
        table.dataSource = self; table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        var bottomAnchor = view.bottomAnchor
        var constraints = [
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ]
        if canAddRemove {
            let add = NSButton(title: "+", target: self, action: #selector(addRow))
            let del = NSButton(title: "−", target: self, action: #selector(removeRow))
            let up = NSButton(title: "↑", target: self, action: #selector(moveUp))
            let down = NSButton(title: "↓", target: self, action: #selector(moveDown))
            let bar = NSStackView(views: [add, del, up, down, NSView()]); bar.spacing = 6
            bar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bar)
            constraints += [bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor), scroll.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -6)]
            bottomAnchor = bar.topAnchor
        } else {
            constraints.append(scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor))
        }
        _ = bottomAnchor
        NSLayoutConstraint.activate(constraints)
    }

    func setRows(_ r: [[String]]) { rows = r; table.reloadData() }

    private func changed() { onChange?(rows) }

    @objc private func addRow() {
        rows.append(newRow()); table.reloadData(); changed()
        table.selectRowIndexes(IndexSet(integer: rows.count - 1), byExtendingSelection: false)
        table.scrollRowToVisible(rows.count - 1)
    }

    @objc private func removeRow() {
        let r = table.selectedRow
        guard rows.indices.contains(r) else { return }
        rows.remove(at: r); table.reloadData(); changed()
    }

    @objc private func moveUp() { move(-1) }
    @objc private func moveDown() { move(1) }

    private func move(_ d: Int) {
        let r = table.selectedRow, t = r + d
        guard rows.indices.contains(r), rows.indices.contains(t) else { return }
        rows.swapAt(r, t); table.reloadData(); table.selectRowIndexes(IndexSet(integer: t), byExtendingSelection: false); changed()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let col, let ci = Int(col.identifier.rawValue.dropFirst()), rows.indices.contains(row), ci < columns.count else { return nil }
        let id = col.identifier
        let field = (tv.makeView(withIdentifier: id, owner: nil) as? NSTextField) ?? {
            let f = NSTextField(); f.identifier = id; f.isBordered = false; f.drawsBackground = false
            f.lineBreakMode = .byTruncatingTail; f.delegate = self; return f
        }()
        field.isEditable = columns[ci].editable
        field.textColor = columns[ci].editable ? .labelColor : .secondaryLabelColor
        field.stringValue = ci < rows[row].count ? rows[row][ci] : ""
        field.tag = row * 100 + ci
        return field
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let f = obj.object as? NSTextField else { return }
        let row = f.tag / 100, ci = f.tag % 100
        guard rows.indices.contains(row), ci < columns.count else { return }
        while rows[row].count < columns.count { rows[row].append("") }
        if let validate, !validate(row, ci, f.stringValue) { f.stringValue = rows[row][ci]; return }
        guard rows[row][ci] != f.stringValue else { return }
        rows[row][ci] = f.stringValue
        changed()
    }
}
