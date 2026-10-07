import Darwin
import Foundation

public enum ConflictPolicy: Sendable { case overwrite, overwriteOlder, skip, keepBoth }
public enum TransferKind: Sendable { case copy, move }

public struct TransferItem: Sendable, Hashable {
    public let source: URL
    public let destination: URL
    public init(source: URL, destination: URL) { self.source = source; self.destination = destination }
}

public struct OperationReport: Sendable {
    public struct Failure: Sendable {
        public let url: URL; public let message: String
        public init(url: URL, message: String) { self.url = url; self.message = message }
    }
    public var succeeded = 0
    public var skipped = 0
    public var cancelled = false
    public var failures: [Failure] = []
    public init() {}
}

public struct TransferProgress: Sendable, Equatable {
    public var current = ""
    public var bytesDone: Int64 = 0
    public var bytesTotal: Int64 = 0
    public var filesDone = 0
    public var filesTotal = 0
    public init() {}
    public var fraction: Double { bytesTotal > 0 ? min(1, Double(bytesDone) / Double(bytesTotal)) : (filesTotal > 0 ? Double(filesDone) / Double(filesTotal) : 0) }
}

/// Řízení běžící operace z jiného vlákna: pozastavení, pokračování a zrušení.
public final class OperationControl: @unchecked Sendable {
    private let cond = NSCondition()
    private var cancelled = false
    private var paused = false
    public init() {}

    public func cancel() { cond.lock(); cancelled = true; paused = false; cond.broadcast(); cond.unlock() }
    public func pause() { cond.lock(); paused = true; cond.unlock() }
    public func resume() { cond.lock(); paused = false; cond.broadcast(); cond.unlock() }
    public var isCancelled: Bool { cond.lock(); defer { cond.unlock() }; return cancelled }
    public var isPaused: Bool { cond.lock(); defer { cond.unlock() }; return paused }

    /// Při pauze čeká; vrací false, pokud byla operace zrušena.
    public func checkpoint() -> Bool {
        cond.lock(); defer { cond.unlock() }
        while paused && !cancelled { cond.wait() }
        return !cancelled
    }
}

private struct PosixFailure: LocalizedError {
    let code: Int32
    var errorDescription: String? { String(cString: strerror(code)) }
}

private final class Tracker {
    var p = TransferProgress()
    let handler: (@Sendable (TransferProgress) -> Void)?
    var last = Date.distantPast
    init(handler: (@Sendable (TransferProgress) -> Void)?) { self.handler = handler }

    func add(bytes: Int64) { p.bytesDone += bytes; emit() }
    func fileFinished(_ n: Int = 1) { p.filesDone += n; emit() }
    func emit(force: Bool = false) {
        guard let handler else { return }
        let now = Date()
        if force || now.timeIntervalSince(last) > 0.05 { last = now; handler(p) }
    }
}

private final class Context {
    var report = OperationReport()
    let control: OperationControl
    let tracker: Tracker
    let verify: Bool
    init(control: OperationControl, tracker: Tracker, verify: Bool) { self.control = control; self.tracker = tracker; self.verify = verify }
}

public struct FileOperations: Sendable {
    public let fs: any VirtualFileSystem
    public init(fs: any VirtualFileSystem = LocalFileSystem()) { self.fs = fs }

    /// Každý zdroj do adresáře `dir` pod stejným názvem.
    public func plan(sources: [URL], into dir: URL) -> [TransferItem] {
        sources.map { TransferItem(source: $0, destination: dir.appendingPathComponent($0.lastPathComponent)) }
    }

    public func conflicts(_ items: [TransferItem]) -> [TransferItem] {
        items.filter { fs.exists($0.destination) }
    }

    /// Spočítá soubory a bajty ve stromu (symlinky se nenásledují).
    public func scan(_ url: URL) -> (files: Int, bytes: Int64) {
        guard let e = try? fs.stat(url) else { return (0, 0) }
        if !e.isDirectory || e.isSymlink { return (1, e.isSymlink ? 0 : e.size) }
        var files = 0, bytes: Int64 = 0
        for child in (try? fs.list(url, includeHidden: true)) ?? [] {
            let s = scan(child.url); files += s.files; bytes += s.bytes
        }
        return (files, bytes)
    }

