import AppKit
import TCCore

/// Žádosti o přístup ke složkám v App Sandboxu (verze z Mac App Store): úvodní uvítání a dialog při odepřeném přístupu.
@MainActor
enum AccessPrompt {
    /// Dokud neskončí start aplikace, se nikdo neptá (první výpisy panelů proběhnou ještě před zobrazením okna).
    private static var ready = false
    private static var lastDecline: Date?

    /// Po startu: v sandboxu při prvním spuštění uvítá a vyžádá přístup k domovské složce, pak znovu načte panely.
    static func launchFinished() {
        ready = true
        guard Sandbox.isSandboxed else { return }
        if AccessManager.shared.roots.isEmpty {
            let welcome = Dialogs.confirm(
                title: "Vítejte v TCommanderu",
                message: "Aby mohl TCommander pracovat s vašimi soubory, potřebuje váš souhlas s přístupem ke složce. Doporučujeme vybrat celou domovskou složku; později můžete povolit další složky nebo disky (stačí je v panelu otevřít). Souhlas se uloží a příště se neptá.",
                ok: "Vybrat složku…")
            if welcome { _ = choose(directory: Sandbox.home, message: "Vyberte složku, ke které chcete TCommanderu povolit přístup (doporučeno: vaše domovská složka).", target: nil) }
        }
        AppModel.shared.reloadAll()
    }

    /// Zeptá se na přístup ke složce, kterou se nepodařilo otevřít; vrací true, pokud byla povolena.
    static func request(for target: URL) -> Bool {
        guard ready, Sandbox.isSandboxed else { return false }
        if let d = lastDecline, Date().timeIntervalSince(d) < 4 { return false }              // při odmítnutí se neptá znovu pro každý panel
        let home = Sandbox.home.path
        let suggested = target.path == home || target.path.hasPrefix(home + "/") ? Sandbox.home : target
        let name = target.lastPathComponent.isEmpty ? target.path : target.lastPathComponent
        return choose(directory: suggested, message: "TCommander potřebuje váš souhlas, aby mohl otevřít „\(name)“. Vyberte složku a potvrďte (stejným způsobem lze povolit i celý disk).", target: target)
    }

    private static func choose(directory: URL, message: String, target: URL?) -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = directory
        panel.message = message
        panel.prompt = "Povolit přístup"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { lastDecline = Date(); return false }
        AccessManager.shared.grant(url)
        if let target, !AccessManager.shared.covers(target) { lastDecline = Date(); return false }
        return true
    }
}
