import Foundation

/// Složky aplikace. Při přejmenování z macTC na TCommander se stará složka s nastavením jednorázově přesune, aby se nic neztratilo.
public enum AppPaths {
    public static let appName = "TCommander"
    static let legacyName = "macTC"

    /// ~/Library/Application Support/TCommander (nastavení, zkratky, spojení, oblíbené adresáře, pluginy).
    public static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return migrate(base: base)
    }()

    /// Přesune `base/macTC` na `base/TCommander`, pokud nová složka ještě neexistuje; vrací novou cestu.
    static func migrate(base: URL) -> URL {
        let fm = FileManager.default
        let new = base.appendingPathComponent(appName), old = base.appendingPathComponent(legacyName)
        if fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) { try? fm.moveItem(at: old, to: new) }
        return new
    }

    public static var plugins: URL { support.appendingPathComponent("PlugIns") }

    /// ~/Library/Caches/TCommander/<podsložka>
    public static func caches(_ sub: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent(appName).appendingPathComponent(sub)
    }
}
