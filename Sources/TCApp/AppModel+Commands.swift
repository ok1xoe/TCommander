import AppKit
import TCCore

enum DefaultCustomization {
    static let buttonBar: [ButtonBarItem] = [
        ButtonBarItem(title: "Zobrazit", icon: "eye", command: "cm_view"),
        ButtonBarItem(title: "Editovat", icon: "pencil", command: "cm_edit"),
        ButtonBarItem(title: "Kopírovat", icon: "doc.on.doc", command: "cm_copy"),
        ButtonBarItem(title: "Přesunout", icon: "arrow.right.circle", command: "cm_move"),
        ButtonBarItem(title: "Nový adresář", icon: "folder.badge.plus", command: "cm_mkdir"),
        ButtonBarItem(title: "Smazat", icon: "trash", command: "cm_delete"),
        ButtonBarItem(title: "Hledat", icon: "magnifyingglass", command: "cm_search"),
        ButtonBarItem(title: "Hromadně", icon: "textformat.abc", command: "cm_multirename"),
        ButtonBarItem(title: "Porovnat", icon: "rectangle.split.2x1", command: "cm_comparefiles"),
        ButtonBarItem(title: "Synchronizovat", icon: "arrow.triangle.2.circlepath", command: "cm_sync"),
        ButtonBarItem(title: "Server", icon: "network", command: "cm_connect"),
        ButtonBarItem(title: "Nastavení", icon: "gearshape", command: "cm_settings"),
    ]

    static let startMenu: [ButtonBarItem] = [
        ButtonBarItem(title: "Terminál zde", icon: "terminal", command: "open", parameters: "-a Terminal %P"),
        ButtonBarItem(title: "Monitor aktivity", icon: "chart.bar", command: "open", parameters: "-a 'Activity Monitor'"),
        ButtonBarItem(title: "Systémová nastavení", icon: "gearshape.2", command: "open", parameters: "-a 'System Settings'"),
        ButtonBarItem(title: "Zobrazit ve Finderu", icon: "folder", command: "open", parameters: "-R %F"),
    ]
}

extension AppModel {
    // MARK: Registr příkazů

    /// Provede příkaz podle identifikátoru (cm_*); stejná cesta se používá pro zkratky, tlačítka i menu.
    func perform(_ id: String) {
        switch id {
        case "cm_rename": rename()
        case "cm_view": view()
        case "cm_edit": edit()
        case "cm_newfile": newFile()
        case "cm_copy": transfer(.copy)
        case "cm_pack": packFiles()
        case "cm_move": transfer(.move)
        case "cm_mkdir": makeDirectory()
        case "cm_search": search()
        case "cm_delete": delete(permanent: false)
        case "cm_deleteperm": delete(permanent: true)
        case "cm_unpack": unpackArchives()
        case "cm_properties": properties()
        case "cm_open": open()
        case "cm_multirename": multiRename()
        case "cm_checksums": checksums()
        case "cm_split": splitFile()
        case "cm_combine": combineFiles()
        case "cm_duplicates": findDuplicates()
        case "cm_encode": encodeFiles()
        case "cm_decode": decodeFiles()
        case "cm_markall": source.markAll()
        case "cm_unmarkall": source.unmarkAll()
        case "cm_invertmarks": source.invertMarks()
        case "cm_markmask": markByMask(on: true)
        case "cm_unmarkmask": markByMask(on: false)
        case "cm_markext": source.markSameExtension()
        case "cm_savesel": source.saveSelection()
        case "cm_restoresel": source.restoreSelection()
        case "cm_switchpanel": if !quickViewOn { activeSide = activeSide.other }
        case "cm_swappanels": swapPanels()
        case "cm_targetsource": targetEqualsSource()
        case "cm_goup": source.goUp()
        case "cm_goback": source.goBack()
        case "cm_goforward": source.goForward()
        case "cm_reload": reloadAll()
        case "cm_branchview": toggleBranchView()
        case "cm_quickfilter": toggleFilter()
        case "cm_quickview": quickViewOn.toggle()
        case "cm_viewfull": source.viewMode = .full
        case "cm_viewbrief": source.viewMode = .brief
        case "cm_viewthumbs": source.viewMode = .thumbnails
        case "cm_hidden": showHidden.toggle()
        case "cm_newtab": group(activeSide).newTab()
        case "cm_closetab": group(activeSide).closeActiveTab()
        case "cm_nexttab": group(activeSide).nextTab()
        case "cm_prevtab": group(activeSide).previousTab()
        case "cm_addhotlist": hotlist.add(source.persistentPath)
        case "cm_comparefiles": compareFiles()
        case "cm_comparedirs": compareDirectories()
        case "cm_sync": synchronize()
        case "cm_connect": connectToServer()
        case "cm_disconnect": disconnect()
        case "cm_settings": SettingsWindow.show(self)
        case "cm_cmdhistory": insertNameIntoCommandLine()
        default:
            if !performExtended(id) { Dialogs.error("Příkaz", "Neznámý příkaz „\(id)“.") }
        }
    }

    // MARK: Spouštění příkazů a programů

    /// Tlačítko, položka Start menu: interní příkaz (cm_*), uživatelský (em_*) nebo shellový příkaz.
    func run(command: String, parameters: String = "") {
        if command.hasPrefix("cm_") { perform(command); return }
        if command.hasPrefix("em_"), let u = userCommands.first(where: { $0.name == command }) { runUser(u); return }
        runShell(command, parameters, startPath: nil, terminal: false, title: command)
    }

    func runUser(_ u: UserCommand) {
        if u.command.hasPrefix("cm_") { perform(u.command); return }
        runShell(u.command, u.parameters, startPath: u.startPath, terminal: u.runInTerminal, title: u.title)
    }

