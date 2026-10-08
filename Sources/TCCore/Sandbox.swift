import Foundation

/// Edice aplikace: ve verzi z Mac App Store běží v App Sandboxu, bez něj (GitHub, vlastní sestavení) má plný přístup k disku.
public enum Sandbox {
    /// Proces běží v App Sandboxu (systém tehdy nastavuje `APP_SANDBOX_CONTAINER_ID`).
    public static var isSandboxed: Bool { override ?? actual }

    private static let actual: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// Jen pro testy: přepíše příznak sandboxu pouze v rámci jedné úlohy (`Sandbox.$override.withValue(true) { … }`), takže souběžné testy ho nevidí.
    @TaskLocal public static var override: Bool?

    /// Skutečná domovská složka uživatele; v sandboxu vrací `homeDirectoryForCurrentUser` složku kontejneru, ta se tu obchází.
    public static var home: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return URL(fileURLWithPath: String(cString: dir), isDirectory: true) }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Chyba „přístup odepřen“ (oprávnění, sandbox).
    public static func isPermissionDenied(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let e = current {
            if e.domain == NSCocoaErrorDomain, [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(e.code) { return true }
            if e.domain == NSPOSIXErrorDomain, [Int(EPERM), Int(EACCES)].contains(e.code) { return true }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

/// Složky, ke kterým uživatel aplikaci povolil přístup (security-scoped bookmarky). V sandboxu je to jediná cesta k souborům mimo kontejner;
/// bez sandboxu se jen evidují.
public final class AccessManager: @unchecked Sendable {
    public static let shared = AccessManager()

    /// Cesta bez symbolických odkazů (např. /var → /private/var), aby se povolené složky a dotazy porovnávaly stejně.
    static func normalized(_ url: URL) -> URL { url.resolvingSymlinksInPath().standardizedFileURL }

    private let store: JSONStore<[Data]>
    private let lock = NSLock()
    private var active: [URL] = []

    public init(store: JSONStore<[Data]> = JSONStore<[Data]>(name: "access")) { self.store = store }

    /// Povolené složky (po `restore()` a `grant(_:)`).
    public var roots: [URL] { lock.lock(); defer { lock.unlock() }; return active }

    /// Načte uložené bookmarky a zapne přístup; zastaralé obnoví a neplatné zahodí.
    public func restore() {
        var saved = store.load(default: [])
        var kept: [Data] = [], urls: [URL] = []
        for data in saved {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) else { continue }
            guard url.startAccessingSecurityScopedResource() || !Sandbox.isSandboxed else { continue }
            urls.append(Self.normalized(url))
            kept.append(stale ? ((try? url.bookmarkData(options: .withSecurityScope)) ?? data) : data)
        }
        if kept != saved { saved = kept; store.save(saved) }
        lock.lock(); active = urls; lock.unlock()
    }

    /// Zapamatuje a zapne přístup ke složce vybrané uživatelem (např. v otevíracím dialogu).
    @discardableResult
    public func grant(_ url: URL) -> Bool {
        let u = Self.normalized(url)
        guard let data = try? u.bookmarkData(options: .withSecurityScope) else { return false }
        _ = u.startAccessingSecurityScopedResource()
        lock.lock()
        active.removeAll { $0.path == u.path }
        // povolení nadřazené složky nahrazuje povolení podsložek
        let narrower = active.filter { $0.path.hasPrefix(u.path + "/") }
        active.removeAll { $0.path.hasPrefix(u.path + "/") }
        active.append(u)
        let all = active
        lock.unlock()
        narrower.forEach { $0.stopAccessingSecurityScopedResource() }
        store.save(all.compactMap { try? $0.bookmarkData(options: .withSecurityScope) })
        _ = data
        return true
    }

    /// Je cesta uvnitř některé povolené složky?
    public func covers(_ url: URL) -> Bool {
        let p = Self.normalized(url).path
        return roots.contains { p == $0.path || p.hasPrefix($0.path == "/" ? "/" : $0.path + "/") }
    }

    public func revoke(_ url: URL) {
        let u = Self.normalized(url)
        lock.lock(); active.removeAll { $0.path == u.path }; let all = active; lock.unlock()
        u.stopAccessingSecurityScopedResource()
        store.save(all.compactMap { try? $0.bookmarkData(options: .withSecurityScope) })
    }
}
