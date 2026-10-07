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
    let connections = SavedConnections(file: SavedConnections.defaultFile())
    /// Zobrazený rychlý filtr v panelech (klíč: levý = true).
    var filterVisible: [Bool: Bool] = [:]
    var status: String?

    // MARK: Nastavení a přizpůsobení (ukládá se do Application Support)
    @ObservationIgnored let settingsStore = JSONStore<AppSettings>(name: "settings")
    @ObservationIgnored let keymapStore = JSONStore<Keymap>(name: "keymap")
    @ObservationIgnored let userCommandsStore = JSONStore<[UserCommand]>(name: "usercommands")
    @ObservationIgnored let buttonBarStore = JSONStore<[ButtonBarItem]>(name: "buttonbar")
    @ObservationIgnored let startMenuStore = JSONStore<[ButtonBarItem]>(name: "startmenu")
    @ObservationIgnored let associationsStore = JSONStore<[FileAssociation]>(name: "associations")
    @ObservationIgnored let favoriteTabsStore = JSONStore<[FavoriteTabSet]>(name: "favoritetabs")

    var settings: AppSettings { didSet { if settings != oldValue { applySettings(oldValue); settingsStore.save(settings) } } }
    var keymap: Keymap { didSet { keymapStore.save(keymap) } }
    var userCommands: [UserCommand] { didSet { userCommandsStore.save(userCommands) } }
    var buttonBar: [ButtonBarItem] { didSet { buttonBarStore.save(buttonBar) } }
    var startMenu: [ButtonBarItem] { didSet { startMenuStore.save(startMenu) } }
    var associations: [FileAssociation] { didSet { associationsStore.save(associations) } }
    var favoriteTabs: [FavoriteTabSet] { didSet { favoriteTabsStore.save(favoriteTabs) } }

    var verifyCopies: Bool { get { settings.verifyCopies } set { settings.verifyCopies = newValue } }
    var deleteToTrash: Bool { get { settings.deleteToTrash } set { settings.deleteToTrash = newValue } }
    var showHidden: Bool { get { settings.showHidden } set { settings.showHidden = newValue } }

    var panelStyle: PanelStyle { PanelStyle(fontSize: settings.fontSize, rowHeight: settings.rowHeight, colorRules: settings.colorRules) }

    private func applySettings(_ old: AppSettings) {
        if settings.showHidden != old.showHidden { for t in left.tabs + right.tabs { t.showHidden = settings.showHidden } }
    }

    @ObservationIgnored let ops = FileOperations()
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
        var initial = AppSettings()
        if !FileManager.default.fileExists(atPath: settingsStore.file.path) {          // převzetí starších hodnot
            initial.showHidden = UserDefaults.standard.bool(forKey: "showHidden")
            initial.verifyCopies = UserDefaults.standard.bool(forKey: "verifyCopies")
        }
        settings = settingsStore.load(default: initial)
        keymap = keymapStore.load(default: Keymap())
        userCommands = userCommandsStore.load(default: [])
        buttonBar = buttonBarStore.load(default: DefaultCustomization.buttonBar)
        startMenu = startMenuStore.load(default: DefaultCustomization.startMenu)
        associations = associationsStore.load(default: [])
        favoriteTabs = favoriteTabsStore.load(default: [])
        for t in left.tabs + right.tabs { t.showHidden = settings.showHidden }
        ArchiveFileSystem.cleanTemporary()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save(); ArchiveFileSystem.cleanTemporary() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadAll() }
        }
    }

    func save() {
        defaults.set(left.tabs.map(\.persistentPath.path), forKey: "tabs.left"); defaults.set(left.activeIndex, forKey: "tabs.left.active")
        defaults.set(right.tabs.map(\.persistentPath.path), forKey: "tabs.right"); defaults.set(right.activeIndex, forKey: "tabs.right.active")
    }

    func group(_ side: Side) -> PanelGroup { side == .left ? left : right }
    var source: PanelTab { group(activeSide).active }
    var target: PanelTab { group(activeSide.other).active }

    func reloadAll() { left.tabs.forEach { $0.reload() }; right.tabs.forEach { $0.reload() } }

    // MARK: Klávesnice

    /// Zkratka z události klávesnice (nil pro znaky, které nelze zapsat).
    static func shortcut(from e: NSEvent) -> Shortcut? {
        var mods = Set<Shortcut.Modifier>()
        let f = e.modifierFlags
        if f.contains(.control) { mods.insert(.ctrl) }
        if f.contains(.option) { mods.insert(.alt) }
        if f.contains(.shift) { mods.insert(.shift) }
        if f.contains(.command) { mods.insert(.cmd) }
        if let k = Shortcut.macKeyCodes[e.keyCode] { return Shortcut(key: k, modifiers: mods) }
        guard let c = e.charactersIgnoringModifiers?.lowercased(), c.count == 1 else { return nil }
        return Shortcut(key: c, modifiers: mods)
    }

    func handleKey(_ e: NSEvent, side: Side) -> Bool {
        activeSide = side
        if let sc = Self.shortcut(from: e), let id = keymap.command(for: sc) { perform(id); return true }
        // pevné klávesy mimo konfigurovatelné příkazy
        let m = e.modifierFlags.intersection([.command, .option, .control, .shift])
        switch e.keyCode {
        case 51: if m == .command { delete(permanent: false); return true }        // ⌘⌫ jako ve Finderu
        case 49: if m == [] { spaceKey(); return true }
        case 114: if m == [] { source.toggleMarkAndAdvance(); return true }         // Insert
        case 53: // Esc
            if filterVisible[side.key] == true { filterVisible[side.key] = false; source.quickFilter = ""; return true }
            if !source.quickFilter.isEmpty { source.quickFilter = "" } else { commandLine = ""; source.marked.isEmpty ? () : source.unmarkAll() }
            return true
        default: break
        }
        return false
    }

    // MARK: Navigace

    func open() {
        guard let url = source.activateCursor() else { return }
        if source.insideArchive, let tmp = extractToTemp(url) { NSWorkspace.shared.open(tmp) }
        else if source.remote != nil, let e = source.entries.first(where: { $0.url == url }) { withRemoteFile(e) { NSWorkspace.shared.open($0) } }
        else if !source.isVirtual {
            if let a = Associations.match(url.lastPathComponent, in: associations) { runAssociation(a) } else { NSWorkspace.shared.open(url) }
        }
    }

    /// Soubor z archivu se rozbalí do dočasného adresáře (ten se maže při startu a ukončení).
    func extractToTemp(_ inner: URL) -> URL? {
        guard let fs = source.archiveFS else { return nil }
        do { return try fs.extractToTemporary(inner.path) }
        catch { Dialogs.error("Soubor z archivu nelze rozbalit", error.localizedDescription); return nil }
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

    func goTo(_ url: URL) { source.navigateLocal(url) }

    func toggleBranchView() { if source.isBranch { source.exitBranchView() } else { source.enterBranchView() } }

    func toggleFilter() {
        let k = activeSide.key
        let show = filterVisible[k] != true
        filterVisible[k] = show
        if !show { source.quickFilter = "" }
    }
    func swapPanels() {
        let a = source.persistentPath, b = target.persistentPath
        source.navigateLocal(b); target.navigateLocal(a)
    }
    func targetEqualsSource() { target.navigateLocal(source.persistentPath) }

    func insertNameIntoCommandLine() {
        guard let e = source.cursorEntry, !e.isParentLink else { return }
        commandLine += (commandLine.isEmpty || commandLine.hasSuffix(" ") ? "" : " ") + shellQuote(e.name) + " "
    }

    private func shellQuote(_ s: String) -> String {
        s.range(of: "^[A-Za-z0-9_./-]+$", options: .regularExpression) != nil ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Souborové operace

    func requireLocal() -> Bool {
        if source.isVirtual { Dialogs.error(source.insideArchive ? "Archiv" : "Server", "Tato operace \(source.insideArchive ? "uvnitř archivu" : "na serveru") není k dispozici."); return false }
        return true
    }

    func requireLocalTarget() -> Bool {
        if target.isVirtual { Dialogs.error("Cíl", "Cílový panel je uvnitř archivu nebo na serveru; tato operace sem zapisovat neumí."); return false }
        return true
    }


    func transfer(_ kind: TransferKind) {
        if target.isVirtual || source.isVirtual { virtualTransfer(kind); return }
        let src = source, sources = src.targets.map(\.url)
        guard !sources.isEmpty else { return }
        let verb = kind == .copy ? "Kopírovat" : "Přesunout"
        let what = sources.count == 1 ? "„\(sources[0].lastPathComponent)“" : "\(sources.count) položek"
        let initial = target.path.path + "/"
        guard let text = Dialogs.prompt(title: "\(verb) \(what)", message: "Cíl:", initial: initial, ok: verb) else { return }
        guard let items = resolveTransfer(sources: sources, destination: text, base: src.path) else { return }
        enqueueTransfer(kind, items, what: what)
    }

    func extractFromArchive(_ kind: TransferKind) {
        guard kind == .copy else { Dialogs.error("Archiv", "Z archivu lze položky jen kopírovat (rozbalit), ne přesouvat."); return }
        guard let fs = source.archiveFS else { return }
        let entries = source.targets
        guard !entries.isEmpty else { return }
        let what = entries.count == 1 ? "„\(entries[0].name)“" : "\(entries.count) položek"
        guard let text = Dialogs.prompt(title: "Rozbalit \(what)", message: "Cíl:", initial: target.path.path + "/", ok: "Rozbalit"),
              let dest = resolveDirectory(text, base: target.path) else { return }
        let paths = entries.map(\.url.path)
        let existing = entries.filter { FileManager.default.fileExists(atPath: dest.appendingPathComponent($0.name).path) }
        var policy = ConflictPolicy.overwrite
        if !existing.isEmpty {
            guard let p = Dialogs.conflictPolicy(count: existing.count, example: dest.appendingPathComponent(existing[0].name).path) else { return }
            policy = p
        }
        let chosen = policy
        jobs.enqueue(title: "Rozbalit \(what)", work: { control, progress in
            fs.extract(paths, to: dest, policy: chosen, control: control, progress: progress)
        }, onFinish: { [weak self] r in self?.finish(r, success: "Rozbaleno") })
    }

    /// Cílový adresář z textu dialogu; chybějící se vytvoří.
    func resolveDirectory(_ text: String, base: URL) -> URL? {
        var path = (text.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        guard !path.isEmpty else { return nil }
        if !path.hasPrefix("/") { path = base.appendingPathComponent(path).path }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue { return url }
            Dialogs.error("Neplatný cíl", "„\(url.path)“ není adresář."); return nil
        }
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }
        catch { Dialogs.error("Cíl nelze vytvořit", error.localizedDescription); return nil }
    }

    // MARK: Zápis do archivů

    /// Archiv, který se bude upravovat (musí být zapisovatelného formátu).
    func writableArchive(_ tab: PanelTab) -> ArchiveFileSystem? {
        guard let fs = tab.archiveFS else { return nil }
        guard fs.isWritable else {
            Dialogs.error("Archiv je jen pro čtení", "Formát „\(tab.archiveFile?.pathExtension ?? "")“ nelze upravovat. Upravovat lze zip, tar.gz/bz2/xz a 7z.")
            return nil
        }
        return fs
    }

    /// Spustí úpravu archivu jako úlohu ve frontě a po dokončení obnoví všechny panely zobrazující tento archiv.
    private func modifyArchive(_ fs: ArchiveFileSystem, title: String, changes: ArchiveFileSystem.Changes,
                               after: @escaping @Sendable () -> Void = {}, success: String) {
        let url = fs.archiveURL
        jobs.enqueue(title: title, work: { control, progress in
            let r = fs.apply(changes, control: control, progress: progress)
            if r.failures.isEmpty && !r.cancelled { after() }
            return r
        }, onFinish: { [weak self] report in
            guard let self else { return }
            for t in self.left.tabs + self.right.tabs where t.archiveFile == url { t.refreshArchive() }
            self.finish(report, success: success)
        })
    }

    func innerName(_ tab: PanelTab, _ name: String) -> String {
        ArchiveSupport.normalize(tab.path.path == "/" ? name : tab.path.path + "/" + name)
    }

    private func deleteFromArchive() {
        guard let fs = writableArchive(source) else { return }
        let targets = source.targets
        guard !targets.isEmpty else { return }
        let what = targets.count == 1 ? "„\(targets[0].name)“" : "\(targets.count) položek"
        guard Dialogs.confirm(title: "Smazat z archivu?", message: "\(what) bude trvale odstraněno z archivu (nelze vrátit).", ok: "Smazat", destructive: true) else { return }
        var c = ArchiveFileSystem.Changes()
        c.remove = targets.map { ArchiveSupport.normalize($0.url.path) }
        modifyArchive(fs, title: "Smazat z archivu: \(what)", changes: c, success: "Smazáno z archivu")
    }

    private func renameInArchive() {
        guard let fs = writableArchive(source), let e = source.targets.first, source.targets.count == 1 else { return }
        guard let name = Dialogs.prompt(title: "Přejmenovat v archivu", message: "Nový název:", initial: e.name, ok: "Přejmenovat") else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !n.contains("/"), n != e.name else { return }
        guard !fs.exists(URL(fileURLWithPath: "/" + innerName(source, n))) else { Dialogs.error("Přejmenování", "„\(n)“ v archivu už existuje."); return }
        var c = ArchiveFileSystem.Changes()
        c.rename = [ArchiveSupport.normalize(e.url.path): innerName(source, n)]
        modifyArchive(fs, title: "Přejmenovat v archivu: \(e.name)", changes: c, success: "Přejmenováno")
    }

    private func makeDirectoryInArchive() {
        guard let fs = writableArchive(source) else { return }
        guard let name = Dialogs.prompt(title: "Nová složka v archivu", message: "Název (lze i vnořený a/b/c):", initial: "", ok: "Vytvořit") else { return }
        let n = name.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !n.isEmpty else { return }
        var c = ArchiveFileSystem.Changes()
        c.makeDirectories = [innerName(source, n)]
        modifyArchive(fs, title: "Nová složka v archivu: \(n)", changes: c, success: "Vytvořeno")
    }

    /// F5/F6 do panelu uvnitř archivu: ze souborů na disku, nebo z jiného archivu (přes dočasné rozbalení).
    func copyIntoArchive(_ kind: TransferKind) {
        guard let dst = writableArchive(target) else { return }
        let entries = source.targets
        guard !entries.isEmpty else { return }
        let what = entries.count == 1 ? "„\(entries[0].name)“" : "\(entries.count) položek"
        let innerDir = ArchiveSupport.normalize(target.path.path)
        let existing = entries.filter { dst.exists(URL(fileURLWithPath: "/" + innerName(target, $0.name))) }
        if !existing.isEmpty {
            guard Dialogs.confirm(title: "Přepsat v archivu?", message: "\(existing.count) položek už v archivu existuje a bude nahrazeno (např. „\(existing[0].name)“).",
                                  ok: "Přepsat", destructive: true) else { return }
        }
        guard Dialogs.confirm(title: (kind == .copy ? "Zkopírovat " : "Přesunout ") + what + " do archivu?",
                              message: "\(target.archiveFile?.lastPathComponent ?? "") ▸ \(target.path.path)", ok: kind == .copy ? "Kopírovat" : "Přesunout") else { return }
        guard let staged = stagedSource() else { return }
        let move = kind == .move
        if case .archive = staged, move { Dialogs.error("Archiv", "Z archivu lze jen kopírovat."); return }
        let url = dst.archiveURL
        jobs.enqueue(title: "\(move ? "Přesunout" : "Kopírovat") \(what) do archivu", work: { control, progress in
            let (locals, temp, early) = staged.stage(control: control, progress: progress)
            if let early { return early }
            defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
            var c = ArchiveFileSystem.Changes()
            c.add = locals.map { .init(local: $0, innerDirectory: innerDir) }
            let report = dst.apply(c, control: control, progress: progress)
            if move && report.failures.isEmpty && !report.cancelled { staged.deleteSources() }
            return report
        }, onFinish: { [weak self] report in
            guard let self else { return }
            for t in self.left.tabs + self.right.tabs where t.archiveFile == url { t.refreshArchive() }
            self.finish(report, success: move ? "Přesunuto do archivu" : "Zkopírováno do archivu")
        })
    }

    /// Alt+F5: zabalí vybrané soubory do nového archivu.
    func packFiles() {
        guard requireLocal(), requireLocalTarget() else { return }
        let items = source.targets
        guard !items.isEmpty else { return }
        let formats = ArchiveFormat.allCases
        guard let fi = Dialogs.choose(title: "Zabalit do archivu", message: "Formát:", options: formats.map(\.displayName), ok: "Pokračovat") else { return }
        let format = formats[fi]
        let base = items.count == 1 ? items[0].baseName : source.path.lastPathComponent
        let initial = target.path.appendingPathComponent(base + "." + format.fileExtension).path
        guard let text = Dialogs.prompt(title: "Zabalit \(items.count == 1 ? "„\(items[0].name)“" : "\(items.count) položek")",
                                        message: "Soubor archivu:", initial: initial, ok: "Zabalit") else { return }
        var path = (text.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        if !path.hasPrefix("/") { path = target.path.appendingPathComponent(path).path }
        let dest = URL(fileURLWithPath: path).standardizedFileURL
        if ArchiveFormat.detect(fileName: dest.lastPathComponent) != format {
            Dialogs.error("Zabalit", "Název souboru musí končit „.\(format.fileExtension)“."); return
        }
        guard FileManager.default.fileExists(atPath: dest.deletingLastPathComponent().path) else {
            Dialogs.error("Zabalit", "Adresář „\(dest.deletingLastPathComponent().path)“ neexistuje."); return
        }
        if FileManager.default.fileExists(atPath: dest.path),
           !Dialogs.confirm(title: "Přepsat existující archiv?", message: dest.path, ok: "Přepsat", destructive: true) { return }
        let urls = items.map(\.url)
        if urls.contains(where: { dest.path == $0.path || dest.path.hasPrefix($0.path + "/") }) {
            Dialogs.error("Zabalit", "Archiv nelze uložit do zabalovaného adresáře."); return
        }
        jobs.enqueue(title: "Zabalit do \(dest.lastPathComponent)", work: { control, progress in
            ArchiveWriter.create(dest, format: format, sources: urls, control: control, progress: progress)
        }, onFinish: { [weak self] r in self?.finish(r, success: "Zabaleno") })
    }

    // MARK: Archivy

    private func selectedArchives() -> [URL] {
        if let a = source.archiveFile { return [a] }
        return source.targets.filter { !$0.isDirectory && ArchiveSupport.isArchive($0.name) }.map(\.url)
    }

    nonisolated private static func archiveBaseName(_ url: URL) -> String {
        let n = url.lastPathComponent
        for c in [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.z", ".tar.lz", ".tar.lzma"] where n.lowercased().hasSuffix(c) { return String(n.dropLast(c.count)) }
        return (n as NSString).deletingPathExtension
    }

    /// Alt+F9: rozbalí celé archivy do vybraného adresáře.
    func unpackArchives() {
        let archives = selectedArchives()
        guard !archives.isEmpty else { Dialogs.error("Rozbalit archiv", "Vyberte archiv (zip, tar.gz, 7z, rar …)."); return }
        guard requireLocalTarget() else { return }
        let first = archives[0]
        let initial = archives.count == 1 ? target.path.appendingPathComponent(Self.archiveBaseName(first)).path : target.path.path + "/"
        guard let text = Dialogs.prompt(title: archives.count == 1 ? "Rozbalit „\(first.lastPathComponent)“" : "Rozbalit \(archives.count) archivů",
                                        message: archives.count == 1 ? "Cílový adresář:" : "Cílový adresář (každý archiv do vlastní složky):",
                                        initial: initial, ok: "Rozbalit"),
              let base = resolveDirectory(text, base: target.path) else { return }
        let single = archives.count == 1
        jobs.enqueue(title: "Rozbalit \(single ? first.lastPathComponent : "\(archives.count) archivů")", work: { control, progress in
            var total = OperationReport()
            for a in archives {
                guard !control.isCancelled else { total.cancelled = true; break }
                let dest = single ? base : base.appendingPathComponent(Self.archiveBaseName(a))
                do {
                    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                    let r = try ArchiveFileSystem(archiveURL: a).extractAll(to: dest, policy: .overwrite, control: control, progress: progress)
                    total.succeeded += r.succeeded; total.skipped += r.skipped; total.failures += r.failures; total.cancelled = r.cancelled
                } catch { total.failures.append(.init(url: a, message: error.localizedDescription)) }
            }
            return total
        }, onFinish: { [weak self] r in self?.finish(r, success: "Rozbaleno") })
    }

    /// Test integrity archivu (přečte všechna data).
    func testArchives() {
        let archives = selectedArchives()
        guard !archives.isEmpty else { Dialogs.error("Test archivu", "Vyberte archiv."); return }
        jobs.enqueue(title: "Test archivu \(archives.count == 1 ? archives[0].lastPathComponent : "(\(archives.count))")", work: { control, progress in
            var total = OperationReport()
            for a in archives {
                do {
                    let r = try ArchiveFileSystem(archiveURL: a).test(control: control, progress: progress)
                    total.succeeded += r.succeeded; total.failures += r.failures; total.cancelled = r.cancelled
                } catch { total.failures.append(.init(url: a, message: error.localizedDescription)) }
                if control.isCancelled { break }
            }
            return total
        }, onFinish: { [weak self] r in
            guard let self else { return }
            if r.cancelled { self.status = "Test archivu zrušen"; return }
            if r.failures.isEmpty { Dialogs.error("Test archivu", "Archiv je v pořádku (\(r.succeeded) souborů)."); self.status = "Archiv je v pořádku" }
            else { Dialogs.error("Archiv je poškozený", r.failures.prefix(10).map { "\($0.url.lastPathComponent): \($0.message)" }.joined(separator: "\n")) }
        })
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
        if source.insideArchive { deleteFromArchive(); return }
        if source.remote != nil { deleteFromRemote(); return }
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

    func finish(_ report: OperationReport, success: String) {
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
        if source.insideArchive { renameInArchive(); return }
        if source.remote != nil { renameOnRemote(); return }
        guard let e = source.targets.first, source.targets.count == 1 else { return }
        guard let name = Dialogs.prompt(title: "Přejmenovat", message: "Nový název:", initial: e.name, ok: "Přejmenovat") else { return }
        do { let new = try ops.rename(e.url, to: name); source.unmarkAll(); reloadAll(); source.reload(select: new) }
        catch { Dialogs.error("Přejmenování selhalo", error.localizedDescription) }
    }

    func makeDirectory() {
        if source.insideArchive { makeDirectoryInArchive(); return }
        if source.remote != nil { makeDirectoryOnRemote(); return }
        guard let name = Dialogs.prompt(title: "Nový adresář", message: "Název (lze i vnořený a/b/c):", initial: "", ok: "Vytvořit") else { return }
        do { let new = try ops.makeDirectory(name, in: source.path); reloadAll(); source.reload(select: new) }
        catch { Dialogs.error("Vytvoření adresáře selhalo", error.localizedDescription) }
    }

    func newFile() {
        guard requireLocal() else { return }
        guard let name = Dialogs.prompt(title: "Nový soubor", message: "Název:", initial: "", ok: "Vytvořit") else { return }
        do { let new = try ops.makeFile(named: name, in: source.path); reloadAll(); source.reload(select: new); openInEditor(new) }
        catch { Dialogs.error("Vytvoření souboru selhalo", error.localizedDescription) }
    }

    func search() {
        guard requireLocal() else { return }
        SearchWindow.show(root: source.path) { [weak self] url, inner in
            guard let self else { return }
            if let inner {
                // nález uvnitř archivu: vstoupit do archivu a nastavit se na soubor
                self.source.navigateLocal(url.deletingLastPathComponent(), select: url)
                if self.source.enterArchive(url) {
                    let dir = (("/" + inner) as NSString).deletingLastPathComponent
                    self.source.navigate(to: URL(fileURLWithPath: dir), select: URL(fileURLWithPath: "/" + inner))
                }
            } else {
                self.source.navigateLocal(url.deletingLastPathComponent(), select: url)
            }
            NSApp.windows.first { $0.isVisible && $0.title == "macTC" }?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: Prohlížení a editace

    func view() {
        guard let e = source.targets.first, !e.isDirectory else { return }
        if source.insideArchive { if let tmp = extractToTemp(e.url) { ListerWindow.show(tmp) }; return }
        if source.remote != nil { withRemoteFile(e) { ListerWindow.show($0) }; return }
        ListerWindow.show(e.url)
    }

    func edit() {
        guard let e = source.targets.first, !e.isDirectory else { return }
        if source.insideArchive { if let tmp = extractToTemp(e.url) { openInEditor(tmp) }; return }
        if source.remote != nil { withRemoteFile(e) { [weak self] in self?.openInEditor($0) }; return }
        openInEditor(e.url)
    }

    func openInEditor(_ url: URL) {
        let editor = URL(fileURLWithPath: settings.editorApp)
        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
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
        guard requireLocal() else { return }
        var o = SyncOptions(); o.recursive = false; o.includeHidden = showHidden
        let l = left.active, r = right.active
        let items = DirectoryComparer.compare(left: l.path, right: r.path, options: o)
        l.setMarks(Set(items.filter { $0.state == .onlyLeft || $0.state == .leftNewer || $0.state == .different }.compactMap { $0.left?.url }))
        r.setMarks(Set(items.filter { $0.state == .onlyRight || $0.state == .rightNewer || $0.state == .different }.compactMap { $0.right?.url }))
        status = "Porovnání adresářů: \(items.filter { $0.state != .same }.count) rozdílů"
    }

    func synchronize() {
        guard requireLocal() else { return }
        SyncWindow.show(left: left.active.path, right: right.active.path, jobs: jobs) { [weak self] in self?.reloadAll() }
    }

    // MARK: Duplicity a kódování

    func findDuplicates() {
        guard requireLocal() else { return }
        DuplicatesWindow.show(root: source.path, goTo: { [weak self] url in
            guard let self else { return }
            self.source.navigateLocal(url.deletingLastPathComponent(), select: url)
        }, onChange: { [weak self] in self?.reloadAll() })
    }

    func encodeFiles() {
        guard requireLocal(), requireLocalTarget() else { return }
        let files = source.targets.filter { !$0.isDirectory }
        guard !files.isEmpty else { return }
        let kinds = FileEncoding.allCases
        guard let i = Dialogs.choose(title: "Kódovat soubory", message: "Formát (výsledek do \(target.path.path)):", options: kinds.map(\.rawValue), ok: "Kódovat") else { return }
        let kind = kinds[i], dir = target.path
        var errors: [String] = []
        for f in files {
            do {
                let data = try Data(contentsOf: f.url)
                let out = dir.appendingPathComponent(f.name + "." + kind.fileExtension)
                guard !FileManager.default.fileExists(atPath: out.path) else { errors.append("\(out.lastPathComponent): již existuje"); continue }
                try TextCodecs.encode(data, as: kind, fileName: f.name, mode: f.permissions).write(to: out, atomically: true, encoding: .utf8)
            } catch { errors.append("\(f.name): \(error.localizedDescription)") }
        }
        reloadAll()
        if !errors.isEmpty { Dialogs.error("Některé soubory se nepodařilo zakódovat", errors.prefix(10).joined(separator: "\n")) }
    }

    func decodeFiles() {
        guard requireLocal(), requireLocalTarget() else { return }
        let files = source.targets.filter { !$0.isDirectory }
        guard !files.isEmpty else { return }
        let dir = target.path
        var errors: [String] = []
        for f in files {
            let kind = FileEncoding.from(fileName: f.name)
            guard let kind, let raw = try? Data(contentsOf: f.url) else { errors.append("\(f.name): neznámá přípona (.uue, .xxe, .b64)"); continue }
            guard let result = TextCodecs.decode(TextDecoding.decode(raw).text, as: kind) else { errors.append("\(f.name): neplatná data"); continue }
            let name = result.name ?? (f.name as NSString).deletingPathExtension
            let out = dir.appendingPathComponent((name as NSString).lastPathComponent)
            guard !FileManager.default.fileExists(atPath: out.path) else { errors.append("\(out.lastPathComponent): již existuje"); continue }
            do { try result.data.write(to: out) } catch { errors.append("\(f.name): \(error.localizedDescription)") }
        }
        reloadAll()
        if !errors.isEmpty { Dialogs.error("Některé soubory se nepodařilo dekódovat", errors.prefix(10).joined(separator: "\n")) }
    }

    // MARK: Nástroje

    func multiRename() {
        guard requireLocal() else { return }
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
        guard requireLocal() else { return }
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
        guard requireLocal() else { return }
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
        guard requireLocal() else { return }
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
        guard requireLocal(), requireLocalTarget() else { return }
        guard let e = source.targets.first, !e.isDirectory, source.targets.count == 1 else { return }
        guard let t = Dialogs.prompt(title: "Rozdělit „\(e.name)“", message: "Velikost jedné části v MB (do \(target.path.path)):", initial: "100", ok: "Rozdělit"),
              let mb = Double(t.replacingOccurrences(of: ",", with: ".")), mb > 0 else { return }
        let size = Int64(mb * 1_048_576), url = e.url, dir = target.path
        jobs.enqueue(title: "Rozdělit \(e.name)", work: { control, progress in
            FileSplitter.split(url, partSize: size, into: dir, control: control, progress: progress)
        }, onFinish: { [weak self] r in self?.finish(r, success: "Vytvořeno částí") })
    }

    func combineFiles() {
        guard requireLocal(), requireLocalTarget() else { return }
        guard let e = source.targets.first, e.name.hasSuffix(".001") else { Dialogs.error("Spojit soubory", "Nastavte kurzor na první část (název.001)."); return }
        let url = e.url, dir = target.path
        guard Dialogs.confirm(title: "Spojit části", message: "Výsledek bude uložen do \(dir.path).", ok: "Spojit") else { return }
        jobs.enqueue(title: "Spojit \(e.name)", work: { control, progress in
            FileSplitter.combine(first: url, into: dir, control: control, progress: progress)
        }, onFinish: { [weak self] r in self?.finish(r, success: "Spojeno") })
    }

    func makeLink(hard: Bool) {
        guard requireLocal(), requireLocalTarget() else { return }
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
