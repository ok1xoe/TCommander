import Foundation

// MARK: Soubory s kontrolními součty

public enum ChecksumFile {
    public struct Line: Equatable, Sendable { public let hash: String; public let name: String
        public init(hash: String, name: String) { self.hash = hash; self.name = name } }
    public enum Status: Equatable, Sendable { case ok, mismatch, missing }
    public struct Result: Equatable, Sendable { public let name: String; public let status: Status }

    public static func format(_ lines: [Line]) -> String { lines.map { "\($0.hash) *\($0.name)" }.joined(separator: "\n") + "\n" }

    /// Podporuje "hash  název", "hash *název"; řádky začínající # se přeskočí.
    public static func parse(_ text: String) -> [Line] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let l = raw.trimmingCharacters(in: .whitespaces)
            guard !l.isEmpty, !l.hasPrefix("#"), let sp = l.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
            var name = l[l.index(after: sp)...].trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("*") { name.removeFirst() }
            return name.isEmpty ? nil : Line(hash: String(l[..<sp]).lowercased(), name: name)
        }
    }

    public static func algorithm(forFileName name: String, firstHash: String? = nil) -> ChecksumAlgorithm? {
        switch (name as NSString).pathExtension.lowercased() {
        case "md5": return .md5
        case "sha1": return .sha1
        case "sha256": return .sha256
        case "sha512": return .sha512
        case "crc", "crc32", "sfv": return .crc32
        default:
            switch firstHash?.count { case 32: return .md5; case 40: return .sha1; case 64: return .sha256; case 128: return .sha512; case 8: return .crc32; default: return nil }
        }
    }

    public static func verify(sumFile: URL, onFile: (String) -> Void = { _ in }, isCancelled: () -> Bool = { false }) -> [Result]? {
        guard let data = try? Data(contentsOf: sumFile) else { return nil }
        let lines = parse(TextDecoding.decode(data).text)
        guard let alg = algorithm(forFileName: sumFile.lastPathComponent, firstHash: lines.first?.hash) else { return nil }
        let dir = sumFile.deletingLastPathComponent()
        var out: [Result] = []
        for l in lines {
            if isCancelled() { break }
            onFile(l.name)
            let f = dir.appendingPathComponent(l.name)
            guard FileManager.default.fileExists(atPath: f.path) else { out.append(.init(name: l.name, status: .missing)); continue }
            out.append(.init(name: l.name, status: Checksum.hash(f, alg) == l.hash ? .ok : .mismatch))
        }
        return out
    }
}

// MARK: Vlastnosti

public enum FileAttributes {
    public static func apply(_ url: URL, permissions: UInt16? = nil, modified: Date? = nil) throws {
        var a: [FileAttributeKey: Any] = [:]
        if let permissions { a[.posixPermissions] = NSNumber(value: permissions) }
        if let modified { a[.modificationDate] = modified }
        guard !a.isEmpty else { return }
        try FileManager.default.setAttributes(a, ofItemAtPath: url.path)
    }

    /// "755" nebo "0644" → 0o755; neplatný vstup → nil.
    public static func parseOctal(_ s: String) -> UInt16? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard (3...4).contains(t.count), t.allSatisfy({ ("0"..."7").contains($0) }), let v = UInt16(t, radix: 8) else { return nil }
        return v
    }
}

// MARK: Odkazy

public extension FileOperations {
    func makeSymlink(to target: String, at link: URL) throws {
        guard !fs.exists(link) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target)
    }

    func makeHardlink(to existing: URL, at link: URL) throws {
        guard !fs.exists(link) else { throw CocoaError(.fileWriteFileExists) }
        try FileManager.default.linkItem(at: existing, to: link)
    }
}

// MARK: Rozdělení a spojení souborů

public enum FileSplitter {
    public static func partName(_ base: String, _ n: Int) -> String { base + "." + String(format: "%03d", n) }

