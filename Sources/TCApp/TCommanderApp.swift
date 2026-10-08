import AppKit
import SwiftUI
import TCCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ContentColumnRegistry.shared.register(BuiltinContentColumns())
        WindowTranslator.install()
        PluginHost.shared.reload()
        AccessPrompt.launchFinished()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // Ladicí přepínač: TCommander --lister <soubor> otevře rovnou Lister.
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
            if let e = args.firstIndex(of: "--compare-edit"), e + 1 < args.count {      // ladění: 0 = psaní, 1 = přepočet
                let phase = Int(args[e + 1]) ?? 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { FileCompareWindow.latest?.debugEditDemo(0) }
                if phase > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { FileCompareWindow.latest?.debugEditDemo(1) } }
            }
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
                TerminalWindow.latest?.sendDebug("echo tcommander-pty-$((20+22)); env | grep -i CLICOLOR; ls -l /bin | head -4; stty size\r")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                try? ((TerminalWindow.latest?.transcript ?? "(žádné okno)") + "\n[" + (TerminalWindow.latest?.styleSummary ?? "") + "]").write(toFile: out, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--mount-selftest"), i + 2 < CommandLine.arguments.count {      // ladění: připojení svazku (WebDAV/SMB), zápis a čtení souboru
            let url = URL(string: CommandLine.arguments[i + 1])!, out = CommandLine.arguments[i + 2]
            Task {
                var report = ""
                do {
                    let mp = try await NetworkMounts.mount(url, user: nil, password: nil)
                    report += "mount: \(mp.path)\n"
                    let names = (try? FileManager.default.contentsOfDirectory(atPath: mp.path)) ?? []
                    report += "list: \(names.sorted())\n"
                    let f = mp.appendingPathComponent("tcommander-written.txt")
                    try "zapsáno z TCommander".write(to: f, atomically: false, encoding: .utf8)
                    report += "readback: \((try? String(contentsOf: f, encoding: .utf8)) ?? "CHYBA")\n"
                    try? FileManager.default.removeItem(at: f)
                } catch { report += "error: \(error.localizedDescription)\n" }
                try? report.write(toFile: out, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--dump-menu"), i + 1 < CommandLine.arguments.count {         // ladění: struktura hlavního menu do souboru
            let out = CommandLine.arguments[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                func dump(_ m: NSMenu, _ depth: Int) -> String {
                    m.items.map { item in
                        let key = item.keyEquivalent.isEmpty ? "" : "  [" + (item.keyEquivalentModifierMask.contains(.control) ? "⌃" : "") + (item.keyEquivalentModifierMask.contains(.shift) ? "⇧" : "") + (item.keyEquivalentModifierMask.contains(.option) ? "⌥" : "") + (item.keyEquivalentModifierMask.contains(.command) ? "⌘" : "") + item.keyEquivalent + "]"
                        let line = String(repeating: "  ", count: depth) + (item.isSeparatorItem ? "----" : item.title) + key + (item.isHidden ? " (skryto)" : "") + "\n"
                        return line + (item.submenu.map { dump($0, depth + 1) } ?? "")
                    }.joined()
                }
                try? (NSApp.mainMenu.map { dump($0, 0) } ?? "(bez menu)").write(toFile: out, atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--keys-demo"), i + 2 < CommandLine.arguments.count {         // ladění: PageDown/PageUp/End/Home v panelu
            let m = AppModel.shared
            m.source.navigate(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated {
                func find(_ v: NSView) -> KeyTableView? { if let t = v as? KeyTableView { return t }; for s in v.subviews { if let t = find(s) { return t } }; return nil }
                guard let w = NSApp.windows.first(where: { $0.contentView != nil && find($0.contentView!) != nil }), let table = find(w.contentView!) else {
                    try? "tabulka nenalezena".write(toFile: CommandLine.arguments[i + 2], atomically: true, encoding: .utf8); NSApp.terminate(nil); return
                }
                var log = "řádků \(m.source.entries.count), viditelných ≈ \(Int(table.visibleRect.height / table.rowHeight))\n"
                @MainActor func press(_ code: UInt16, _ name: String) {
                    let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
                    table.keyDown(with: e)
                    DispatchQueue.main.async { }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                    log += "\(name): kurzor \(m.source.cursor), vybraný řádek \(table.selectedRow), horní viditelný řádek \(table.row(at: NSPoint(x: 5, y: table.visibleRect.minY + 2)))\n"
                }
                press(121, "PageDown"); press(121, "PageDown"); press(116, "PageUp"); press(119, "End"); press(115, "Home")
                try? log.write(toFile: CommandLine.arguments[i + 2], atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            } }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--longpress-demo"), i + 2 < CommandLine.arguments.count {     // ladění: krátké a dlouhé pravé tlačítko nad adresářem
            let m = AppModel.shared
            m.source.navigate(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { MainActor.assumeIsolated {
                func find(_ v: NSView) -> KeyTableView? { if let t = v as? KeyTableView { return t }; for s in v.subviews { if let t = find(s) { return t } }; return nil }
                guard let w = NSApp.windows.first(where: { $0.contentView != nil && find($0.contentView!) != nil }), let table = find(w.contentView!),
                      let row = m.source.entries.firstIndex(where: { $0.isDirectory && !$0.isParentLink }) else {
                    try? "adresář v panelu nenalezen".write(toFile: CommandLine.arguments[i + 2], atomically: true, encoding: .utf8); NSApp.terminate(nil); return
                }
                let p = table.convert(NSPoint(x: 40, y: table.rect(ofRow: row).midY), to: nil)
                func event(_ t: NSEvent.EventType) -> NSEvent { NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)! }
                let tabsBefore = m.group(m.activeSide).tabs.count
                table.rightMouseDown(with: event(.rightMouseDown)); RunLoop.current.run(until: Date().addingTimeInterval(0.2)); table.rightMouseUp(with: event(.rightMouseUp))
                RunLoop.current.run(until: Date().addingTimeInterval(1.0))
                var log = "krátké kliknutí: dialog \(NSApp.modalWindow == nil ? "nezobrazen" : "ZOBRAZEN")\n"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    MainActor.assumeIsolated {
                        let alert = NSApp.modalWindow
                        let texts = alert?.contentView.map { v -> [String] in
                            func labels(_ v: NSView) -> [String] { (v as? NSTextField).map { [$0.stringValue] } ?? v.subviews.flatMap(labels) }
                            return labels(v) } ?? []
                        log += "dlouhé podržení: dialog \(alert == nil ? "NEZOBRAZEN" : "zobrazen") \(texts.filter { !$0.isEmpty })\n"
                        NSApp.abortModal()
                        log += "záložek před: \(tabsBefore), po zrušení: \(m.group(m.activeSide).tabs.count)\n"
                        try? log.write(toFile: CommandLine.arguments[i + 2], atomically: true, encoding: .utf8)
                        NSApp.terminate(nil)
                    }
                }
                table.rightMouseDown(with: event(.rightMouseDown))
            } }
        }
        // ladění / snímky obrazovky: --panel-left a:b:c  --panel-right d  --mode-left full  --mode-right thumbnails  --window-size 1440x900
        func panelArg(_ name: String) -> [URL] { CommandLine.arguments.firstIndex(of: name).flatMap { i in i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : nil }?.split(separator: ":").map { URL(fileURLWithPath: String($0)) } ?? [] }
        func modeArg(_ name: String) -> ViewMode? { CommandLine.arguments.firstIndex(of: name).flatMap { i in i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : nil }.flatMap { ViewMode(rawValue: $0) } }
        for (side, flag, modeFlag) in [(Side.left, "--panel-left", "--mode-left"), (Side.right, "--panel-right", "--mode-right")] {
            let paths = panelArg(flag)
            if !paths.isEmpty { AppModel.shared.group(side).replaceTabs(paths.map { ($0, false) }, active: 0, showHidden: false) }
            if let m = modeArg(modeFlag) { AppModel.shared.group(side).active.viewMode = m }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--window-size"), i + 1 < CommandLine.arguments.count {
            let wh = CommandLine.arguments[i + 1].split(separator: "x").compactMap { Double($0) }
            if wh.count == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    for w in NSApp.windows where w.isVisible && w.styleMask.contains(.titled) {
                        let screen = w.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
                        w.setFrame(NSRect(x: screen.minX + 40, y: screen.maxY - wh[1] - 40, width: wh[0], height: wh[1]), display: true)
                    }
                }
            }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--many-tabs"), i + 1 < CommandLine.arguments.count, let n = Int(CommandLine.arguments[i + 1]) {   // ladění: mnoho záložek
            let dirs = ["/usr/lib", "/usr/bin", "/usr/share", "/usr/local", "/Library", "/System", "/Applications", "/tmp", "/private/var", "/opt", "/usr/libexec", "/usr/sbin", "/bin", "/sbin", "/Users"]
            for k in 0..<n { AppModel.shared.group(.left).newTab(at: URL(fileURLWithPath: dirs[k % dirs.count])) }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--strip-demo"), i + 1 < CommandLine.arguments.count {      // ladění: kliknutí na šipky pásu záložek
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { MainActor.assumeIsolated {
                func all(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(all) }
                guard let root = NSApp.windows.first(where: { $0.contentView != nil })?.contentView else { return }
                let strips = all(root).compactMap { $0 as? StripView }
                var log = "pásů: \(strips.count)\n"
                for (n, strip) in strips.enumerated() {
                    let sv = all(strip).compactMap { $0 as? NSScrollView }.first
                    let btns = all(strip).compactMap { $0 as? NSButton }
                    func state() -> String { "x=\(Int(sv?.contentView.bounds.origin.x ?? -1)) doleva=\(btns.first { $0.toolTip == "Doleva" }.map { $0.isEnabled && !$0.isHidden } ?? false) doprava=\(btns.first { $0.toolTip == "Doprava" }.map { $0.isEnabled && !$0.isHidden } ?? false)" }
                    log += "pás \(n): \(state())\n"
                    btns.first { $0.toolTip == "Doleva" }?.performClick(nil); RunLoop.current.run(until: Date().addingTimeInterval(0.5)); log += "   po kliknutí doleva: \(state())\n"
                    btns.first { $0.toolTip == "Doprava" }?.performClick(nil); RunLoop.current.run(until: Date().addingTimeInterval(0.5)); log += "   po kliknutí doprava: \(state())\n"
                }
                try? log.write(toFile: CommandLine.arguments[i + 1], atomically: true, encoding: .utf8)
                NSApp.terminate(nil)
            } }
        }
        if let i = CommandLine.arguments.firstIndex(of: "--terminal-cmd"), i + 1 < CommandLine.arguments.count {      // ladění: otevře terminál a spustí příkaz (okno zůstane otevřené)
            let dir = CommandLine.arguments.firstIndex(of: "--terminal-dir").flatMap { d in d + 1 < CommandLine.arguments.count ? CommandLine.arguments[d + 1] : nil }
            TerminalWindow.show(directory: dir.map { URL(fileURLWithPath: $0) } ?? Sandbox.home)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { TerminalWindow.latest?.sendDebug(CommandLine.arguments[i + 1] + "\r") }
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
        if let i = CommandLine.arguments.firstIndex(of: "--help-page"), i + 1 < CommandLine.arguments.count { HelpWindow.show(page: CommandLine.arguments[i + 1]) }     // ladění
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

    /// Složka přetažená na ikonu aplikace nebo „Otevřít v…“: v sandboxu tím uživatel složku povolí; panel na ni přejde.
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                AccessManager.shared.grant(u)
                AppModel.shared.source.navigateLocal(u)
            } else {
                AccessManager.shared.grant(u.deletingLastPathComponent())
                AppModel.shared.source.navigateLocal(u.deletingLastPathComponent(), select: u)
            }
        }
    }
}

