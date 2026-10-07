import AppKit
import SwiftUI
import TCCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ContentColumnRegistry.shared.register(BuiltinContentColumns())
        PluginHost.shared.reload()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Ladicí přepínač: macTC --lister <soubor> otevře rovnou Lister.
        if let i = CommandLine.arguments.firstIndex(of: "--lister"), i + 1 < CommandLine.arguments.count {
            ListerWindow.show(URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
        if let i = CommandLine.arguments.firstIndex(of: "--thumbs"), i + 1 < CommandLine.arguments.count {   // ladění: náhledy v adresáři
            AppModel.shared.source.navigate(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            AppModel.shared.source.viewMode = .thumbnails
        }
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--compare"), i + 2 < args.count {           // ladění: porovnání dvou souborů
            FileCompareWindow.show(URL(fileURLWithPath: args[i + 1]), URL(fileURLWithPath: args[i + 2]))
        }
        if let i = args.firstIndex(of: "--sync"), i + 2 < args.count {              // ladění: synchronizace dvou adresářů
            SyncWindow.show(left: URL(fileURLWithPath: args[i + 1]), right: URL(fileURLWithPath: args[i + 2]), jobs: AppModel.shared.jobs) {}
        }
        if let i = CommandLine.arguments.firstIndex(of: "--archive"), i + 1 < CommandLine.arguments.count {     // ladění: vstup do archivu
            let a = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            AppModel.shared.source.navigate(to: a.deletingLastPathComponent(), select: a)
            AppModel.shared.source.enterArchive(a)
        }
        if let i = CommandLine.arguments.firstIndex(of: "--ftp-selftest"), i + 2 < CommandLine.arguments.count {   // ladění: připojení k testovacímu FTP
            let port = Int(CommandLine.arguments[i + 1]) ?? 21, out = CommandLine.arguments[i + 2]
            let m = AppModel.shared
            m.connectFTP(SavedConnection(name: "selftest", kind: .ftp, host: "127.0.0.1", port: port, user: "tester"), "secret")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let t = m.source
                let text = "remote=\(t.remote != nil)\npath=\(t.path.path)\ndisplay=\(t.displayPath)\nentries=\(t.entries.map(\.name).joined(separator: ","))\nerror=\(t.error ?? "-")\n"
                try? text.write(toFile: out, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--sftp-selftest"), i + 3 < CommandLine.arguments.count {   // ladění: SFTP na localhostu s klíčem
            let port = Int(CommandLine.arguments[i + 1]) ?? 22, key = CommandLine.arguments[i + 2], out = CommandLine.arguments[i + 3]
            let m = AppModel.shared
            m.connectSFTP(SavedConnection(name: "selftest", kind: .sftp, host: "127.0.0.1", port: port, user: NSUserName(), path: "", identityFile: key), "")
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                let t = m.source
                let text = "remote=\(t.remote != nil)\npath=\(t.path.path)\ndisplay=\(t.displayPath)\nentries=\(t.entries.prefix(5).map(\.name).joined(separator: ","))\nerror=\(t.error ?? "-")\n"
                try? text.write(toFile: out, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--mode"), i + 1 < CommandLine.arguments.count {      // ladění: režim zobrazení
            let parts = CommandLine.arguments[i + 1].split(separator: "|").map(String.init)
            AppModel.shared.source.viewMode = ViewMode(rawValue: parts[0]) ?? .full
            if parts.count > 1 { AppModel.shared.source.columns = ColumnSet.parse(parts[1].replacingOccurrences(of: "+", with: ",")) }
            if parts.count > 2 { AppModel.shared.source.navigate(to: URL(fileURLWithPath: parts[2])) }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--lang"), i + 1 < CommandLine.arguments.count {         // ladění: jazyk (ukládá se do nastavení)
            AppModel.shared.settings.language = CommandLine.arguments[i + 1]
        }
        if let i = CommandLine.arguments.firstIndex(of: "--terminal-selftest"), i + 1 < CommandLine.arguments.count {   // ladění: příkaz v terminálu
            let out = CommandLine.arguments[i + 1]
            TerminalWindow.show(directory: FileManager.default.homeDirectoryForCurrentUser)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                TerminalWindow.latest?.sendDebug("echo mactc-pty-$((20+22)); pwd; tty\r")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                try? (TerminalWindow.latest?.transcript ?? "(žádné okno)").write(toFile: out, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--rename-demo"), i + 1 < CommandLine.arguments.count {   // ladění: F2 v adresáři
            let m = AppModel.shared
            m.source.navigate(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { m.source.moveCursor(to: 1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { m.rename() }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--properties-demo"), i + 1 < CommandLine.arguments.count {   // ladění: dialog Vlastnosti
            let u = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            if let e = try? LocalFileSystem().stat(u) { DispatchQueue.main.async { _ = PropertiesDialog(entries: [e]).run() } }
        }
        if CommandLine.arguments.contains("--settings") { AppModel.shared.perform("cm_settings") }     // ladění
        if CommandLine.arguments.contains("--search") { AppModel.shared.search() }
        if CommandLine.arguments.contains("--demo-job") {      // ladění: simulované úlohy ve frontě
            for n in 1...2 {
                AppModel.shared.jobs.enqueue(title: "Kopírovat demo \(n)", work: { control, progress in
                    var p = TransferProgress(); p.bytesTotal = 100_000_000; p.filesTotal = 10
                    for i in 1...100 {
                        guard control.checkpoint() else { break }
                        Thread.sleep(forTimeInterval: 0.08)
                        p.bytesDone = Int64(i) * 1_000_000; p.filesDone = i / 10; p.current = "soubor-\(i).bin"; progress(p)
                    }
                    return OperationReport()
                }, onFinish: { _ in })
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct MacTCApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        WindowGroup("macTC") {
            ContentView(model: model)
        }
        .defaultSize(width: 1400, height: 800)
        .commands { TCCommands(model: model) }
    }
}

struct TCCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("Nový tab")) { model.group(model.activeSide).newTab() }.keyboardShortcut("t")
        }
        CommandGroup(replacing: .saveItem) {
            Button(L("Zavřít tab")) { model.group(model.activeSide).closeActiveTab() }.keyboardShortcut("w")
        }
        CommandMenu(L("Soubor")) {
            Button(L("Otevřít")) { model.open() }.keyboardShortcut("o")
            Button(L("Hledat soubory…")) { model.search() }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button(L("Přejmenovat…")) { model.rename() }
            Button(L("Nový adresář…")) { model.makeDirectory() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button(L("Nový soubor…")) { model.newFile() }
            Divider()
            Button(L("Kopírovat…")) { model.transfer(.copy) }
            Button(L("Přesunout…")) { model.transfer(.move) }
            Button(L("Smazat…")) { model.delete(permanent: false) }.keyboardShortcut(.delete, modifiers: .command)
            Button(L("Smazat trvale…")) { model.delete(permanent: true) }
            Divider()
            Toggle(L("Ověřovat kopie (SHA-256)"), isOn: Binding(get: { model.verifyCopies }, set: { model.verifyCopies = $0 }))
        }
        CommandMenu(L("Porovnání")) {
            Button(L("Porovnat soubory podle obsahu…")) { model.compareFiles() }.keyboardShortcut("c", modifiers: [.control, .shift])
            Button(L("Porovnat adresáře (označit rozdíly)")) { model.compareDirectories() }.keyboardShortcut("d", modifiers: [.control, .shift])
            Button(L("Synchronizovat adresáře…")) { model.synchronize() }.keyboardShortcut("s", modifiers: [.control, .shift])
        }
        CommandMenu("Start") {
            ForEach(model.startMenu) { item in
                Button(L(item.title)) { model.run(command: item.command, parameters: item.parameters) }
            }
            if !model.userCommands.isEmpty {
                Divider()
                ForEach(model.userCommands) { u in Button(u.title) { model.runUser(u) } }
            }
        }
        CommandMenu(L("Nástroje")) {
            Button(L("Nastavení…")) { model.perform("cm_settings") }.keyboardShortcut(",")
            Button(L("Terminál")) { model.perform("cm_terminal") }.keyboardShortcut("t", modifiers: [.command, .option])
            Button(L("Importovat nastavení z Total Commanderu…")) { model.importFromTotalCommander() }
            Divider()
            Button(L("Hromadné přejmenování…")) { model.multiRename() }.keyboardShortcut("m", modifiers: .control)
            Divider()
            Button(L("Vlastnosti…")) { model.properties() }.keyboardShortcut(.return, modifiers: .option)
            Divider()
            Button(L("Kontrolní součty…")) { model.checksums() }
            Button(L("Ověřit kontrolní součty ze souboru")) { model.verifyChecksums() }
            Divider()
            Button(L("Zabalit do archivu…")) { model.packFiles() }
            Button(L("Rozbalit archiv…")) { model.unpackArchives() }
            Button(L("Otestovat archiv")) { model.testArchives() }
            Divider()
            Button(L("Najít duplicitní soubory…")) { model.findDuplicates() }
            Divider()
            Button(L("Kódovat soubory (MIME, UUE, XXE) do druhého panelu…")) { model.encodeFiles() }
            Button(L("Dekódovat soubory do druhého panelu…")) { model.decodeFiles() }
            Divider()
            Button(L("Rozdělit soubor…")) { model.splitFile() }
            Button(L("Spojit soubory (.001)…")) { model.combineFiles() }
            Divider()
            Button(L("Symbolický odkaz do druhého panelu…")) { model.makeLink(hard: false) }
            Button(L("Pevný odkaz do druhého panelu…")) { model.makeLink(hard: true) }
        }
        CommandMenu(L("Označit")) {
            Button(L("Označit vše")) { model.source.markAll() }.keyboardShortcut("a")
            Button(L("Zrušit označení")) { model.source.unmarkAll() }.keyboardShortcut("a", modifiers: [.command, .shift])
            Button(L("Invertovat označení")) { model.source.invertMarks() }
            Button(L("Označit podle masky…")) { model.markByMask(on: true) }
            Button(L("Odznačit podle masky…")) { model.markByMask(on: false) }
            Button(L("Označit stejnou příponu")) { model.source.markSameExtension() }.keyboardShortcut("e", modifiers: [.command, .shift])
            Button(L("Uložit výběr")) { model.source.saveSelection() }
            Button(L("Obnovit výběr")) { model.source.restoreSelection() }
            Divider()
            Button(L("Spočítat velikosti adresářů")) { model.source.computeAllDirSizes() }
        }
        CommandMenu(L("Síť")) {
            Button(L("Připojit k serveru…")) { model.connectToServer() }.keyboardShortcut("k")
            Button(L("Odpojit panel od serveru")) { model.disconnect() }.keyboardShortcut("k", modifiers: [.command, .shift])
            if !model.connections.items.isEmpty {
                Divider()
                ForEach(model.connections.items) { c in Button("\(c.name)  (\(c.kind.rawValue))") { model.connect(saved: c) } }
                Divider()
                Menu(L("Zapomenout připojení")) {
                    ForEach(model.connections.items) { c in Button(c.name) { model.forget(c) } }
                }
            }
        }
        CommandMenu(L("Karty")) {
            Button(L("Zamknout / odemknout kartu")) { model.perform("cm_locktab") }
            Divider()
            Button(L("Uložit sadu karet…")) { model.saveFavoriteTabs() }
            if !model.favoriteTabs.isEmpty {
                Divider()
                ForEach(model.favoriteTabs) { set in Button(set.name) { model.loadFavoriteTabs(set) } }
                Divider()
                Menu(L("Smazat sadu")) { ForEach(model.favoriteTabs) { set in Button(set.name) { model.deleteFavoriteTabs(set) } } }
            }
        }
        CommandMenu(L("Oblíbené")) {
            Button(L("Přidat aktuální adresář")) { model.hotlist.add(model.source.persistentPath) }.keyboardShortcut("d")
            Divider()
            ForEach(model.hotlist.entries) { e in
                Button(e.name) { model.goTo(URL(fileURLWithPath: e.path)) }
            }
            if !model.hotlist.entries.isEmpty {
                Divider()
                Menu(L("Odebrat")) {
                    ForEach(model.hotlist.entries) { e in Button(e.name) { model.hotlist.remove(e) } }
                }
            }
        }
        CommandMenu(L("Historie")) {
            ForEach(Array(model.source.recent.prefix(25)), id: \.self) { url in
                Button(url.path) { model.goTo(url) }
            }
        }
        CommandMenu(L("Zobrazení")) {
            Toggle(L("Skryté soubory"), isOn: Binding(get: { model.showHidden }, set: { model.showHidden = $0 }))
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button(L("Plný režim")) { model.source.viewMode = .full }.keyboardShortcut("1", modifiers: .control)
            Button(L("Stručný režim")) { model.source.viewMode = .brief }.keyboardShortcut("2", modifiers: .control)
            Button(L("Náhledy")) { model.source.viewMode = .thumbnails }.keyboardShortcut("3", modifiers: .control)
            Button(L("Strom adresářů")) { model.source.viewMode = .tree }.keyboardShortcut("4", modifiers: .control)
            Menu(L("Sloupce (plný režim)")) {
                ForEach(model.settings.columnSets) { cs in
                    Button(cs.name) { model.source.viewMode = .full; model.source.columns = cs.columns }
                }
            }
            Button(L("Panely nad sebou / vedle sebe")) { model.perform("cm_layout") }
            Button("Quick View (druhý panel)") { model.quickViewOn.toggle() }.keyboardShortcut("q", modifiers: .control)
            Divider()
            Button(L("Obnovit")) { model.reloadAll() }.keyboardShortcut("r")
            Button("Branch view (všechny podadresáře)") { model.toggleBranchView() }.keyboardShortcut("b")
            Button(L("Rychlý filtr")) { model.toggleFilter() }.keyboardShortcut("f")
            Divider()
            Button(L("Nadřazený adresář")) { model.source.goUp() }.keyboardShortcut(.upArrow, modifiers: .command)
            Button(L("Zpět")) { model.source.goBack() }.keyboardShortcut("[")
            Button(L("Vpřed")) { model.source.goForward() }.keyboardShortcut("]")
            Divider()
            Button(L("Cíl = zdroj")) { model.targetEqualsSource() }.keyboardShortcut("=")
            Button(L("Prohodit panely")) { model.swapPanels() }.keyboardShortcut("u")
            Button(L("Další tab")) { model.group(model.activeSide).nextTab() }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button(L("Předchozí tab")) { model.group(model.activeSide).previousTab() }.keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }
}