    /// Rozdělí soubor na části `název.001`, `název.002`, … do adresáře `dir`.
    public static func split(_ url: URL, partSize: Int64, into dir: URL, control: OperationControl = OperationControl(),
                             progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        var report = OperationReport()
        guard partSize > 0, let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value,
              let input = try? FileHandle(forReadingFrom: url) else {
            report.failures.append(.init(url: url, message: "Soubor nelze číst nebo je neplatná velikost části")); return report
        }
        defer { try? input.close() }
        var p = TransferProgress(); p.bytesTotal = size; p.filesTotal = Int((size + partSize - 1) / max(partSize, 1))
        var created: [URL] = []
        var index = 1
        do {
            while true {
                guard control.checkpoint() else { throw CancellationError() }
                let out = dir.appendingPathComponent(partName(url.lastPathComponent, index))
                if FileManager.default.fileExists(atPath: out.path) { throw CocoaError(.fileWriteFileExists) }
                FileManager.default.createFile(atPath: out.path, contents: nil)
                created.append(out)
                let w = try FileHandle(forWritingTo: out)
                var left = partSize
                var wrote: Int64 = 0
                while left > 0 {
                    guard control.checkpoint() else { try? w.close(); throw CancellationError() }
                    guard let d = try input.read(upToCount: Int(min(left, 1 << 20))), !d.isEmpty else { break }
                    try w.write(contentsOf: d); left -= Int64(d.count); wrote += Int64(d.count)
                    p.bytesDone += Int64(d.count); p.current = out.lastPathComponent; progress?(p)
                }
                try w.close()
                if wrote == 0 { try? FileManager.default.removeItem(at: out); created.removeLast(); break }
                p.filesDone += 1; progress?(p)
                if left > 0 { break }
                index += 1
            }
            report.succeeded = created.count
        } catch is CancellationError {
            report.cancelled = true
            created.forEach { try? FileManager.default.removeItem(at: $0) }
        } catch {
            report.failures.append(.init(url: url, message: error.localizedDescription))
            created.forEach { try? FileManager.default.removeItem(at: $0) }
        }
        return report
    }

    /// Z `název.001` najde všechny po sobě jdoucí části; jinak nil.
    public static func parts(ofFirst first: URL) -> (base: String, parts: [URL])? {
        let name = first.lastPathComponent
        guard name.hasSuffix(".001") else { return nil }
        let base = String(name.dropLast(4))
        var list: [URL] = []
        var n = 1
        while FileManager.default.fileExists(atPath: first.deletingLastPathComponent().appendingPathComponent(partName(base, n)).path) {
            list.append(first.deletingLastPathComponent().appendingPathComponent(partName(base, n))); n += 1
        }
        return list.isEmpty ? nil : (base, list)
    }

    public static func combine(first: URL, into dir: URL, control: OperationControl = OperationControl(),
                               progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        var report = OperationReport()
        guard let (base, parts) = parts(ofFirst: first) else {
            report.failures.append(.init(url: first, message: "Vyberte první část (název.001)")); return report
        }
        let out = dir.appendingPathComponent(base)
        guard !FileManager.default.fileExists(atPath: out.path) else {
            report.failures.append(.init(url: out, message: "Cílový soubor již existuje")); return report
        }
        let total = parts.reduce(Int64(0)) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? NSNumber)?.int64Value ?? 0) }
        var p = TransferProgress(); p.bytesTotal = total; p.filesTotal = parts.count
        FileManager.default.createFile(atPath: out.path, contents: nil)
        do {
            let w = try FileHandle(forWritingTo: out)
            defer { try? w.close() }
            for part in parts {
                let r = try FileHandle(forReadingFrom: part)
                defer { try? r.close() }
                p.current = part.lastPathComponent
                while let d = try r.read(upToCount: 1 << 20), !d.isEmpty {
                    guard control.checkpoint() else { throw CancellationError() }
                    try w.write(contentsOf: d); p.bytesDone += Int64(d.count); progress?(p)
                }
                p.filesDone += 1; progress?(p)
            }
            report.succeeded = 1
        } catch is CancellationError {
            report.cancelled = true; try? FileManager.default.removeItem(at: out)
        } catch {
            report.failures.append(.init(url: out, message: error.localizedDescription)); try? FileManager.default.removeItem(at: out)
        }
        return report
    }
}
