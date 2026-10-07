import CArchive
import Foundation

public enum ArchiveFormat: String, Sendable, CaseIterable {
    case zip, tarGz, tarBz2, tarXz, sevenZip

    public var displayName: String {
        switch self { case .zip: "ZIP"; case .tarGz: "TAR.GZ"; case .tarBz2: "TAR.BZ2"; case .tarXz: "TAR.XZ"; case .sevenZip: "7-Zip" }
    }
    public var fileExtension: String {
        switch self { case .zip: "zip"; case .tarGz: "tar.gz"; case .tarBz2: "tar.bz2"; case .tarXz: "tar.xz"; case .sevenZip: "7z" }
    }

    /// Formát podle názvu souboru; nil pro formáty, které libarchive neumí zapisovat (rar, iso, cab …).
    public static func detect(fileName: String) -> ArchiveFormat? {
        let l = fileName.lowercased()
        if l.hasSuffix(".tar.gz") || l.hasSuffix(".tgz") { return .tarGz }
        if l.hasSuffix(".tar.bz2") || l.hasSuffix(".tbz") || l.hasSuffix(".tbz2") { return .tarBz2 }
        if l.hasSuffix(".tar.xz") || l.hasSuffix(".txz") { return .tarXz }
        if l.hasSuffix(".zip") || l.hasSuffix(".jar") || l.hasSuffix(".war") || l.hasSuffix(".apk") { return .zip }
        if l.hasSuffix(".7z") { return .sevenZip }
        return nil
    }

    fileprivate func configure(_ a: OpaquePointer) {
        switch self {
        case .zip: _ = archive_write_set_format_zip(a)
        case .sevenZip: _ = archive_write_set_format_7zip(a)
        case .tarGz: _ = archive_write_set_format_pax_restricted(a); _ = archive_write_add_filter_gzip(a)
        case .tarBz2: _ = archive_write_set_format_pax_restricted(a); _ = archive_write_add_filter_bzip2(a)
        case .tarXz: _ = archive_write_set_format_pax_restricted(a); _ = archive_write_add_filter_xz(a)
        }
    }
}

/// Zápis a úpravy archivů (vždy přepsáním do nového souboru a atomickou výměnou).
public enum ArchiveWriter {
    fileprivate final class Sink {
        let a: OpaquePointer
        let control: OperationControl
        var progress = TransferProgress()
        let handler: (@Sendable (TransferProgress) -> Void)?
        var last = Date.distantPast
        init(_ a: OpaquePointer, control: OperationControl, handler: (@Sendable (TransferProgress) -> Void)?) {
            self.a = a; self.control = control; self.handler = handler
        }
        func tick(force: Bool = false) {
            guard let handler else { return }
            let now = Date()
            if force || now.timeIntervalSince(last) > 0.05 { last = now; handler(progress) }
        }
        func error(_ fallback: String) -> ArchiveError { ArchiveError(message: archive_error_string(a).map { String(cString: $0) } ?? fallback) }
    }

    /// Vytvoří nový archiv ze zdrojů (soubory a adresáře, názvy nejvyšší úrovně se zachovají).
    public static func create(_ archive: URL, format: ArchiveFormat, sources: [URL], control: OperationControl = OperationControl(),
                              progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        var changes = ArchiveFileSystem.Changes()
        changes.add = sources.map { ArchiveFileSystem.Addition(local: $0, innerDirectory: "") }
        return rewrite(source: nil, destination: archive, format: format, changes: changes, control: control, progress: progress, replaceInPlace: false)
    }

