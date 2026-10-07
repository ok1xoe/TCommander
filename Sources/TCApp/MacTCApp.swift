import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
            Button("Přejmenovat…") { model.rename() }
            Button("Nový adresář…") { model.makeDirectory() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Nový soubor…") { model.newFile() }
            Divider()
            Button("Kopírovat…") { model.transfer(.copy) }
            Button("Přesunout…") { model.transfer(.move) }
            Button("Smazat…") { model.delete(permanent: false) }.keyboardShortcut(.delete, modifiers: .command)
            Button("Smazat trvale…") { model.delete(permanent: true) }
        }
        CommandMenu("Označit") {
            Button("Označit vše") { model.source.markAll() }.keyboardShortcut("a")
            Button("Zrušit označení") { model.source.unmarkAll() }.keyboardShortcut("a", modifiers: [.command, .shift])
            Button("Invertovat označení") { model.source.invertMarks() }
            Button("Označit podle masky…") { model.markByMask(on: true) }
            Button("Odznačit podle masky…") { model.markByMask(on: false) }
            Button("Spočítat velikosti adresářů") { model.source.computeAllDirSizes() }
        }
        CommandMenu("Zobrazení") {
            Toggle("Skryté soubory", isOn: Binding(get: { model.showHidden }, set: { model.showHidden = $0 }))
                .keyboardShortcut(".", modifiers: [.command, .shift])
            Button("Obnovit") { model.reloadAll() }.keyboardShortcut("r")
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