    public func perform(_ kind: TransferKind, _ items: [TransferItem], policy: ConflictPolicy, verify: Bool = false,
                        control: OperationControl = OperationControl(),
                        progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        let tracker = Tracker(handler: progress)
        for item in items {
            let s = scan(item.source)
            tracker.p.filesTotal += s.files
            tracker.p.bytesTotal += s.bytes * (verify && kind == .copy ? 3 : 1)
        }
        let ctx = Context(control: control, tracker: tracker, verify: verify)
        tracker.emit(force: true)
        for item in items {
            if !control.checkpoint() { ctx.report.cancelled = true; break }
            transfer(kind, item.source, item.destination, policy, ctx, top: true)
        }
        tracker.emit(force: true)
        return ctx.report
    }

    private func skipAccounting(_ src: URL, _ ctx: Context) {
        let s = scan(src)
        ctx.tracker.add(bytes: s.bytes); ctx.tracker.fileFinished(s.files)
    }

    private func transfer(_ kind: TransferKind, _ src: URL, _ dstIn: URL, _ policy: ConflictPolicy,
                          _ ctx: Context, top: Bool) {
        guard ctx.control.checkpoint() else { ctx.report.cancelled = true; return }
        var dst = dstIn
        let s = src.standardizedFileURL.path, d = dst.standardizedFileURL.path
        if s == d {
            if kind == .copy && policy == .keepBoth { dst = uniqueName(dst) }
            else if kind == .move { ctx.report.skipped += 1; skipAccounting(src, ctx); return }
            else { ctx.report.failures.append(.init(url: src, message: "Zdroj a cíl jsou totožné")); skipAccounting(src, ctx); return }
        }
        if d.hasPrefix(s + "/") {
            ctx.report.failures.append(.init(url: src, message: "Adresář nelze přesunout ani kopírovat do sebe sama")); return
        }
        let failuresBefore = ctx.report.failures.count
        do {
            let srcEntry = try fs.stat(src)
            if fs.exists(dst) {
                let dstEntry = try fs.stat(dst)
                if policy == .keepBoth {
                    dst = uniqueName(dst)
                } else if srcEntry.isDirectory && dstEntry.isDirectory && !srcEntry.isSymlink {
                    // sloučení adresářů
                    for child in try fs.list(src, includeHidden: true) {
                        transfer(kind, child.url, dst.appendingPathComponent(child.name), policy, ctx, top: false)
                    }
                    if kind == .move, !ctx.report.cancelled, (try? fs.list(src, includeHidden: true).isEmpty) == true { try fs.remove(src) }
                    if top && ctx.report.failures.count == failuresBefore && !ctx.report.cancelled { ctx.report.succeeded += 1 }
                    return
                } else if srcEntry.isDirectory != dstEntry.isDirectory {
                    ctx.report.failures.append(.init(url: src, message: "Typ cíle (soubor/adresář) nesouhlasí"))
                    skipAccounting(src, ctx); return
                } else {
                    switch policy {
                    case .skip: ctx.report.skipped += 1; skipAccounting(src, ctx); return
                    case .overwriteOlder:
                        if (srcEntry.modified ?? .distantPast) <= (dstEntry.modified ?? .distantPast) {
                            ctx.report.skipped += 1; skipAccounting(src, ctx); return
                        }
                        try fs.remove(dst)
                    case .overwrite: try fs.remove(dst)
                    case .keepBoth: break
                    }
                }
            }
            try place(kind, src, dst, srcEntry, ctx)
            if top { ctx.report.succeeded += 1 }
        } catch is CancellationError {
            ctx.report.cancelled = true
        } catch {
            ctx.report.failures.append(.init(url: src, message: error.localizedDescription))
        }
    }

    /// Přesun zkusí `rename` (okamžité na stejném svazku), jinak kopíruje a zdroj smaže.
    private func place(_ kind: TransferKind, _ src: URL, _ dst: URL, _ entry: FileEntry, _ ctx: Context) throws {
        if kind == .move {
            let s = entry.isDirectory && !entry.isSymlink ? scan(src) : (1, entry.size)
            if Darwin.rename(src.path, dst.path) == 0 {
                ctx.tracker.add(bytes: s.1); ctx.tracker.fileFinished(s.0); return
            }
            if errno != EXDEV { throw PosixFailure(code: errno) }
        }
        try copyTree(src, dst, entry, ctx)
        if kind == .move { try fs.remove(src) }
    }