@main
struct TCommanderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("TCommander", id: "main") {          // jedno okno: událost „Otevřít“ (složka přetažená na ikonu) nesmí vytvářet další
            ContentView(model: model)
        }
        .defaultSize(width: 1400, height: 800)
        .commands { TCCommands(model: model) }
    }
}

/// Hlavní menu; kvůli omezení `CommandsBuilder` (nejvýš 10 položek najednou) rozdělené na dvě skupiny.
struct TCCommands: Commands {
    let model: AppModel

    var body: some Commands {
        TCCommandsFirst(model: model)
        TCCommandsSecond(model: model)
    }
}

struct TCCommandsFirst: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(L("TCommander Nápověda")) { HelpWindow.show() }.keyboardShortcut("?", modifiers: .command)
            Button(L("Klávesové zkratky")) { HelpWindow.show(page: "12-shortcuts.html") }
            Divider()
            Button(L("Webové stránky TCommanderu")) { NSWorkspace.shared.open(HelpWindow.siteURL) }
            Button(L("Zásady ochrany soukromí")) { HelpWindow.show(page: "privacy.html") }
            Button(L("Nahlásit chybu…")) { NSWorkspace.shared.open(HelpWindow.issuesURL) }
        }
        CommandGroup(replacing: .newItem) {
            Button(L("Nový tab")) { model.group(model.activeSide).newTab() }.keyboardShortcut("t")
        }
        CommandGroup(replacing: .saveItem) {
            Button(L("Zavřít tab")) { model.group(model.activeSide).closeActiveTab() }.keyboardShortcut("w")
        }
        CommandMenu(L("Soubor")) {
            Button(L("Otevřít")) { model.open() }.keyboardShortcut("o").hideable(model, "Soubor/Otevřít")
            Button(L("Hledat soubory…")) { model.search() }.keyboardShortcut("f", modifiers: [.command, .shift]).hideable(model, "Soubor/Hledat soubory…")
            Button(L("Přejmenovat…")) { model.rename() }.hideable(model, "Soubor/Přejmenovat…")
            Button(L("Nový adresář…")) { model.makeDirectory() }.keyboardShortcut("n", modifiers: [.command, .shift]).hideable(model, "Soubor/Nový adresář…")
            Button(L("Nový soubor…")) { model.newFile() }.hideable(model, "Soubor/Nový soubor…")
            Divider()
            Button(L("Kopírovat…")) { model.transfer(.copy) }.hideable(model, "Soubor/Kopírovat…")
            Button(L("Přesunout…")) { model.transfer(.move) }.hideable(model, "Soubor/Přesunout…")
            Button(L("Smazat…")) { model.delete(permanent: false) }.keyboardShortcut(.delete, modifiers: .command).hideable(model, "Soubor/Smazat…")
            Button(L("Smazat trvale…")) { model.delete(permanent: true) }.hideable(model, "Soubor/Smazat trvale…")
            Divider()
            Toggle(L("Ověřovat kopie (SHA-256)"), isOn: Binding(get: { model.verifyCopies }, set: { model.verifyCopies = $0 })).hideable(model, "Soubor/Ověřovat kopie (SHA-256)")
        }
        CommandMenu(L("Porovnání")) {
            Button(L("Porovnat soubory podle obsahu…")) { model.compareFiles() }.keyboardShortcut("c", modifiers: [.control, .shift]).hideable(model, "Porovnání/Porovnat soubory podle obsahu…")
            Button(L("Porovnat adresáře (označit rozdíly)")) { model.compareDirectories() }.keyboardShortcut("d", modifiers: [.control, .shift]).hideable(model, "Porovnání/Porovnat adresáře (označit rozdíly)")
            Button(L("Synchronizovat adresáře…")) { model.synchronize() }.keyboardShortcut("s", modifiers: [.control, .shift]).hideable(model, "Porovnání/Synchronizovat adresáře…")
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
        CommandMenu(model.mainMenu.customTitle.isEmpty ? L("Vlastní") : model.mainMenu.customTitle) {
            let tree = MenuNode.tree(from: model.mainMenu.customItems)
            if tree.isEmpty {
                Button(L("(prázdné – položky přidáte v Nastavení › Hlavní menu)")) {}.disabled(true)
            } else {
                CustomMenuContent(model: model, nodes: tree)
            }
        }
        CommandMenu(L("Nástroje")) {
            Button(L("Nastavení…")) { model.perform("cm_settings") }.keyboardShortcut(",").hideable(model, "Nástroje/Nastavení…")
            Button(L("Terminál")) { model.perform("cm_terminal") }.keyboardShortcut("t", modifiers: [.command, .option]).hideable(model, "Nástroje/Terminál")
            Button(L("Importovat nastavení z Total Commanderu…")) { model.importFromTotalCommander() }.hideable(model, "Nástroje/Importovat nastavení z Total Commanderu…")
            Divider()
            Button(L("Hromadné přejmenování…")) { model.multiRename() }.keyboardShortcut("m", modifiers: .control).hideable(model, "Nástroje/Hromadné přejmenování…")
            Divider()
            Button(L("Vlastnosti…")) { model.properties() }.keyboardShortcut(.return, modifiers: .option).hideable(model, "Nástroje/Vlastnosti…")
            Divider()
            Button(L("Kontrolní součty…")) { model.checksums() }.hideable(model, "Nástroje/Kontrolní součty…")
            Button(L("Ověřit kontrolní součty ze souboru")) { model.verifyChecksums() }.hideable(model, "Nástroje/Ověřit kontrolní součty ze souboru")
            Divider()
            Button(L("Zabalit do archivu…")) { model.packFiles() }.hideable(model, "Nástroje/Zabalit do archivu…")
            Button(L("Rozbalit archiv…")) { model.unpackArchives() }.hideable(model, "Nástroje/Rozbalit archiv…")
            Button(L("Otestovat archiv")) { model.testArchives() }.hideable(model, "Nástroje/Otestovat archiv")
            Divider()
            Button(L("Najít duplicitní soubory…")) { model.findDuplicates() }.hideable(model, "Nástroje/Najít duplicitní soubory…")
            Divider()
            Button(L("Kódovat soubory (MIME, UUE, XXE) do druhého panelu…")) { model.encodeFiles() }.hideable(model, "Nástroje/Kódovat soubory (MIME, UUE, XXE) do druhého panelu…")
            Button(L("Dekódovat soubory do druhého panelu…")) { model.decodeFiles() }.hideable(model, "Nástroje/Dekódovat soubory do druhého panelu…")
            Divider()
            Button(L("Rozdělit soubor…")) { model.splitFile() }.hideable(model, "Nástroje/Rozdělit soubor…")
            Button(L("Spojit soubory (.001)…")) { model.combineFiles() }.hideable(model, "Nástroje/Spojit soubory (.001)…")
            Divider()
            Button(L("Symbolický odkaz do druhého panelu…")) { model.makeLink(hard: false) }.hideable(model, "Nástroje/Symbolický odkaz do druhého panelu…")
            Button(L("Pevný odkaz do druhého panelu…")) { model.makeLink(hard: true) }.hideable(model, "Nástroje/Pevný odkaz do druhého panelu…")
        }
    }
}

