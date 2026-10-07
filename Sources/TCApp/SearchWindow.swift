import AppKit
import TCCore

/// Vlákny bezpečný sběrač nálezů; hlavní vlákno ho periodicky vyprazdňuje.
private final class HitCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var hits: [SearchHit] = []
    private var cancelled = false
    private(set) var finished = false
    private(set) var scanned = 0

    func add(_ h: SearchHit) { lock.lock(); hits.append(h); lock.unlock() }
    func drain() -> [SearchHit] { lock.lock(); defer { lock.unlock() }; let r = hits; hits = []; return r }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func finish(scanned: Int) { lock.lock(); self.scanned = scanned; finished = true; lock.unlock() }
    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
}

@MainActor
final class SearchWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var current: SearchWindow?

    static func show(root: URL, goTo: @escaping (URL, String?) -> Void) {
        if let w = current { w.root.stringValue = root.path; w.window.makeKeyAndOrderFront(nil); return }
        let w = SearchWindow(root: root, goTo: goTo)
        current = w
        w.window.makeKeyAndOrderFront(nil)
    }

    private let window: NSWindow
    private let goTo: (URL, String?) -> Void
    private let masks = NSTextField(string: "*")
    private let root = NSTextField()
    private let text = NSTextField()
    private let subdirs = NSButton(checkboxWithTitle: "Podadresáře", target: nil, action: nil)
    private let hidden = NSButton(checkboxWithTitle: "Skryté soubory", target: nil, action: nil)
    private let archives = NSButton(checkboxWithTitle: "V archivech", target: nil, action: nil)
    private let caseSens = NSButton(checkboxWithTitle: "Rozlišovat velikost písmen", target: nil, action: nil)
    private let regex = NSButton(checkboxWithTitle: "Regulární výraz", target: nil, action: nil)
    private let minKB = NSTextField(), maxKB = NSTextField(), days = NSTextField()
    private let searchButton = NSButton(title: "Hledat", target: nil, action: nil)
    private let status = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private var results: [SearchHit] = []
    private var collector: HitCollector?
    private var timer: Timer?

    private init(root rootURL: URL, goTo: @escaping (URL, String?) -> Void) {
        self.goTo = goTo
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Hledat soubory"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        root.stringValue = rootURL.path
        subdirs.state = .on
        text.placeholderString = "text v souboru (nepovinné)"
        for f in [minKB, maxKB, days] { f.placeholderString = "—"; f.alignment = .right }

        func row(_ label: String, _ views: [NSView]) -> NSStackView {
            let l = NSTextField(labelWithString: label); l.alignment = .right
            l.widthAnchor.constraint(equalToConstant: 130).isActive = true
            let s = NSStackView(views: [l] + views); s.spacing = 8; return s
        }
        for f in [masks, root, text] { f.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        for f in [minKB, maxKB, days] { f.widthAnchor.constraint(equalToConstant: 70).isActive = true }
        searchButton.target = self; searchButton.action = #selector(toggleSearch); searchButton.keyEquivalent = "\r"
        let form = NSStackView(views: [
            row("Hledat soubory:", [masks]),
            row("V adresáři:", [root]),
            row("Obsahující text:", [text]),
            row("", [subdirs, hidden, archives, caseSens, regex]),
            row("Velikost (KB):", [minKB, NSTextField(labelWithString: "až"), maxKB,
                                   NSTextField(labelWithString: "   změněno za posledních"), days, NSTextField(labelWithString: "dní")]),
        ])
        form.orientation = .vertical; form.alignment = .leading; form.spacing = 6

        for (id, title, w) in [("name", "Název", 200.0), ("dir", "Adresář", 330.0), ("size", "Velikost", 80.0), ("match", "Nalezeno", 230.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = w; table.addTableColumn(c)
        }
        table.dataSource = self; table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.target = self; table.doubleAction = #selector(openSelected)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let goButton = NSButton(title: "Přejít na soubor", target: self, action: #selector(openSelected))
        let viewButton = NSButton(title: "Zobrazit (F3)", target: self, action: #selector(viewSelected))
        let bottom = NSStackView(views: [status, NSView(), viewButton, goButton, searchButton]); bottom.spacing = 8

        let content = window.contentView!
        for v in [form, scroll, bottom] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            form.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            form.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bottom.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            bottom.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            bottom.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            bottom.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    // MARK: Hledání

    @objc private func toggleSearch() {
        if let c = collector, !c.isFinished { c.cancel(); return }
        start()
    }

    private func criteria() -> SearchCriteria? {
        var c = SearchCriteria(root: URL(fileURLWithPath: (root.stringValue as NSString).expandingTildeInPath))
        c.masks = masks.stringValue.isEmpty ? "*" : masks.stringValue
        c.text = text.stringValue
        c.includeSubdirectories = subdirs.state == .on
        c.includeHidden = hidden.state == .on
        c.searchInArchives = archives.state == .on
        c.caseSensitive = caseSens.state == .on
        c.useRegex = regex.state == .on
        if let v = Int64(minKB.stringValue) { c.minSize = v * 1024 }
        if let v = Int64(maxKB.stringValue) { c.maxSize = v * 1024 }
        if let d = Double(days.stringValue) { c.modifiedAfter = Date().addingTimeInterval(-d * 86_400) }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: c.root.path, isDirectory: &isDir), isDir.boolValue else {
            Dialogs.error("Neplatný adresář", c.root.path); return nil
        }
        if let err = FileSearch.validate(c) { Dialogs.error("Neplatný regulární výraz", err); return nil }
        return c
    }

    private func start() {
        guard let c = criteria() else { return }
        results = []; table.reloadData()
        let col = HitCollector()
        collector = col
        searchButton.title = "Zastavit"
        status.stringValue = "Hledám…"
        Task.detached {
            let n = FileSearch().run(c, isCancelled: { col.isCancelled }, onHit: { col.add($0) })
            col.finish(scanned: n)
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        guard let col = collector else { return }
        let finished = col.isFinished          // nejdřív stav, potom vyprázdnění (jinak by se ztratily poslední nálezy)
        let batch = col.drain()
        if !batch.isEmpty { results += batch; table.reloadData() }
        status.stringValue = finished ? "Hotovo: \(results.count) nalezeno, prohledáno \(col.scanned) souborů"
                                      : "Hledám… nalezeno \(results.count)"
        if finished {
            timer?.invalidate(); timer = nil
            searchButton.title = "Hledat"
            if col.isCancelled { status.stringValue = "Zastaveno: \(results.count) nalezeno" }
        }
    }

    private var selectedHit: SearchHit? { table.selectedRow >= 0 && table.selectedRow < results.count ? results[table.selectedRow] : nil }
    @objc private func openSelected() { if let h = selectedHit { goTo(h.url, h.inner) } }
    @objc private func viewSelected() {
        guard let h = selectedHit else { return }
        if let inner = h.inner {
            guard let fs = try? ArchiveFileSystem(archiveURL: h.url), let tmp = try? fs.extractToTemporary("/" + inner) else { return }
            ListerWindow.show(tmp)
        } else { ListerWindow.show(h.url) }
    }

    // MARK: Tabulka

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let col, row < results.count else { return nil }
        let h = results[row]
        let cell = (tv.makeView(withIdentifier: col.identifier, owner: nil) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: ""); f.identifier = col.identifier; f.lineBreakMode = .byTruncatingMiddle; return f
        }()
        switch col.identifier.rawValue {
        case "name": cell.stringValue = h.inner.map { ($0 as NSString).lastPathComponent } ?? h.url.lastPathComponent
        case "dir": cell.stringValue = h.inner.map { h.url.path + " ▸ /" + ($0 as NSString).deletingLastPathComponent } ?? h.url.deletingLastPathComponent().path
        case "size": cell.stringValue = Fmt.bytes(h.size); cell.alignment = .right
        default: cell.stringValue = h.line.map { "\($0): \(h.snippet ?? "")" } ?? ""
        }
        return cell
    }

    func windowWillClose(_ notification: Notification) {
        collector?.cancel(); timer?.invalidate(); timer = nil
        Self.current = nil
    }
}