    func runAssociation(_ a: FileAssociation) {
        runShell(a.command, a.parameters.isEmpty ? "%F" : a.parameters, startPath: nil, terminal: false, title: a.command, quiet: true)
    }

    func placeholderContext(needsList: Bool) -> PlaceholderContext {
        let targets = source.targets
        var listFile: String?
        if needsList {
            let f = FileManager.default.temporaryDirectory.appendingPathComponent("macTC-list-\(UUID().uuidString).lst")
            try? targets.map(\.url.path).joined(separator: "\n").write(to: f, atomically: true, encoding: .utf8)
            listFile = f.path
        }
        return PlaceholderContext(sourcePath: source.persistentPath.path, targetPath: target.persistentPath.path,
                                  cursorName: source.cursorEntry.flatMap { $0.isParentLink ? nil : $0.name },
                                  selectedNames: targets.map(\.name), listFile: listFile)
    }

    /// Sestaví shellový příkaz (placeholdery %P %N %S %T %F %L se ošetří uvozovkami).
    func buildShellCommand(_ command: String, _ parameters: String) -> String {
        let needsList = (command + parameters).contains("%L")
        let ctx = placeholderContext(needsList: needsList)
        let base: String
        if command.hasSuffix(".app") {
            base = "open -a " + PlaceholderExpander.shellQuote(command)
            let p = PlaceholderExpander.expand(parameters.isEmpty ? "%F" : parameters, ctx)
            return base + " " + p
        }
        base = FileManager.default.fileExists(atPath: command) ? PlaceholderExpander.shellQuote(command) : PlaceholderExpander.expand(command, ctx)
        return base + " " + PlaceholderExpander.expand(parameters, ctx)
    }

    func runShell(_ command: String, _ parameters: String, startPath: String?, terminal: Bool, title: String, quiet: Bool = false) {
        let full = buildShellCommand(command, parameters).trimmingCharacters(in: .whitespaces)
        guard !full.isEmpty else { return }
        var dir = source.persistentPath
        if let sp = startPath, !sp.isEmpty {
            let expanded = PlaceholderExpander.expand(sp, placeholderContext(needsList: false), quote: false)
            dir = URL(fileURLWithPath: (expanded as NSString).expandingTildeInPath)
        }
        if terminal { openInTerminal(full, in: dir); return }
        busy = "Spouštím: \(title)…"
        Task {
            let r = await Task.detached { Shell.run(full, in: dir) }.value
            self.busy = nil
            self.reloadAll()
            if !quiet && (!r.output.isEmpty || r.status != 0) {
                let note = r.timedOut ? "\n\n(přerušeno po 60 s)" : (r.status != 0 ? "\n\n(návratový kód \(r.status))" : "")
                Dialogs.output(title: title, text: r.output + note)
            } else if quiet && r.status != 0 {
                Dialogs.error("Spuštění selhalo", r.output.isEmpty ? "Návratový kód \(r.status)" : r.output)
            }
        }
    }

    /// Spustí příkaz v okně Terminálu (přes dočasný .command skript).
    func openInTerminal(_ command: String, in dir: URL) {
        let folder = ArchiveFileSystem.temporaryRoot.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = folder.appendingPathComponent("run.command")
        let text = "#!/bin/zsh\ncd \(PlaceholderExpander.shellQuote(dir.path))\n\(command)\necho\nread -k 1 \"?Hotovo – stiskněte klávesu…\"\n"
        try? text.write(to: script, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        NSWorkspace.shared.open([script], withApplicationAt: URL(fileURLWithPath: settings.terminalApp), configuration: NSWorkspace.OpenConfiguration())
    }

    /// Příkazy doplněné v dalších částech.
    func performExtended(_ id: String) -> Bool {
        switch id {
        case "cm_viewtree": source.viewMode = .tree
        case "cm_locktab": source.locked.toggle()
        case "cm_savetabs": saveFavoriteTabs()
        case "cm_layout": settings.panelsStacked.toggle()
        default: return false
        }
        return true
    }

    // MARK: Sady oblíbených karet

    func saveFavoriteTabs() {
        guard let name = Dialogs.prompt(title: "Uložit sadu karet", message: "Název sady (stejný název sadu nahradí):", initial: "", ok: "Uložit"),
              !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        func tabs(_ g: PanelGroup) -> [FavoriteTabSet.Tab] { g.tabs.map { .init(path: $0.persistentPath.path, locked: $0.locked) } }
        let n = name.trimmingCharacters(in: .whitespaces)
        let set = FavoriteTabSet(id: favoriteTabs.first { $0.name == n }?.id ?? UUID(), name: n, left: tabs(left), right: tabs(right),
                                 leftActive: left.activeIndex, rightActive: right.activeIndex)
        if let i = favoriteTabs.firstIndex(where: { $0.name == n }) { favoriteTabs[i] = set } else { favoriteTabs.append(set) }
        status = "Sada karet „\(n)“ uložena"
    }

    func loadFavoriteTabs(_ set: FavoriteTabSet) {
        func specs(_ t: [FavoriteTabSet.Tab]) -> [(path: URL, locked: Bool)] {
            t.map { (URL(fileURLWithPath: $0.path), $0.locked) }.filter { FileManager.default.fileExists(atPath: $0.0.path) }
        }
        left.replaceTabs(specs(set.left), active: set.leftActive, showHidden: showHidden)
        right.replaceTabs(specs(set.right), active: set.rightActive, showHidden: showHidden)
    }

    func deleteFavoriteTabs(_ set: FavoriteTabSet) { favoriteTabs.removeAll { $0.id == set.id } }
}