struct TCCommandsSecond: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu(L("Označit")) {
            Button(L("Označit vše")) { model.source.markAll() }.keyboardShortcut("a").hideable(model, "Označit/Označit vše")
            Button(L("Zrušit označení")) { model.source.unmarkAll() }.keyboardShortcut("a", modifiers: [.command, .shift]).hideable(model, "Označit/Zrušit označení")
            Button(L("Invertovat označení")) { model.source.invertMarks() }.hideable(model, "Označit/Invertovat označení")
            Button(L("Označit podle masky…")) { model.markByMask(on: true) }.hideable(model, "Označit/Označit podle masky…")
            Button(L("Odznačit podle masky…")) { model.markByMask(on: false) }.hideable(model, "Označit/Odznačit podle masky…")
            Button(L("Označit stejnou příponu")) { model.source.markSameExtension() }.keyboardShortcut("e", modifiers: [.command, .shift]).hideable(model, "Označit/Označit stejnou příponu")
            Button(L("Uložit výběr")) { model.source.saveSelection() }.hideable(model, "Označit/Uložit výběr")
            Button(L("Obnovit výběr")) { model.source.restoreSelection() }.hideable(model, "Označit/Obnovit výběr")
            Divider()
            Button(L("Spočítat velikosti adresářů")) { model.source.computeAllDirSizes() }.hideable(model, "Označit/Spočítat velikosti adresářů")
        }
        CommandMenu(L("Síť")) {
            Button(L("Připojit k serveru…")) { model.connectToServer() }.keyboardShortcut("k").hideable(model, "Síť/Připojit k serveru…")
            Button(L("Odpojit panel od serveru")) { model.disconnect() }.keyboardShortcut("k", modifiers: [.command, .shift]).hideable(model, "Síť/Odpojit panel od serveru")
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
            Button(L("Zamknout / odemknout kartu")) { model.perform("cm_locktab") }.hideable(model, "Karty/Zamknout / odemknout kartu")
            Divider()
            Button(L("Uložit sadu karet…")) { model.saveFavoriteTabs() }.hideable(model, "Karty/Uložit sadu karet…")
            if !model.favoriteTabs.isEmpty {
                Divider()
                ForEach(model.favoriteTabs) { set in Button(set.name) { model.loadFavoriteTabs(set) } }
                Divider()
                Menu(L("Smazat sadu")) { ForEach(model.favoriteTabs) { set in Button(set.name) { model.deleteFavoriteTabs(set) } } }
            }
        }
        CommandMenu(L("Oblíbené")) {
            Button(L("Přidat aktuální adresář")) { model.hotlist.add(model.source.persistentPath) }.keyboardShortcut("d").hideable(model, "Oblíbené/Přidat aktuální adresář")
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
            Toggle(L("Skryté soubory"), isOn: Binding(get: { model.showHidden }, set: { model.showHidden = $0 })).hideable(model, "Zobrazení/Skryté soubory")
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button(L("Plný režim")) { model.source.viewMode = .full }.keyboardShortcut("1", modifiers: .control).hideable(model, "Zobrazení/Plný režim")
            Button(L("Stručný režim")) { model.source.viewMode = .brief }.keyboardShortcut("2", modifiers: .control).hideable(model, "Zobrazení/Stručný režim")
            Button(L("Náhledy")) { model.source.viewMode = .thumbnails }.keyboardShortcut("3", modifiers: .control).hideable(model, "Zobrazení/Náhledy")
            Button(L("Strom adresářů")) { model.source.viewMode = .tree }.keyboardShortcut("4", modifiers: .control).hideable(model, "Zobrazení/Strom adresářů")
            Menu(L("Sloupce (plný režim)")) {
                ForEach(model.settings.columnSets) { cs in
                    Button(cs.name) { model.source.viewMode = .full; model.source.columns = cs.columns }
                }
            }
            Button(L("Panely nad sebou / vedle sebe")) { model.perform("cm_layout") }.hideable(model, "Zobrazení/Panely nad sebou / vedle sebe")
            Button(L("Quick View (druhý panel)")) { model.quickViewOn.toggle() }.keyboardShortcut("q", modifiers: .control).hideable(model, "Zobrazení/Quick View (druhý panel)")
            Divider()
            Button(L("Obnovit")) { model.reloadAll() }.keyboardShortcut("r").hideable(model, "Zobrazení/Obnovit")
            Button(L("Branch view (všechny podadresáře)")) { model.toggleBranchView() }.keyboardShortcut("b").hideable(model, "Zobrazení/Branch view (všechny podadresáře)")
            Button(L("Rychlý filtr")) { model.toggleFilter() }.keyboardShortcut("f").hideable(model, "Zobrazení/Rychlý filtr")
            Divider()
            Button(L("Nadřazený adresář")) { model.source.goUp() }.keyboardShortcut(.upArrow, modifiers: .command).hideable(model, "Zobrazení/Nadřazený adresář")
            Button(L("Zpět")) { model.source.goBack() }.keyboardShortcut("[").hideable(model, "Zobrazení/Zpět")
            Button(L("Vpřed")) { model.source.goForward() }.keyboardShortcut("]").hideable(model, "Zobrazení/Vpřed")
            Divider()
            Button(L("Cíl = zdroj")) { model.targetEqualsSource() }.keyboardShortcut("=").hideable(model, "Zobrazení/Cíl = zdroj")
            Button(L("Prohodit panely")) { model.swapPanels() }.keyboardShortcut("u").hideable(model, "Zobrazení/Prohodit panely")
            Button(L("Další tab")) { model.group(model.activeSide).nextTab() }.keyboardShortcut("]", modifiers: [.command, .shift]).hideable(model, "Zobrazení/Další tab")
            Button(L("Předchozí tab")) { model.group(model.activeSide).previousTab() }.keyboardShortcut("[", modifiers: [.command, .shift]).hideable(model, "Zobrazení/Předchozí tab")
        }
    }
}
