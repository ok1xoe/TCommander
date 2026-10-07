import Foundation

public enum ConflictPolicy: Sendable { case overwrite, overwriteOlder, skip, keepBoth }
public enum TransferKind: Sendable { case copy, move }

public struct TransferItem: Sendable, Hashable {
    public let source: URL
    public let destination: URL
    public init(source: URL, destination: URL) { self.source = source; self.destination = destination }
}

public struct OperationReport: Sendable {
    public struct Failure: Sendable { public let url: URL; public let message: String }
    public var succeeded = 0
    public var skipped = 0
    public var failures: [Failure] = []
    public init() {}
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

    public func perform(_ kind: TransferKind, _ items: [TransferItem], policy: ConflictPolicy,
                        isCancelled: @Sendable () -> Bool = { false }) -> OperationReport {
        var report = OperationReport()
        for item in items {
            if isCancelled() { break }
            transfer(kind, item.source, item.destination, policy, &report, top: true)
        }
        return report
    }

    private func transfer(_ kind: TransferKind, _ src: URL, _ dstIn: URL, _ policy: ConflictPolicy,
                          _ report: inout OperationReport, top: Bool) {
        var dst = dstIn
        let s = src.standardizedFileURL.path, d = dst.standardizedFileURL.path
        if s == d {
            if kind == .copy && policy == .keepBoth { dst = uniqueName(dst) }
            else if kind == .move { report.skipped += 1; return }
            else { report.failures.append(.init(url: src, message: "Zdroj a cíl jsou totožné")); return }
        }
        if d.hasPrefix(s + "/") {
            report.failures.append(.init(url: src, message: "Adresář nelze přesunout ani kopírovat do sebe sama")); return
        }
        do {
            let srcEntry = try fs.stat(src)
            if fs.exists(dst) {
                let dstEntry = try fs.stat(dst)
                if policy == .keepBoth {
                    dst = uniqueName(dst)
                } else if srcEntry.isDirectory && dstEntry.isDirectory && !srcEntry.isSymlink {
                    // sloučení adresářů
                    for child in try fs.list(src, includeHidden: true) {
                        transfer(kind, child.url, dst.appendingPathComponent(child.name), policy, &report, top: false)
                    }
                    if kind == .move, (try? fs.list(src, includeHidden: true).isEmpty) == true { try fs.remove(src) }
                    if top { report.succeeded += 1 }
                    return
                } else if srcEntry.isDirectory != dstEntry.isDirectory {
                    report.failures.append(.init(url: src, message: "Typ cíle (soubor/adresář) nesouhlasí")); return
                } else {
                    switch policy {
                    case .skip: report.skipped += 1; return
                    case .overwriteOlder:
                        if (srcEntry.modified ?? .distantPast) <= (dstEntry.modified ?? .distantPast) { report.skipped += 1; return }
                        try fs.remove(dst)
                    case .overwrite: try fs.remove(dst)
                    case .keepBoth: break
                    }
                }
            }
            switch kind {
            case .copy: try fs.copy(src, to: dst)
            case .move: try fs.move(src, to: dst)
            }
            report.succeeded += 1
        } catch {
            report.failures.append(.init(url: src, message: error.localizedDescription))
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

    public func delete(_ urls: [URL], toTrash: Bool) -> OperationReport {
        var report = OperationReport()
        for u in urls {
            do { try (toTrash ? fs.trash(u) : fs.remove(u)); report.succeeded += 1 }
            catch { report.failures.append(.init(url: u, message: error.localizedDescription)) }
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
