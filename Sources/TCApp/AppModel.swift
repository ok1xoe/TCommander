import AppKit
import Observation
import TCCore

enum Side { case left, right
    var other: Side { self == .left ? .right : .left }
    var key: Bool { self == .left }
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    let left: PanelGroup
    let right: PanelGroup
    var activeSide: Side = .left
    var commandLine = ""
    /// Rozepsaná cesta v adresním řádku panelu (nil = zobrazuje se skutečná cesta).
    var pathEdit: [Bool: String] = [:]
    var busy: String?
    let jobs = JobManager()
    var quickViewOn = false
    private(set) var commandHistory: [String] = UserDefaults.standard.stringArray(forKey: "commandHistory") ?? []
    @ObservationIgnored private var historyIndex: Int?
    let hotlist = Hotlist(file: Hotlist.defaultFile())
    /// Zobrazený rychlý filtr v panelech (klíč: levý = true).
    var filterVisible: [Bool: Bool] = [:]
    var verifyCopies = false { didSet { defaults.set(verifyCopies, forKey: "verifyCopies") } }
    var status: String?
    var deleteToTrash = true
    var showHidden = false { didSet { for t in left.tabs + right.tabs { t.showHidden = showHidden } } }

    @ObservationIgnored private let ops = FileOperations()
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func restore(_ key: String) -> PanelGroup {
            let paths = (defaults(key) ?? []).map { URL(fileURLWithPath: $0) }
                .filter { var d: ObjCBool = false; return FileManager.default.fileExists(atPath: $0.path, isDirectory: &d) && d.boolValue }
            let g = PanelGroup(paths: paths.isEmpty ? [home] : paths)
            g.select(UserDefaults.standard.integer(forKey: key + ".active"))
            return g
        }
        func defaults(_ key: String) -> [String]? { UserDefaults.standard.stringArray(forKey: key) }
        left = restore("tabs.left")
        right = restore("tabs.right")
        showHidden = UserDefaults.standard.bool(forKey: "showHidden")
        verifyCopies = UserDefaults.standard.bool(forKey: "verifyCopies")
        for t in left.tabs + right.tabs { t.showHidden = showHidden }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadAll() }
        }
    }

    func save() {
        defaults.set(left.tabs.map(\.path.path), forKey: "tabs.left"); defaults.set(left.activeIndex, forKey: "tabs.left.active")
        defaults.set(right.tabs.map(\.path.path), forKey: "tabs.right"); defaults.set(right.activeIndex, forKey: "tabs.right.active")
        defaults.set(showHidden, forKey: "showHidden")
    }

    func group(_ side: Side) -> PanelGroup { side == .left ? left : right }
    var source: PanelTab { group(activeSide).active }
    var target: PanelTab { group(activeSide.other).active }

    func reloadAll() { left.tabs.forEach { $0.reload() }; right.tabs.forEach { $0.reload() } }

    // MARK: Klávesnice

    func handleKey(_ e: NSEvent, side: Side) -> Bool {
        activeSide = side
        let m = e.modifierFlags.intersection([.command, .option, .control, .shift])
        switch e.keyCode {
        case 48: // Tab
            if m == .control { group(side).nextTab() } else if m == [.control, .shift] { group(side).previousTab() }
            else if !quickViewOn { activeSide = side.other }
            return true
        case 36, 76: // Return
            if m == .option { properties(); return true }
            if m == .control { insertNameIntoCommandLine(); return true }
            if m == [] { open(); return true }
        case 51: // Backspace
            if m == [] { source.goUp(); return true }
            if m == .command { delete(permanent: false); return true }
        case 117: if m == [] { delete(permanent: false); return true }
                  if m == .shift { delete(permanent: true); return true }
        case 49: if m == [] { spaceKey(); return true }
        case 114: if m == [] { source.toggleMarkAndAdvance(); return true }
        case 69: if m == [] { markByMask(on: true); return true }
        case 78: if m == [] { markByMask(on: false); return true }
        case 67: if m == [] { source.invertMarks(); return true }
        case 11: if m == .control { toggleBranchView(); return true }   // Ctrl+B
        case 46: if m == .control { multiRename(); return true }        // Ctrl+M
        case 1: if m == .control { toggleFilter(); return true }        // Ctrl+S
        case 12: if m == .control { quickViewOn.toggle(); return true } // Ctrl+Q
        case 53: // Esc
            if filterVisible[side.key] == true { filterVisible[side.key] = false; source.quickFilter = ""; return true }
            if !source.quickFilter.isEmpty { source.quickFilter = "" } else { commandLine = ""; source.marked.isEmpty ? () : source.unmarkAll() }
            return true
        case 120: rename(); return true                                  // F2
        case 99: view(); return true                                     // F3
        case 118: if m == .shift { newFile() } else { edit() }; return true // F4
        case 96: transfer(.copy); return true                            // F5
        case 97: if m == .shift { rename() } else { transfer(.move) }; return true // F6
        case 98: if m == .option { search() } else { makeDirectory() }; return true // F7
        case 100: delete(permanent: m == .shift); return true            // F8
        default: break
        }
        return false
    }

    // MARK: Navigace

    func open() {
        guard let url = source.activateCursor() else { return }
        NSWorkspace.shared.open(url)
    }

    func spaceKey() {
        if let e = source.cursorEntry, e.isDirectory, !e.isParentLink, source.dirSizes[e.url] == nil { source.computeDirSize(e) }
        source.toggleMarkAndAdvance()
    }

    func markByMask(on: Bool) {
        guard let mask = Dialogs.prompt(title: on ? "Označit soubory" : "Odznačit soubory",
                                        message: "Maska (např. *.txt;*.doc):", initial: "*.*") else { return }
        source.mark(matching: mask, on: on)
    }

    func goTo(_ url: URL) { source.navigate(to: url) }

    func toggleBranchView() { if source.isBranch { source.exitBranchView() } else { source.enterBranchView() } }

    func toggleFilter() {
        let k = activeSide.key
        let show = filterVisible[k] != true
        filterVisible[k] = show
        if !show { source.quickFilter = "" }
    }
    func swapPanels() {
        let a = source.path, b = target.path
        source.navigate(to: b); target.navigate(to: a)
    }
    func targetEqualsSource() { target.navigate(to: source.path) }

    func insertNameIntoCommandLine() {
        guard let e = source.cursorEntry, !e.isParentLink else { return }
        commandLine += (commandLine.isEmpty || commandLine.hasSuffix(" ") ? "" : " ") + shellQuote(e.name) + " "
    }

    private func shellQuote(_ s: String) -> String {
        s.range(of: "^[A-Za-z0-9_./-]+$", options: .regularExpression) != nil ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Souborové operace

    func transfer(_ kind: TransferKind) {
        let src = source, sources = src.targets.map(\.url)
        guard !sources.isEmpty else { return }
        let verb = kind == .copy ? "Kopírovat" : "Přesunout"
        let what = sources.count == 1 ? "„\(sources[0].lastPathComponent)“" : "\(sources.count) položek"
        let initial = target.path.path + "/"
        guard let text = Dialogs.prompt(title: "\(verb) \(what)", message: "Cíl:", initial: initial, ok: verb) else { return }
        guard let items = resolveTransfer(sources: sources, destination: text, base: src.path) else { return }
        enqueueTransfer(kind, items, what: what)
    }

    func enqueueTransfer(_ kind: TransferKind, _ items: [TransferItem], what: String) {
        guard !items.isEmpty else { return }
        let verb = kind == .copy ? "Kopírovat" : "Přesunout"
        var policy = ConflictPolicy.overwrite
        let conflicts = ops.conflicts(items)
        if !conflicts.isEmpty {
            guard let p = Dialogs.conflictPolicy(count: conflicts.count, example: conflicts[0].destination.path) else { return }
            policy = p
        }
        let ops = self.ops, verify = verifyCopies, chosen = policy
        jobs.enqueue(title: "\(verb) \(what)", work: { control, progress in
            ops.perform(kind, items, policy: chosen, verify: verify, control: control, progress: progress)
        }, onFinish: { [weak self] report in
            self?.finish(report, success: kind == .copy ? "Zkopírováno" : "Přesunuto")
        })
    }

    /// Přetažení souborů do panelu nebo na adresář (Finder: stejný svazek = přesun, jinak kopie; ⌥ = kopie).
    func drop(_ urls: [URL], into dir: URL, move: Bool) {
        let items = ops.plan(sources: urls, into: dir)
        enqueueTransfer(move ? .move : .copy, items, what: urls.count == 1 ? "„\(urls[0].lastPathComponent)“" : "\(urls.count) položek")
    }

    static func dropIsMove(source: URL, destination: URL, option: Bool) -> Bool {
        if option { return false }
        var a = stat(), b = stat()
        guard stat(source.path, &a) == 0, stat(destination.path, &b) == 0 else { return false }
        return a.st_dev == b.st_dev
    }

    private func resolveTransfer(sources: [URL], destination text: String, base: URL) -> [TransferItem]? {
        var path = (text.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        guard !path.isEmpty else { return nil }
        let wantsDir = path.hasSuffix("/")
        if !path.hasPrefix("/") { path = base.appendingPathComponent(path).path }
        let dest = URL(fileURLWithPath: path).standardizedFileURL
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: dest.path, isDirectory: &isDir)
        if exists && isDir.boolValue { return ops.plan(sources: sources, into: dest) }
        if sources.count == 1 && !wantsDir {
            guard FileManager.default.fileExists(atPath: dest.deletingLastPathComponent().path) else {
                Dialogs.error("Neplatný cíl", "Adresář „\(dest.deletingLastPathComponent().path)“ neexistuje."); return nil
            }
            return [TransferItem(source: sources[0], destination: dest)]   // kopie/přesun pod novým názvem
        }
        if exists { Dialogs.error("Neplatný cíl", "„\(dest.path)“ není adresář."); return nil }
        do { try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true) }
        catch { Dialogs.error("Cíl nelze vytvořit", error.localizedDescription); return nil }
        return ops.plan(sources: sources, into: dest)
    }

    func delete(permanent: Bool) {
        let targets = source.targets.map(\.url)
        guard !targets.isEmpty else { return }
        let toTrash = deleteToTrash && !permanent
        let what = targets.count == 1 ? "„\(targets[0].lastPathComponent)“" : "\(targets.count) položek"
        guard Dialogs.confirm(title: toTrash ? "Přesunout do koše?" : "Smazat trvale?", message: what,
                              ok: toTrash ? "Do koše" : "Smazat", destructive: !toTrash) else { return }
        let ops = self.ops
        jobs.enqueue(title: "\(toTrash ? "Do koše" : "Mazání"): \(what)", work: { control, progress in
            ops.delete(targets, toTrash: toTrash, control: control, progress: progress)
        }, onFinish: { [weak self] report in
            self?.finish(report, success: toTrash ? "Do koše" : "Smazáno")
        })
    }

    private func finish(_ report: OperationReport, success: String) {
        source.unmarkAll()
        reloadAll()
        var parts = [report.cancelled ? "Zrušeno" : success, "\(report.succeeded)"]
        parts = [parts[0] + ": " + parts[1]]
        if report.skipped > 0 { parts.append("přeskočeno: \(report.skipped)") }
        if !report.failures.isEmpty { parts.append("chyb: \(report.failures.count)") }
        status = parts.joined(separator: ", ")
        if !report.failures.isEmpty {
            Dialogs.error("Některé položky se nepodařilo zpracovat",
                          report.failures.prefix(10).map { "\($0.url.lastPathComponent): \($0.message)" }.joined(separator: "\n"))
        }
    }

    func rename() {
        guard let e = source.targets.first, source.targets.count == 1 else { return }
        guard let name = Dialogs.prompt(title: "Přejmenovat", message: "Nový název:", initial: e.name, ok: "Přejmenovat") else { return }
        do { let new = try ops.rename(e.url, to: name); source.unmarkAll(); reloadAll(); source.reload(select: new) }
        catch { Dialogs.error("Přejmenování selhalo", error.localizedDescription) }
    }

    func makeDirectory() {
        guard let name = Dialogs.prompt(title: "Nový adresář", message: "Název (lze i vnořený a/b/c):", initial: "", ok: "Vytvořit") else { return }
        do { let new = try ops.makeDirectory(name, in: source.path); reloadAll(); source.reload(select: new) }
        catch { Dialogs.error("Vytvoření adresáře selhalo", error.localizedDescription) }
    }

    func newFile() {
        guard let name = Dialogs.prompt(title: "Nový soubor", message: "Název:", initial: "", ok: "Vytvořit") else { return }
        do { let new = try ops.makeFile(named: name, in: source.path); reloadAll(); source.reload(select: new); openInEditor(new) }
        catch { Dialogs.error("Vytvoření souboru selhalo", error.localizedDescription) }
    }

    func search() {
        SearchWindow.show(root: source.path) { [weak self] url in
            guard let self else { return }
            self.source.navigate(to: url.deletingLastPathComponent(), select: url)
            NSApp.windows.first { $0.isVisible && $0.title == "macTC" }?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Prohlížení a editace

    func view() {
        guard let e = source.targets.first, !e.isDirectory else { return }
        ListerWindow.show(e.url)
    }

    func edit() {
        guard let e = source.targets.first, !e.isDirectory else { return }
        openInEditor(e.url)
    }

    private func openInEditor(_ url: URL) {
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: Porovnání a synchronizace

    /// Porovnání souborů podle obsahu: dva označené soubory v panelu, jinak soubory pod kurzory obou panelů.
    func compareFiles() {
        let t = source.targets.filter { !$0.isDirectory }
        if t.count == 2 { FileCompareWindow.show(t[0].url, t[1].url); return }
        guard let a = source.cursorEntry, let b = target.cursorEntry, !a.isDirectory, !b.isDirectory, !a.isParentLink, !b.isParentLink else {
            Dialogs.error("Porovnat soubory", "Označte dva soubory, nebo nastavte kurzory na soubor v každém panelu."); return
        }
        FileCompareWindow.show(a.url, b.url)
    }

    /// Porovná adresáře obou panelů (bez podadresářů) a označí odlišné soubory.
    func compareDirectories() {
        var o = SyncOptions(); o.recursive = false; o.includeHidden = showHidden
        let l = left.active, r = right.active
        let items = DirectoryComparer.compare(left: l.path, right: r.path, options: o)
        l.setMarks(Set(items.filter { $0.state == .onlyLeft || $0.state == .leftNewer || $0.state == .different }.compactMap { $0.left?.url }))
        r.setMarks(Set(items.filter { $0.state == .onlyRight || $0.state == .rightNewer || $0.state == .different }.compactMap { $0.right?.url }))
        status = "Porovnání adresářů: \(items.filter { $0.state != .same }.count) rozdílů"
    }

    func synchronize() {
        SyncWindow.show(left: left.active.path, right: right.active.path, jobs: jobs) { [weak self] in self?.reloadAll() }
    }

    // MARK: Nástroje

    func multiRename() {
        let files = source.targets.map(\.url)
        guard !files.isEmpty else { return }
        MultiRenameWindow.show(files: files) { [weak self] newURL in
            guard let self else { return }
            self.source.unmarkAll()
            self.reloadAll()
            if let newURL { self.source.reload(select: newURL) }
        }
    }

    func properties() {
        let t = source.targets
        guard !t.isEmpty else { return }
        let single = t.count == 1 ? t[0] : nil
        let df = DateFormatter(); df.dateFormat = "dd.MM.yyyy HH:mm:ss"
        var info = single.map { "\($0.url.path)\n\($0.isDirectory ? "Adresář" : Fmt.bytes($0.size) + " bajtů")" } ?? "\(t.count) vybraných položek"
        if let e = single, e.isDirectory, let size = source.dirSizes[e.url] { info += " · \(Fmt.bytes(size)) bajtů" }
        guard let r = Dialogs.properties(title: "Vlastnosti", info: info,
                                         permissions: single.map { String($0.permissions, radix: 8) } ?? "",
                                         modified: single?.modified.map { df.string(from: $0) } ?? "") else { return }
        var perms: UInt16?, date: Date?
        if !r.permissions.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let p = FileAttributes.parseOctal(r.permissions) else { Dialogs.error("Neplatná oprávnění", "Zadejte osmičkově, např. 644."); return }
            perms = p
        }
        if !r.modified.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let d = df.date(from: r.modified) else { Dialogs.error("Neplatné datum", "Formát: dd.MM.yyyy HH:mm:ss"); return }
            date = d
        }
        var errors: [String] = []
        for e in t {
            do { try FileAttributes.apply(e.url, permissions: perms, modified: date) } catch { errors.append("\(e.name): \(error.localizedDescription)") }
        }
        reloadAll()
        if !errors.isEmpty { Dialogs.error("Některé změny se nepodařily", errors.prefix(10).joined(separator: "\n")) }
    }

    private final class LineBox: @unchecked Sendable { var lines: [ChecksumFile.Line] = [] }

    func checksums() {
        let files = source.targets.filter { !$0.isDirectory }
        guard !files.isEmpty else { Dialogs.error("Kontrolní součty", "Vyberte soubory (ne adresáře)."); return }
        let algs = ChecksumAlgorithm.allCases
        guard let i = Dialogs.choose(title: "Kontrolní součty", message: "Algoritmus pro \(files.count) souborů:",
                                     options: algs.map(\.rawValue), ok: "Spočítat") else { return }
        let alg = algs[i], urls = files.map(\.url), total = files.reduce(Int64(0)) { $0 + $1.size }
        let box = LineBox(), dir = source.path
        jobs.enqueue(title: "Kontrolní součty \(alg.rawValue)", work: { control, progress in
            var rep = OperationReport(), p = TransferProgress()
            p.filesTotal = urls.count; p.bytesTotal = total
            for u in urls {
                p.current = u.lastPathComponent
                let h = Checksum.hash(u, alg) { n in p.bytesDone += Int64(n); progress(p); return control.checkpoint() }
                guard let h else {
                    if control.isCancelled { rep.cancelled = true; break }
                    rep.failures.append(.init(url: u, message: "Soubor nelze přečíst")); continue
                }
                box.lines.append(.init(hash: h, name: u.lastPathComponent)); p.filesDone += 1
            }
            rep.succeeded = box.lines.count
            return rep
        }, onFinish: { [weak self] rep in
            guard let self, !rep.cancelled, !box.lines.isEmpty else { return }
            let text = ChecksumFile.format(box.lines)
            if Dialogs.output(title: "\(alg.rawValue)", text: text, extraButton: "Uložit do souboru") {
                let name = box.lines.count == 1 ? "\(box.lines[0].name).\(alg.fileExtension)" : "checksums.\(alg.fileExtension)"
                do { try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8); self.reloadAll() }
                catch { Dialogs.error("Uložení selhalo", error.localizedDescription) }
            }
        })
    }

    func verifyChecksums() {
        guard let e = source.targets.first, !e.isDirectory else { return }
        busy = "Ověřuji součty…"
        let url = e.url
        Task {
            let r = await Task.detached { ChecksumFile.verify(sumFile: url) }.value
            self.busy = nil
            guard let r else { Dialogs.error("Ověření součtů", "Soubor „\(e.name)“ není platný soubor s kontrolními součty."); return }
            let bad = r.filter { $0.status != .ok }
            let text = r.map { ($0.status == .ok ? "OK        " : $0.status == .missing ? "CHYBÍ     " : "NESOUHLASÍ ") + $0.name }.joined(separator: "\n")
            Dialogs.output(title: bad.isEmpty ? "Všech \(r.count) souborů souhlasí" : "Nesouhlasí nebo chybí: \(bad.count) z \(r.count)", text: text)
        }
    }

    func splitFile() {
        guard let e = source.targets.first, !e.isDirectory, source.targets.count == 1 else { return }
        guard let t = Dialogs.prompt(title: "Rozdělit „\(e.name)“", message: "Velikost jedné části v MB (do \(target.path.path)):", initial: "100", ok: "Rozdělit"),
              let mb = Double(t.replacingOccurrences(of: ",", with: ".")), mb > 0 else { return }
        let size = Int64(mb * 1_048_576), url = e.url, dir = target.path
        jobs.enqueue(title: "Rozdělit \(e.name)", work: { control, progress in
            FileSplitter.split(url, partSize: size, into: dir, control: control, progress: progress)
        }, onFinish: { [weak self] r in self?.finish(r, success: "Vytvořeno částí") })
    }

    func combineFiles() {
        guard let e = source.targets.first, e.name.hasSuffix(".001") else { Dialogs.error("Spojit soubory", "Nastavte kurzor na první část (název.001)."); return }
        let url = e.url, dir = target.path
        guard Dialogs.confirm(title: "Spojit části", message: "Výsledek bude uložen do \(dir.path).", ok: "Spojit") else { return }
        jobs.enqueue(title: "Spojit \(e.name)", work: { control, progress in
            FileSplitter.combine(first: url, into: dir, control: control, progress: progress)
        }, onFinish: { [weak self] r in self?.finish(r, success: "Spojeno") })
    }

    func makeLink(hard: Bool) {
        guard let e = source.targets.first, source.targets.count == 1 else { return }
        guard let name = Dialogs.prompt(title: hard ? "Pevný odkaz" : "Symbolický odkaz",
                                        message: "Název odkazu v \(target.path.path):", initial: e.name + (hard ? " hardlink" : " alias"), ok: "Vytvořit") else { return }
        let link = target.path.appendingPathComponent(name)
        do {
            if hard { try ops.makeHardlink(to: e.url, at: link) } else { try ops.makeSymlink(to: e.url.path, at: link) }
            reloadAll()
        } catch { Dialogs.error("Vytvoření odkazu selhalo", error.localizedDescription) }
    }

    // MARK: Příkazová řádka

    private func remember(_ cmd: String) {
        commandHistory.removeAll { $0 == cmd }
        commandHistory.append(cmd)
        if commandHistory.count > 100 { commandHistory.removeFirst() }
        historyIndex = nil
        UserDefaults.standard.set(commandHistory, forKey: "commandHistory")
    }

    func historyPrevious() {
        guard !commandHistory.isEmpty else { return }
        let i = max(0, (historyIndex ?? commandHistory.count) - 1)
        historyIndex = i; commandLine = commandHistory[i]
    }

    func historyNext() {
        guard let i = historyIndex else { return }
        if i + 1 < commandHistory.count { historyIndex = i + 1; commandLine = commandHistory[i + 1] }
        else { historyIndex = nil; commandLine = "" }
    }

    func runCommandLine() {
        let cmd = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty, busy == nil else { return }
        commandLine = ""
        remember(cmd)
        if cmd == "cd" || cmd.hasPrefix("cd ") {
            let arg = String(cmd.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            let expanded = arg.isEmpty ? NSHomeDirectory() : (arg as NSString).expandingTildeInPath
            let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : source.path.appendingPathComponent(expanded)
            source.navigate(to: url)
            return
        }
        let dir = source.path
        busy = "Spouštím příkaz…"
        Task {
            let r = await Task.detached { Shell.run(cmd, in: dir) }.value
            self.busy = nil
            self.reloadAll()
            if !r.output.isEmpty || r.status != 0 {
                let note = r.timedOut ? "\n\n(přerušeno po 60 s)" : (r.status != 0 ? "\n\n(návratový kód \(r.status))" : "")
                Dialogs.output(title: cmd, text: r.output + note)
            }
        }
    }
}
