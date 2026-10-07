import AppKit
import TCCore

@MainActor
final class SyncWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var current: SyncWindow?

    static func show(left: URL, right: URL, jobs: JobManager, onDone: @escaping () -> Void) {
        current?.window.close()
        let w = SyncWindow(left: left, right: right, jobs: jobs, onDone: onDone)
        current = w
        w.window.makeKeyAndOrderFront(nil)
        w.compare()
    }

    private let jobs: JobManager
    private let onDone: () -> Void
    private let window: NSWindow
    private let leftField = NSTextField(), rightField = NSTextField()
    private let recursive = NSButton(checkboxWithTitle: "Podadresáře", target: nil, action: nil)
    private let content = NSButton(checkboxWithTitle: "Porovnat obsah", target: nil, action: nil)
    private let ignoreDate = NSButton(checkboxWithTitle: "Ignorovat datum", target: nil, action: nil)
    private let hidden = NSButton(checkboxWithTitle: "Skryté", target: nil, action: nil)
    private let ignoreMask = NSTextField()
    private let direction = NSPopUpButton(frame: .zero, pullsDown: false)
    private let showSame = NSButton(checkboxWithTitle: "Zobrazit shodné", target: nil, action: nil)
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let syncButton = NSButton(title: "Synchronizovat", target: nil, action: nil)
    private var plan: [PlannedSync] = []
    private var visible: [Int] = []
    private var comparing = false

    private static let directions: [(SyncDirection, String)] = [
        (.bothNewer, "Obousměrně (novější vyhrává)"), (.leftToRight, "Zleva doprava (aktualizovat)"),
        (.rightToLeft, "Zprava doleva (aktualizovat)"), (.mirrorLeftToRight, "Zrcadlit zleva doprava (smazat nadbytečné)"),
        (.mirrorRightToLeft, "Zrcadlit zprava doleva (smazat nadbytečné)"),
    ]

    private init(left: URL, right: URL, jobs: JobManager, onDone: @escaping () -> Void) {
        self.jobs = jobs; self.onDone = onDone
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Synchronizace adresářů"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        leftField.stringValue = left.path; rightField.stringValue = right.path
        recursive.state = .on
        direction.addItems(withTitles: Self.directions.map(\.1))
        direction.target = self; direction.action = #selector(directionChanged)
        showSame.target = self; showSame.action = #selector(filterChanged)
        ignoreMask.placeholderString = "ignorovat masky (např. *.tmp;.DS_Store)"
        func row(_ label: String, _ views: [NSView]) -> NSStackView {
            let l = NSTextField(labelWithString: label); l.alignment = .right
            l.widthAnchor.constraint(equalToConstant: 110).isActive = true
            let s = NSStackView(views: [l] + views); s.spacing = 8; return s
        }
        let compareButton = NSButton(title: "Porovnat", target: self, action: #selector(compare))
        let form = NSStackView(views: [
            row("Vlevo:", [leftField]), row("Vpravo:", [rightField]),
            row("", [recursive, content, ignoreDate, hidden, ignoreMask, compareButton]),
            row("Směr:", [direction, showSame]),
        ])
        form.orientation = .vertical; form.alignment = .leading; form.spacing = 6

        for (id, title, w) in [("name", "Soubor", 380.0), ("left", "Vlevo", 230.0), ("action", "Akce", 60.0), ("right", "Vpravo", 230.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = w; table.addTableColumn(c)
        }
        table.dataSource = self; table.delegate = self; table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.target = self; table.doubleAction = #selector(cycleAction)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true

        let toRight = NSButton(title: "→", target: self, action: #selector(setToRight))
        let toLeft = NSButton(title: "←", target: self, action: #selector(setToLeft))
        let skip = NSButton(title: "Přeskočit", target: self, action: #selector(setSkip))
        syncButton.target = self; syncButton.action = #selector(runSync)
        let bottom = NSStackView(views: [status, NSView(), NSTextField(labelWithString: "Vybrané řádky:"), toRight, toLeft, skip, syncButton])
        bottom.spacing = 8

        let c = window.contentView!
        for v in [form, scroll, bottom] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; c.addSubview(v) }
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: c.topAnchor, constant: 14),
            form.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14), form.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: c.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            bottom.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            bottom.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14), bottom.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),
            bottom.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -12),
        ])
    }

    private var leftURL: URL { URL(fileURLWithPath: (leftField.stringValue as NSString).expandingTildeInPath) }
    private var rightURL: URL { URL(fileURLWithPath: (rightField.stringValue as NSString).expandingTildeInPath) }
    private var currentDirection: SyncDirection { Self.directions[max(0, direction.indexOfSelectedItem)].0 }

    // MARK: Porovnání

    @objc private func compare() {
        guard !comparing else { return }
        var isDir: ObjCBool = false
        for u in [leftURL, rightURL] {
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else {
                Dialogs.error("Neplatný adresář", u.path); return
            }
        }
        var o = SyncOptions()
        o.recursive = recursive.state == .on; o.compareContent = content.state == .on
        o.ignoreDate = ignoreDate.state == .on; o.includeHidden = hidden.state == .on; o.ignoreMasks = ignoreMask.stringValue
        let l = leftURL, r = rightURL, dir = currentDirection
        comparing = true
        status.stringValue = "Porovnávám…"
        Task {
            let items = await Task.detached { DirectoryComparer.compare(left: l, right: r, options: o) }.value
            self.plan = SyncPlanner.plan(items, direction: dir)
            self.comparing = false
            self.applyFilter()
        }
    }

    @objc private func directionChanged() { plan = SyncPlanner.plan(plan.map(\.item), direction: currentDirection); applyFilter() }
    @objc private func filterChanged() { applyFilter() }

    private func applyFilter() {
        visible = plan.indices.filter { showSame.state == .on || plan[$0].item.state != .same }
        table.reloadData()
        updateStatus()
    }

    private func updateStatus() {
        let actions = plan.filter { $0.action != .none }
        let different = plan.filter { $0.item.state != .same }.count
        status.stringValue = "Rozdílů: \(different) · k provedení: \(actions.count) (kopií: \(actions.filter { $0.action == .copyToLeft || $0.action == .copyToRight }.count), smazání: \(actions.filter { $0.action == .deleteLeft || $0.action == .deleteRight }.count))"
        syncButton.isEnabled = !actions.isEmpty
    }

    // MARK: Akce

    private func setAction(_ a: SyncAction, valid: (SyncItem) -> Bool) {
        for row in table.selectedRowIndexes where visible.indices.contains(row) {
            let i = visible[row]
            if valid(plan[i].item) { plan[i].action = a }
        }
        table.reloadData(); updateStatus()
    }

    @objc private func setToRight() { setAction(.copyToRight) { $0.left != nil } }
    @objc private func setToLeft() { setAction(.copyToLeft) { $0.right != nil } }
    @objc private func setSkip() { setAction(.none) { _ in true } }

    @objc private func cycleAction() {
        let row = table.clickedRow
        guard visible.indices.contains(row) else { return }
        let i = visible[row]
        let item = plan[i].item
        var options: [SyncAction] = [.none]
        if item.left != nil { options.append(.copyToRight) }
        if item.right != nil { options.append(.copyToLeft) }
        if item.right != nil && item.left == nil { options.append(.deleteRight) }
        if item.left != nil && item.right == nil { options.append(.deleteLeft) }
        let next = options[((options.firstIndex(of: plan[i].action) ?? -1) + 1) % options.count]
        plan[i].action = next
        table.reloadData(); updateStatus()
    }

    @objc private func runSync() {
        let todo = plan.filter { $0.action != .none }
        guard !todo.isEmpty else { return }
        let deletes = todo.filter { $0.action == .deleteLeft || $0.action == .deleteRight }.count
        let msg = "Kopírování: \(todo.count - deletes) souborů" + (deletes > 0 ? ", do koše: \(deletes) souborů" : "")
        guard Dialogs.confirm(title: "Provést synchronizaci?", message: msg, ok: "Synchronizovat", destructive: deletes > 0) else { return }
        let l = leftURL, r = rightURL
        jobs.enqueue(title: "Synchronizace \(l.lastPathComponent) ↔ \(r.lastPathComponent)", work: { control, progress in
            SyncPlanner.execute(todo, left: l, right: r, control: control, progress: progress)
        }, onFinish: { [weak self] report in
            self?.onDone()
            if !report.failures.isEmpty {
                Dialogs.error("Některé položky se nepodařilo synchronizovat",
                              report.failures.prefix(10).map { "\($0.url.lastPathComponent): \($0.message)" }.joined(separator: "\n"))
            }
            if self?.window.isVisible == true { self?.compare() }
        })
    }

    // MARK: Tabulka

    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let col, visible.indices.contains(row) else { return nil }
        let p = plan[visible[row]], item = p.item
        let cell = (tv.makeView(withIdentifier: col.identifier, owner: nil) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: ""); f.identifier = col.identifier; f.lineBreakMode = .byTruncatingMiddle; return f
        }()
        func describe(_ e: FileEntry?) -> String { e.map { "\(Fmt.bytes($0.size))  \(Fmt.date($0.modified))" } ?? "—" }
        cell.alignment = .left
        switch col.identifier.rawValue {
        case "name": cell.stringValue = item.relativePath; cell.textColor = .labelColor
        case "left":
            cell.stringValue = describe(item.left)
            cell.textColor = item.state == .onlyLeft || item.state == .leftNewer ? .systemBlue : .secondaryLabelColor
        case "right":
            cell.stringValue = describe(item.right)
            cell.textColor = item.state == .onlyRight || item.state == .rightNewer ? .systemBlue : .secondaryLabelColor
        default:
            cell.alignment = .center
            switch p.action {
            case .none: cell.stringValue = item.state == .same ? "=" : "≠"; cell.textColor = .secondaryLabelColor
            case .copyToRight: cell.stringValue = "→"; cell.textColor = .systemGreen
            case .copyToLeft: cell.stringValue = "←"; cell.textColor = .systemGreen
            case .deleteLeft, .deleteRight: cell.stringValue = "✕"; cell.textColor = .systemRed
            }
        }
        return cell
    }

    func windowWillClose(_ notification: Notification) { Self.current = nil }
}
