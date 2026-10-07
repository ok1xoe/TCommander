import AppKit
import SwiftUI
import TCCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
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
            Button("Nový tab") { model.group(model.activeSide).newTab() }.keyboardShortcut("t")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Zavřít tab") { model.group(model.activeSide).closeActiveTab() }.keyboardShortcut("w")
        }
        CommandMenu("Soubor") {
            Button("Otevřít") { model.open() }.keyboardShortcut("o")
            Button("Hledat soubory…") { model.search() }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Přejmenovat…") { model.rename() }
            Button("Nový adresář…") { model.makeDirectory() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Nový soubor…") { model.newFile() }
            Divider()
            Button("Kopírovat…") { model.transfer(.copy) }
            Button("Přesunout…") { model.transfer(.move) }
            Button("Smazat…") { model.delete(permanent: false) }.keyboardShortcut(.delete, modifiers: .command)
            Button("Smazat trvale…") { model.delete(permanent: true) }
            Divider()
            Toggle("Ověřovat kopie (SHA-256)", isOn: Binding(get: { model.verifyCopies }, set: { model.verifyCopies = $0 }))
        }
        CommandMenu("Porovnání") {
            Button("Porovnat soubory podle obsahu…") { model.compareFiles() }.keyboardShortcut("c", modifiers: [.control, .shift])
            Button("Porovnat adresáře (označit rozdíly)") { model.compareDirectories() }.keyboardShortcut("d", modifiers: [.control, .shift])
            Button("Synchronizovat adresáře…") { model.synchronize() }.keyboardShortcut("s", modifiers: [.control, .shift])
        }
        CommandMenu("Nástroje") {
            Button("Hromadné přejmenování…") { model.multiRename() }.keyboardShortcut("m", modifiers: .control)
            Divider()
            Button("Vlastnosti…") { model.properties() }.keyboardShortcut(.return, modifiers: .option)
            Divider()
            Button("Kontrolní součty…") { model.checksums() }
            Button("Ověřit kontrolní součty ze souboru") { model.verifyChecksums() }
            Divider()
            Button("Zabalit do archivu…") { model.packFiles() }
            Button("Rozbalit archiv…") { model.unpackArchives() }
            Button("Otestovat archiv") { model.testArchives() }
            Divider()
            Button("Najít duplicitní soubory…") { model.findDuplicates() }
            Divider()
            Button("Kódovat soubory (MIME, UUE, XXE) do druhého panelu…") { model.encodeFiles() }
            Button("Dekódovat soubory do druhého panelu…") { model.decodeFiles() }
            Divider()
            Button("Rozdělit soubor…") { model.splitFile() }
            Button("Spojit soubory (.001)…") { model.combineFiles() }
            Divider()
            Button("Symbolický odkaz do druhého panelu…") { model.makeLink(hard: false) }
            Button("Pevný odkaz do druhého panelu…") { model.makeLink(hard: true) }
        }
        CommandMenu("Označit") {
            Button("Označit vše") { model.source.markAll() }.keyboardShortcut("a")
            Button("Zrušit označení") { model.source.unmarkAll() }.keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Invertovat označení") { model.source.invertMarks() }
            Button("Označit podle masky…") { model.markByMask(on: true) }
            Button("Odznačit podle masky…") { model.markByMask(on: false) }
            Button("Označit stejnou příponu") { model.source.markSameExtension() }.keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Uložit výběr") { model.source.saveSelection() }
            Button("Obnovit výběr") { model.source.restoreSelection() }
            Divider()
            Button("Spočítat velikosti adresářů") { model.source.computeAllDirSizes() }
        }
        CommandMenu("Oblíbené") {
            Button("Přidat aktuální adresář") { model.hotlist.add(model.source.persistentPath) }.keyboardShortcut("d")
            Divider()
            ForEach(model.hotlist.entries) { e in
                Button(e.name) { model.goTo(URL(fileURLWithPath: e.path)) }
            }
            if !model.hotlist.entries.isEmpty {
                Divider()
                Menu("Odebrat") {
                    ForEach(model.hotlist.entries) { e in Button(e.name) { model.hotlist.remove(e) } }
                }
            }
        }
        CommandMenu("Historie") {
            ForEach(Array(model.source.recent.prefix(25)), id: \.self) { url in
                Button(url.path) { model.goTo(url) }
            }
        }
        CommandMenu("Zobrazení") {
            Toggle("Skryté soubory", isOn: Binding(get: { model.showHidden }, set: { model.showHidden = $0 }))
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button("Plný režim") { model.source.viewMode = .full }.keyboardShortcut("1", modifiers: .control)
            Button("Stručný režim") { model.source.viewMode = .brief }.keyboardShortcut("2", modifiers: .control)
            Button("Náhledy") { model.source.viewMode = .thumbnails }.keyboardShortcut("3", modifiers: .control)
            Button("Quick View (druhý panel)") { model.quickViewOn.toggle() }.keyboardShortcut("q", modifiers: .control)
            Divider()
            Button("Obnovit") { model.reloadAll() }.keyboardShortcut("r")
            Button("Branch view (všechny podadresáře)") { model.toggleBranchView() }.keyboardShortcut("b")
            Button("Rychlý filtr") { model.toggleFilter() }.keyboardShortcut("f")
            Divider()
            Button("Nadřazený adresář") { model.source.goUp() }.keyboardShortcut(.upArrow, modifiers: .command)
            Button("Zpět") { model.source.goBack() }.keyboardShortcut("[")
            Button("Vpřed") { model.source.goForward() }.keyboardShortcut("]")
            Divider()
            Button("Cíl = zdroj") { model.targetEqualsSource() }.keyboardShortcut("=")
            Button("Prohodit panely") { model.swapPanels() }.keyboardShortcut("u")
            Button("Další tab") { model.group(model.activeSide).nextTab() }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Předchozí tab") { model.group(model.activeSide).previousTab() }.keyboardShortcut("[", modifiers: [.command, .shift])
        }
    }
}