    /// Společné jádro: volitelně zkopíruje záznamy ze stávajícího archivu (s úpravami) a doplní nové.
    static func rewrite(source: URL?, destination: URL, format: ArchiveFormat, changes: ArchiveFileSystem.Changes,
                        control: OperationControl, progress: (@Sendable (TransferProgress) -> Void)?, replaceInPlace: Bool) -> OperationReport {
        var report = OperationReport()
        let fm = FileManager.default
        let tmp = destination.deletingLastPathComponent().appendingPathComponent(".macTC-\(UUID().uuidString).tmp")
        guard let a = archive_write_new() else {
            report.failures.append(.init(url: destination, message: "Nelze inicializovat libarchive")); return report
        }
        var closed = false
        defer { if !closed { _ = archive_write_free(a) } }
        format.configure(a)
        guard archive_write_open_filename(a, tmp.path) == CARCHIVE_OK else {
            report.failures.append(.init(url: destination, message: archive_error_string(a).map { String(cString: $0) } ?? "Archiv nelze vytvořit"))
            return report
        }
        let sink = Sink(a, control: control, handler: progress)
        do {
            // cesty nových položek (kvůli nahrazení starých)
            var newPaths = Set<String>()
            for add in changes.add { try collect(add.local, add.innerDirectory, into: &newPaths) }
            sink.progress.bytesTotal = changes.add.reduce(0) { $0 + localSize($1.local) }
            if let source {
                let old = try ArchiveFileSystem(archiveURL: source)
                sink.progress.bytesTotal += old.entries.reduce(0) { $0 + $1.size }
                try copyExisting(source, sink, changes, newPaths)
            }
            for dir in changes.makeDirectories {
                let path = ArchiveSupport.normalize(dir)
                guard ArchiveSupport.isSafe(path) else { throw ArchiveError(message: "Neplatný název složky") }
                try writeDirectoryEntry(sink, path)
            }
            for add in changes.add { try write(add.local, add.innerDirectory, sink) }
            sink.tick(force: true)
            guard archive_write_close(a) == CARCHIVE_OK else { throw sink.error("Archiv nelze dokončit") }
            _ = archive_write_free(a); closed = true
            if replaceInPlace { _ = try fm.replaceItemAt(destination, withItemAt: tmp) }
            else { try? fm.removeItem(at: destination); try fm.moveItem(at: tmp, to: destination) }
            report.succeeded = 1
        } catch is CancellationError {
            report.cancelled = true
            if !closed { _ = archive_write_close(a); _ = archive_write_free(a); closed = true }
            try? fm.removeItem(at: tmp)
        } catch {
            report.failures.append(.init(url: destination, message: error.localizedDescription))
            if !closed { _ = archive_write_close(a); _ = archive_write_free(a); closed = true }
            try? fm.removeItem(at: tmp)
        }
        return report
    }

    // MARK: Kopie stávajících záznamů

    private static func copyExisting(_ source: URL, _ sink: Sink, _ changes: ArchiveFileSystem.Changes, _ newPaths: Set<String>) throws {
        let removed = changes.remove.map(ArchiveSupport.normalize)
        let renames = changes.rename.map { (ArchiveSupport.normalize($0.key), ArchiveSupport.normalize($0.value)) }
        try ArchiveFileSystem.read(source) { r, entry in
            guard sink.control.checkpoint() else { throw CancellationError() }
            guard let cp = archive_entry_pathname(entry) else { return true }
            var path = ArchiveSupport.normalize(String(cString: cp))
            if path.isEmpty { return true }
            if removed.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
            if newPaths.contains(path) { return true }
            for (from, to) in renames where path == from || path.hasPrefix(from + "/") {
                path = to + String(path.dropFirst(from.count)); break
            }
            guard ArchiveSupport.isSafe(path) else { throw ArchiveError(message: "Neplatný nový název: \(path)") }
            guard let copy = archive_entry_clone(entry) else { throw ArchiveError(message: "Nedostatek paměti") }
            defer { archive_entry_free(copy) }
            let isDir = Int32(archive_entry_filetype(entry)) == CARCHIVE_IFDIR
            archive_entry_set_pathname(copy, isDir ? path + "/" : path)
            guard archive_write_header(sink.a, copy) == CARCHIVE_OK else { throw sink.error("Chyba při zápisu záznamu") }
            sink.progress.current = (path as NSString).lastPathComponent
            let size = 1 << 16
            let buf = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
            defer { buf.deallocate() }
            while true {
                guard sink.control.checkpoint() else { throw CancellationError() }
                let n = archive_read_data(r, buf, size)
                if n == 0 { break }
                if n < 0 { throw ArchiveError(message: archive_error_string(r).map { String(cString: $0) } ?? "Chyba při čtení původního archivu") }
                guard archive_write_data(sink.a, buf, n) == n else { throw sink.error("Chyba při zápisu dat") }
                sink.progress.bytesDone += Int64(n); sink.tick()
            }
            return true
        }
    }

    // MARK: Zápis lokálních souborů

    private static func localSize(_ url: URL) -> Int64 {
        FileOperations().scan(url).bytes
    }

    private static func collect(_ local: URL, _ innerDir: String, into set: inout Set<String>) throws {
        let name = local.lastPathComponent
        let inner = ArchiveSupport.normalize(innerDir.isEmpty ? name : innerDir + "/" + name)
        guard ArchiveSupport.isSafe(inner) else { throw ArchiveError(message: "Neplatný název: \(name)") }
        set.insert(inner)
        let e = try LocalFileSystem().stat(local)
        if e.isDirectory && !e.isSymlink {
            for c in try LocalFileSystem().list(local, includeHidden: true) { try collect(c.url, inner, into: &set) }
        }
    }