    private func copyTree(_ src: URL, _ dst: URL, _ entry: FileEntry, _ ctx: Context) throws {
        guard ctx.control.checkpoint() else { throw CancellationError() }
        ctx.tracker.p.current = src.lastPathComponent
        if entry.isSymlink {
            let target = try FileManager.default.destinationOfSymbolicLink(atPath: src.path)
            try FileManager.default.createSymbolicLink(atPath: dst.path, withDestinationPath: target)
            ctx.tracker.fileFinished()
        } else if entry.isDirectory {
            try fs.createDirectory(dst)
            for child in try fs.list(src, includeHidden: true) {
                try copyTree(child.url, dst.appendingPathComponent(child.name), child, ctx)
            }
            _ = copyfile(src.path, dst.path, nil, copyfile_flags_t(COPYFILE_STAT | COPYFILE_XATTR))
        } else {
            try copyFile(src, dst, entry.size, ctx)
            ctx.tracker.fileFinished()
        }
    }

    private func copyFile(_ src: URL, _ dst: URL, _ size: Int64, _ ctx: Context) throws {
        if clonefile(src.path, dst.path, 0) == 0 {      // APFS: okamžitý klon
            ctx.tracker.add(bytes: size)
        } else {
            let inFd = open(src.path, O_RDONLY)
            guard inFd >= 0 else { throw PosixFailure(code: errno) }
            defer { close(inFd) }
            let outFd = open(dst.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard outFd >= 0 else { throw PosixFailure(code: errno) }
            let bufSize = 1 << 20
            let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 16)
            defer { buf.deallocate() }
            do {
                while true {
                    guard ctx.control.checkpoint() else { throw CancellationError() }
                    let n = read(inFd, buf, bufSize)
                    if n < 0 { throw PosixFailure(code: errno) }
                    if n == 0 { break }
                    var written = 0
                    while written < n {
                        let w = write(outFd, buf + written, n - written)
                        if w < 0 { throw PosixFailure(code: errno) }
                        written += w
                    }
                    ctx.tracker.add(bytes: Int64(n))
                }
                close(outFd)
            } catch {
                close(outFd); unlink(dst.path); throw error
            }
            _ = copyfile(src.path, dst.path, nil, copyfile_flags_t(COPYFILE_STAT | COPYFILE_XATTR))
        }
        if ctx.verify {
            let a = Checksum.hash(src, .sha256) { n in ctx.tracker.add(bytes: Int64(n)); return ctx.control.checkpoint() }
            let b = Checksum.hash(dst, .sha256) { n in ctx.tracker.add(bytes: Int64(n)); return ctx.control.checkpoint() }
            guard let a, let b else { unlink(dst.path); throw CancellationError() }
            if a != b { unlink(dst.path); throw NSError(domain: "macTC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ověření kopie selhalo (nesouhlasí kontrolní součet)"]) }
        }
    }

    public func uniqueName(_ url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var n = 1
        while true {
            let suffix = n == 1 ? " copy" : " copy \(n)"
            let name = ext.isEmpty ? base + suffix : base + suffix + "." + ext
            let candidate = dir.appendingPathComponent(name)
            if !fs.exists(candidate) { return candidate }
            n += 1
        }
    }

    public func delete(_ urls: [URL], toTrash: Bool, control: OperationControl = OperationControl(),
                       progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        var report = OperationReport()
        var p = TransferProgress(); p.filesTotal = urls.count
        for u in urls {
            if !control.checkpoint() { report.cancelled = true; break }
            p.current = u.lastPathComponent
            do { try (toTrash ? fs.trash(u) : fs.remove(u)); report.succeeded += 1 }
            catch { report.failures.append(.init(url: u, message: error.localizedDescription)) }
            p.filesDone += 1; progress?(p)
        }
        return report
    }

    public func rename(_ url: URL, to newName: String) throws -> URL {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else { throw CocoaError(.fileWriteInvalidFileName) }
        let dst = url.deletingLastPathComponent().appendingPathComponent(name)
        if dst.path == url.path { return url }
        guard !fs.exists(dst) else { throw CocoaError(.fileWriteFileExists) }
        try fs.move(url, to: dst)
        return dst
    }

    /// Vytvoří adresář (i vnořený "a/b/c") a vrátí URL nejvyšší vytvořené složky.
    public func makeDirectory(_ path: String, in dir: URL) throws -> URL {
        let comps = path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard let first = comps.first else { throw CocoaError(.fileWriteInvalidFileName) }
        let full = comps.reduce(dir) { $0.appendingPathComponent($1) }
        try fs.createDirectory(full)
        return dir.appendingPathComponent(first)
    }

    public func makeFile(named name: String, in dir: URL) throws -> URL {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !n.contains("/") else { throw CocoaError(.fileWriteInvalidFileName) }
        let url = dir.appendingPathComponent(n)
        try fs.createFile(url)
        return url
    }
}
