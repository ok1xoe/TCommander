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
            else { activeSide = side.other }
            return true
        case 36, 76: // Return
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
        case 53: // Esc
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
        guard busy == nil else { return }
        let src = source, sources = src.targets.map(\.url)
        guard !sources.isEmpty else { return }
        let verb = kind == .copy ? "Kopírovat" : "Přesunout"
        let what = sources.count == 1 ? "„\(sources[0].lastPathComponent)“" : "\(sources.count) položek"
        let initial = target.path.path + "/"
        guard let text = Dialogs.prompt(title: "\(verb) \(what)", message: "Cíl:", initial: initial, ok: verb) else { return }
        guard let items = resolveTransfer(sources: sources, destination: text, base: src.path) else { return }
        guard !items.isEmpty else { return }

        var policy = ConflictPolicy.overwrite
        let conflicts = ops.conflicts(items)
        if !conflicts.isEmpty {
            guard let p = Dialogs.conflictPolicy(count: conflicts.count, example: conflicts[0].destination.path) else { return }
            policy = p
        }
        let ops = self.ops
        busy = kind == .copy ? "Kopíruji…" : "Přesouvám…"
        Task {
            let report = await Task.detached { ops.perform(kind, items, policy: policy) }.value
            self.finish(report, success: kind == .copy ? "Zkopírováno" : "Přesunuto")
        }
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
        guard busy == nil else { return }
        let targets = source.targets.map(\.url)
        guard !targets.isEmpty else { return }
        let toTrash = deleteToTrash && !permanent
        let what = targets.count == 1 ? "„\(targets[0].lastPathComponent)“" : "\(targets.count) položek"
        guard Dialogs.confirm(title: toTrash ? "Přesunout do koše?" : "Smazat trvale?", message: what,
                              ok: toTrash ? "Do koše" : "Smazat", destructive: !toTrash) else { return }
        let ops = self.ops
        busy = "Mažu…"
        Task {
            let report = await Task.detached { ops.delete(targets, toTrash: toTrash) }.value
            self.finish(report, success: toTrash ? "Do koše" : "Smazáno")
        }
    }

    private func finish(_ report: OperationReport, success: String) {
        busy = nil
        source.unmarkAll()
        reloadAll()
        var parts = ["\(success): \(report.succeeded)"]
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

    // MARK: Příkazová řádka

    func runCommandLine() {
        let cmd = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty, busy == nil else { return }
        commandLine = ""
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