    private static func writeDirectoryEntry(_ sink: Sink, _ path: String) throws {
        guard let e = archive_entry_new() else { throw ArchiveError(message: "Nedostatek paměti") }
        defer { archive_entry_free(e) }
        archive_entry_set_pathname(e, path + "/")
        archive_entry_set_filetype(e, UInt32(CARCHIVE_IFDIR))
        archive_entry_set_perm(e, 0o755)
        archive_entry_set_mtime(e, time(nil), 0)
        archive_entry_set_size(e, 0)
        guard archive_write_header(sink.a, e) == CARCHIVE_OK else { throw sink.error("Chyba při zápisu složky") }
    }

    private static func write(_ local: URL, _ innerDir: String, _ sink: Sink) throws {
        guard sink.control.checkpoint() else { throw CancellationError() }
        let fs = LocalFileSystem()
        let info = try fs.stat(local)
        let inner = ArchiveSupport.normalize(innerDir.isEmpty ? info.name : innerDir + "/" + info.name)
        guard let e = archive_entry_new() else { throw ArchiveError(message: "Nedostatek paměti") }
        defer { archive_entry_free(e) }
        let mtime = Int(info.modified?.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
        sink.progress.current = info.name
        if info.isSymlink {
            archive_entry_set_pathname(e, inner)
            archive_entry_set_filetype(e, UInt32(CARCHIVE_IFLNK))
            archive_entry_set_symlink(e, try FileManager.default.destinationOfSymbolicLink(atPath: local.path))
            archive_entry_set_perm(e, 0o755); archive_entry_set_mtime(e, mtime, 0); archive_entry_set_size(e, 0)
            guard archive_write_header(sink.a, e) == CARCHIVE_OK else { throw sink.error("Chyba při zápisu odkazu") }
            sink.progress.filesDone += 1
        } else if info.isDirectory {
            archive_entry_set_pathname(e, inner + "/")
            archive_entry_set_filetype(e, UInt32(CARCHIVE_IFDIR))
            archive_entry_set_perm(e, mode_t(info.permissions)); archive_entry_set_mtime(e, mtime, 0); archive_entry_set_size(e, 0)
            guard archive_write_header(sink.a, e) == CARCHIVE_OK else { throw sink.error("Chyba při zápisu složky") }
            for c in try fs.list(local, includeHidden: true).sorted(by: { $0.name < $1.name }) { try write(c.url, inner, sink) }
        } else {
            archive_entry_set_pathname(e, inner)
            archive_entry_set_filetype(e, UInt32(CARCHIVE_IFREG))
            archive_entry_set_perm(e, mode_t(info.permissions)); archive_entry_set_mtime(e, mtime, 0); archive_entry_set_size(e, info.size)
            guard archive_write_header(sink.a, e) == CARCHIVE_OK else { throw sink.error("Chyba při zápisu záznamu") }
            let h = try FileHandle(forReadingFrom: local)
            defer { try? h.close() }
            var remaining = info.size
            while remaining > 0, let d = try h.read(upToCount: Int(min(remaining, 1 << 16))), !d.isEmpty {
                guard sink.control.checkpoint() else { throw CancellationError() }
                let n = d.withUnsafeBytes { archive_write_data(sink.a, $0.baseAddress, d.count) }
                guard n == d.count else { throw sink.error("Chyba při zápisu dat") }
                remaining -= Int64(d.count)
                sink.progress.bytesDone += Int64(d.count); sink.tick()
            }
            sink.progress.filesDone += 1
        }
    }
}

public extension ArchiveFileSystem {
    struct Addition: Sendable {
        public let local: URL
        public let innerDirectory: String
        public init(local: URL, innerDirectory: String) { self.local = local; self.innerDirectory = innerDirectory }
    }

    struct Changes: Sendable {
        public var add: [Addition] = []
        public var remove: [String] = []
        public var rename: [String: String] = [:]
        public var makeDirectories: [String] = []
        public init() {}
    }

    /// Lze archiv přepsat (zip, tar.gz/bz2/xz, 7z)? Ostatní formáty (rar, iso, cab …) jsou jen pro čtení.
    var isWritable: Bool { ArchiveFormat.detect(fileName: archiveURL.lastPathComponent) != nil }

    /// Provede změny přepsáním archivu (přes dočasný soubor a atomickou výměnu).
    func apply(_ changes: Changes, control: OperationControl = OperationControl(),
               progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        guard let format = ArchiveFormat.detect(fileName: archiveURL.lastPathComponent) else {
            var r = OperationReport()
            r.failures.append(.init(url: archiveURL, message: "Tento formát archivu nelze upravovat (jen čtení)"))
            return r
        }
        return ArchiveWriter.rewrite(source: archiveURL, destination: archiveURL, format: format, changes: changes,
                                     control: control, progress: progress, replaceInPlace: true)
    }
}
