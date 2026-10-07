import CArchive
import Foundation

public struct ArchiveEntryInfo: Sendable, Hashable {
    public let path: String          // bez úvodního a koncového "/"
    public let size: Int64
    public let modified: Date?
    public let mode: UInt16
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let symlinkTarget: String?
}

public enum ArchiveSupport {
    private static let exts: Set<String> = ["zip", "jar", "war", "apk", "tar", "tgz", "tbz", "tbz2", "txz", "7z", "rar", "cab", "iso",
                                            "cpio", "xar", "pkg", "lzh", "lha", "deb", "a", "ar", "zst"]
    private static let compoundTar = [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst", ".tar.z", ".tar.lz", ".tar.lzma"]

    public static func isArchive(_ name: String) -> Bool {
        let l = name.lowercased()
        return compoundTar.contains { l.hasSuffix($0) } || exts.contains((l as NSString).pathExtension)
    }

    /// Normalizace cesty záznamu: bez "./", úvodního a koncového "/".
    public static func normalize(_ p: String) -> String {
        var s = p
        while s.hasPrefix("./") { s.removeFirst(2) }
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// Ochrana proti "zip slip": žádné ".." ani absolutní cesty.
    public static func isSafe(_ p: String) -> Bool {
        !p.isEmpty && !p.hasPrefix("/") && !p.split(separator: "/").contains("..")
    }
}

public struct ArchiveError: LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Souborový systém nad archivem (jen čtení). Cesty uvnitř archivu mají tvar "/adresář/soubor".
public final class ArchiveFileSystem: VirtualFileSystem, @unchecked Sendable {
    public let archiveURL: URL
    public let entries: [ArchiveEntryInfo]
    private let byPath: [String: ArchiveEntryInfo]
    private let children: [String: [String]]      // rodič ("" = kořen) -> cesty potomků

    public init(archiveURL: URL) throws {
        self.archiveURL = archiveURL
        var list: [ArchiveEntryInfo] = []
        try Self.read(archiveURL) { _, entry in
            guard let cpath = archive_entry_pathname(entry) else { return true }
            let path = ArchiveSupport.normalize(String(cString: cpath))
            guard !path.isEmpty else { return true }
            let type = Int32(archive_entry_filetype(entry))
            let isDir = type == CARCHIVE_IFDIR, isLink = type == CARCHIVE_IFLNK
            let size = archive_entry_size_is_set(entry) != 0 ? archive_entry_size(entry) : 0
            let mt = archive_entry_mtime(entry)
            list.append(ArchiveEntryInfo(path: path, size: isDir ? 0 : size, modified: mt > 0 ? Date(timeIntervalSince1970: TimeInterval(mt)) : nil,
                                         mode: UInt16(archive_entry_perm(entry) & 0o777), isDirectory: isDir, isSymlink: isLink,
                                         symlinkTarget: isLink ? archive_entry_symlink(entry).map { String(cString: $0) } : nil))
            return true
        }
        // doplnění implicitních adresářů
        var all = Dictionary(list.map { ($0.path, $0) }, uniquingKeysWith: { _, new in new })
        for e in list {
            var comps = e.path.split(separator: "/").map(String.init); comps.removeLast()
            var acc = ""
            for c in comps {
                acc = acc.isEmpty ? c : acc + "/" + c
                if all[acc] == nil { all[acc] = ArchiveEntryInfo(path: acc, size: 0, modified: nil, mode: 0o755, isDirectory: true, isSymlink: false, symlinkTarget: nil) }
            }
        }
        byPath = all
        entries = all.values.sorted { $0.path < $1.path }
        var kids: [String: [String]] = [:]
        for e in entries {
            let parent = (e.path as NSString).deletingLastPathComponent
            kids[parent, default: []].append(e.path)
        }
        children = kids
    }

    // MARK: Čtení libarchive

    /// Projde záznamy; `visit` vrací false pro ukončení. Data záznamu lze číst uvnitř `visit` pomocí `archive`.
    static func read(_ url: URL, passphrase: String? = nil,
                     _ visit: (OpaquePointer, OpaquePointer) throws -> Bool) throws {
        guard let a = archive_read_new() else { throw ArchiveError(message: "Nelze inicializovat libarchive") }
        defer { _ = archive_read_free(a) }
        _ = archive_read_support_filter_all(a)
        _ = archive_read_support_format_all(a)
        if let passphrase { _ = archive_read_add_passphrase(a, passphrase) }
        guard archive_read_open_filename(a, url.path, 1 << 16) == CARCHIVE_OK else {
            throw ArchiveError(message: archive_error_string(a).map { String(cString: $0) } ?? "Archiv nelze otevřít")
        }
        var entry: OpaquePointer?
        while true {
            let r = archive_read_next_header(a, &entry)
            if r == CARCHIVE_EOF { return }
            if r < CARCHIVE_WARN { throw ArchiveError(message: archive_error_string(a).map { String(cString: $0) } ?? "Chyba při čtení archivu") }
            guard let entry else { return }
            if try !visit(a, entry) { return }
        }
    }

    // MARK: VirtualFileSystem

    private func key(_ url: URL) -> String { ArchiveSupport.normalize(url.path) }

    private func makeEntry(_ e: ArchiveEntryInfo) -> FileEntry {
        let name = (e.path as NSString).lastPathComponent
        return FileEntry(url: URL(fileURLWithPath: "/" + e.path), name: name, isDirectory: e.isDirectory, isSymlink: e.isSymlink,
                         isHidden: name.hasPrefix("."), size: e.size, modified: e.modified, permissions: e.mode)
    }

    public func list(_ dir: URL, includeHidden: Bool) throws -> [FileEntry] {
        let k = key(dir)
        if !k.isEmpty { guard byPath[k]?.isDirectory == true else { throw ArchiveError(message: "Není adresář: \(dir.path)") } }
        return (children[k] ?? []).compactMap { byPath[$0] }.map(makeEntry).filter { includeHidden || !$0.isHidden }
    }

    public func stat(_ url: URL) throws -> FileEntry {
        let k = key(url)
        if k.isEmpty { return FileEntry(url: URL(fileURLWithPath: "/"), name: "/", isDirectory: true) }
        guard let e = byPath[k] else { throw ArchiveError(message: "Neexistuje v archivu: \(url.path)") }
        return makeEntry(e)
    }

    public func exists(_ url: URL) -> Bool { key(url).isEmpty || byPath[key(url)] != nil }

    private func readOnly() -> ArchiveError { ArchiveError(message: "Archiv je zatím jen pro čtení") }
    public func createDirectory(_ url: URL) throws { throw readOnly() }
    public func createFile(_ url: URL) throws { throw readOnly() }
    public func copy(_ src: URL, to dst: URL) throws { throw readOnly() }
    public func move(_ src: URL, to dst: URL) throws { throw readOnly() }
    public func trash(_ url: URL) throws { throw readOnly() }
    public func remove(_ url: URL) throws { throw readOnly() }

    // MARK: Rozbalení

    /// Všechny cesty (soubory i adresáře) pod vybranými vnitřními cestami včetně nich samotných.
    public func expand(_ innerPaths: [String]) -> [ArchiveEntryInfo] {
        let roots = innerPaths.map(ArchiveSupport.normalize)
        return entries.filter { e in roots.contains { e.path == $0 || e.path.hasPrefix($0 + "/") } }
    }

    /// Rozbalí vybrané položky do `dest`; v cíli zůstane jen poslední složka cesty (jako při kopii).
    public func extract(_ innerPaths: [String], to dest: URL, policy: ConflictPolicy = .overwrite,
                        control: OperationControl = OperationControl(),
                        progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        var report = OperationReport()
        let roots = innerPaths.map(ArchiveSupport.normalize)
        let wanted = expand(innerPaths)
        var p = TransferProgress()
        p.filesTotal = wanted.filter { !$0.isDirectory }.count
        p.bytesTotal = wanted.reduce(0) { $0 + $1.size }
        let fm = FileManager.default
        let helper = FileOperations()
        var skipRoots: [String] = []                // přeskočené kořeny (podle politiky konfliktů)
        var renamed: [String: String] = [:]         // kořen -> nový název (keepBoth)

        func destination(for path: String) -> URL? {
            guard let root = roots.first(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return nil }
            let parent = (root as NSString).lastPathComponent
            var rel = parent + String(path.dropFirst(root.count))
            if let n = renamed[root] { rel = n + String(path.dropFirst(root.count)) }
            return dest.appendingPathComponent(rel)
        }

        do {
            try Self.read(archiveURL) { a, entry in
                guard control.checkpoint() else { throw CancellationError() }
                guard let cp = archive_entry_pathname(entry) else { return true }
                let path = ArchiveSupport.normalize(String(cString: cp))
                guard roots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) else { return true }
                guard ArchiveSupport.isSafe(path) else {
                    report.failures.append(.init(url: URL(fileURLWithPath: "/" + path), message: "Nebezpečná cesta v archivu (..)")); return true
                }
                if skipRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
                guard var out = destination(for: path) else { return true }
                let type = Int32(archive_entry_filetype(entry))
                let root = roots.first { path == $0 || path.hasPrefix($0 + "/") }!

                // konflikty řešíme u kořenů (u adresářů se slučuje)
                if path == root, fm.fileExists(atPath: out.path) {
                    var isDir: ObjCBool = false; fm.fileExists(atPath: out.path, isDirectory: &isDir)
                    if !(type == CARCHIVE_IFDIR && isDir.boolValue) {
                        switch policy {
                        case .skip: skipRoots.append(root); report.skipped += 1; return true
                        case .overwriteOlder:
                            let mt = Date(timeIntervalSince1970: TimeInterval(archive_entry_mtime(entry)))
                            if let d = try? fm.attributesOfItem(atPath: out.path)[.modificationDate] as? Date, mt <= d {
                                skipRoots.append(root); report.skipped += 1; return true
                            }
                            try fm.removeItem(at: out)
                        case .overwrite: try fm.removeItem(at: out)
                        case .keepBoth:
                            let u = helper.uniqueName(out); renamed[root] = u.lastPathComponent; out = u
                        }
                    }
                }
                try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                p.current = out.lastPathComponent
                if type == CARCHIVE_IFDIR {
                    try fm.createDirectory(at: out, withIntermediateDirectories: true)
                } else if type == CARCHIVE_IFLNK {
                    if let t = archive_entry_symlink(entry) {
                        try? fm.removeItem(at: out)
                        try fm.createSymbolicLink(atPath: out.path, withDestinationPath: String(cString: t))
                    }
                    p.filesDone += 1
                } else {
                    guard fm.createFile(atPath: out.path, contents: nil) else { throw ArchiveError(message: "Nelze vytvořit \(out.path)") }
                    let h = try FileHandle(forWritingTo: out)
                    defer { try? h.close() }
                    let size = 1 << 16
                    let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
                    defer { buf.deallocate() }
                    while true {
                        guard control.checkpoint() else { try? fm.removeItem(at: out); throw CancellationError() }
                        let n = archive_read_data(a, buf, size)
                        if n == 0 { break }
                        if n < 0 {
                            try? fm.removeItem(at: out)
                            throw ArchiveError(message: archive_error_string(a).map { String(cString: $0) } ?? "Chyba při čtení dat")
                        }
                        try h.write(contentsOf: Data(bytes: buf, count: n))
                        p.bytesDone += Int64(n); progress?(p)
                    }
                    p.filesDone += 1
                }
                let mt = archive_entry_mtime(entry)
                var attrs: [FileAttributeKey: Any] = [:]
                if mt > 0 { attrs[.modificationDate] = Date(timeIntervalSince1970: TimeInterval(mt)) }
                if type != CARCHIVE_IFLNK { attrs[.posixPermissions] = NSNumber(value: archive_entry_perm(entry) & 0o777 | (type == CARCHIVE_IFDIR ? 0o700 : 0o600)) }
                if !attrs.isEmpty { try? fm.setAttributes(attrs, ofItemAtPath: out.path) }
                if path == root { report.succeeded += 1 }
                progress?(p)
                return true
            }
        } catch is CancellationError {
            report.cancelled = true
        } catch {
            report.failures.append(.init(url: archiveURL, message: error.localizedDescription))
        }
        progress?(p)
        return report
    }

    /// Rozbalí celý archiv do `dest`.
    public func extractAll(to dest: URL, policy: ConflictPolicy = .overwrite, control: OperationControl = OperationControl(),
                           progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        let tops = Set(entries.map { String($0.path.split(separator: "/").first ?? "") }).filter { !$0.isEmpty }.sorted()
        return extract(tops, to: dest, policy: policy, control: control, progress: progress)
    }

    // MARK: Test a dočasné rozbalení

    /// Přečte všechna data a ohlásí poškozené záznamy (test integrity archivu).
    public func test(control: OperationControl = OperationControl(),
                     progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        var report = OperationReport()
        var p = TransferProgress()
        p.filesTotal = entries.filter { !$0.isDirectory }.count
        p.bytesTotal = entries.reduce(0) { $0 + $1.size }
        do {
            try Self.read(archiveURL) { a, entry in
                guard control.checkpoint() else { throw CancellationError() }
                let name = archive_entry_pathname(entry).map { String(cString: $0) } ?? "?"
                p.current = name
                let size = 1 << 16
                let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
                defer { buf.deallocate() }
                while true {
                    let n = archive_read_data(a, buf, size)
                    if n == 0 { break }
                    if n < 0 {
                        report.failures.append(.init(url: URL(fileURLWithPath: "/" + name),
                                                     message: archive_error_string(a).map { String(cString: $0) } ?? "Poškozená data"))
                        break
                    }
                    p.bytesDone += Int64(n); progress?(p)
                }
                if Int32(archive_entry_filetype(entry)) != CARCHIVE_IFDIR { p.filesDone += 1; report.succeeded += 1 }
                return true
            }
        } catch is CancellationError { report.cancelled = true }
        catch { report.failures.append(.init(url: archiveURL, message: error.localizedDescription)) }
        return report
    }

    /// Rozbalí jednu položku do dočasného adresáře a vrátí URL výsledku.
    public func extractToTemporary(_ innerPath: String) throws -> URL {
        let dir = ArchiveFileSystem.temporaryRoot.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let r = extract([innerPath], to: dir)
        if let f = r.failures.first { throw ArchiveError(message: f.message) }
        return dir.appendingPathComponent((ArchiveSupport.normalize(innerPath) as NSString).lastPathComponent)
    }

    public static var temporaryRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("TCommander-archive") }
    public static func cleanTemporary() { try? FileManager.default.removeItem(at: temporaryRoot) }
}
