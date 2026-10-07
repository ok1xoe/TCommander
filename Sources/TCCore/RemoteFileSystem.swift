import CCurl
import Foundation

public struct RemoteConnection: Sendable, Equatable {
    public enum Security: String, Sendable, CaseIterable, Codable {
        case none = "Bez šifrování", explicitTLS = "Explicitní TLS (AUTH TLS)", implicitTLS = "Implicitní TLS (FTPS)"
    }
    public var host: String
    public var port: Int?
    public var user: String
    public var password: String
    public var security: Security
    public var allowSelfSigned: Bool
    public var initialPath: String

    public init(host: String, port: Int? = nil, user: String = "anonymous", password: String = "anonymous@",
                security: Security = .none, allowSelfSigned: Bool = false, initialPath: String = "/") {
        self.host = host; self.port = port; self.user = user; self.password = password
        self.security = security; self.allowSelfSigned = allowSelfSigned; self.initialPath = initialPath
    }

    public var displayName: String { "ftp\(security == .none ? "" : "s")://\(user.isEmpty ? "" : user + "@")\(host)\(port.map { ":\($0)" } ?? "")" }
}

public struct RemoteError: LocalizedError {
    public let code: Int32
    public let message: String
    public var errorDescription: String? { message }
}

/// Jeden záznam z výpisu adresáře FTP serveru.
public struct ParsedListEntry: Equatable, Sendable {
    public var name: String
    public var isDirectory: Bool
    public var isSymlink: Bool
    public var size: Int64
    public var modified: Date?
    public var permissions: UInt16
}

public enum FTPListParser {
    public static func parse(_ text: String, mlsd: Bool, now: Date = Date()) -> [ParsedListEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let line = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            guard !line.isEmpty else { return nil }
            let e = mlsd ? parseMLSD(line) : (parseUnix(line, now: now) ?? parseDOS(line))
            guard let e, e.name != ".", e.name != "..", !e.name.isEmpty else { return nil }
            return e
        }
    }

    // type=file;size=12;modify=20260101010101;perm=r; název
    static func parseMLSD(_ line: String) -> ParsedListEntry? {
        guard let sp = line.firstIndex(of: " ") else { return nil }
        let facts = line[..<sp].split(separator: ";")
        let name = String(line[line.index(after: sp)...])
        var type = "file", size: Int64 = 0, modified: Date?, perm: UInt16 = 0o644
        for f in facts {
            guard let eq = f.firstIndex(of: "=") else { continue }
            let k = f[..<eq].lowercased(), v = String(f[f.index(after: eq)...])
            switch k {
            case "type": type = v.lowercased()
            case "size", "sizd": size = Int64(v) ?? 0
            case "modify": modified = mlsdDate(v)
            case "unix.mode": if let m = UInt16(v, radix: 8) { perm = m & 0o777 }
            default: break
            }
        }
        if type == "cdir" || type == "pdir" { return nil }
        return ParsedListEntry(name: name, isDirectory: type == "dir", isSymlink: type.contains("symlink"),
                               size: type == "dir" ? 0 : size, modified: modified, permissions: perm)
    }

    static func mlsdDate(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = s.contains(".") ? "yyyyMMddHHmmss.SSS" : "yyyyMMddHHmmss"
        return f.date(from: s)
    }

    private static let unixRegex = try! NSRegularExpression(
        pattern: #"^([\-dlbcps])([rwxsStT\-]{9})[+@.]?\s+\d+\s+(?:\S+\s+){1,2}?(\d+)\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4}|\d{1,2}:\d{2})\s+(.+)$"#)

    static func parseUnix(_ line: String, now: Date) -> ParsedListEntry? {
        let ns = line as NSString
        guard let m = unixRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func g(_ i: Int) -> String { ns.substring(with: m.range(at: i)) }
        let type = g(1)
        var name = g(7)
        let isLink = type == "l"
        if isLink, let r = name.range(of: " -> ") { name = String(name[..<r.lowerBound]) }
        var perm: UInt16 = 0
        for (i, c) in g(2).enumerated() where c != "-" && c != "S" && c != "T" { perm |= 1 << UInt16(8 - i) }
        return ParsedListEntry(name: name, isDirectory: type == "d", isSymlink: isLink, size: Int64(g(3)) ?? 0,
                               modified: unixDate(month: g(4), day: g(5), yearOrTime: g(6), now: now), permissions: perm)
    }

    static func unixDate(month: String, day: String, yearOrTime: String, now: Date) -> Date? {
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let mi = months.firstIndex(of: month.lowercased()), let d = Int(day) else { return nil }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents(); comps.month = mi + 1; comps.day = d
        if yearOrTime.contains(":") {
            let hm = yearOrTime.split(separator: ":"); comps.hour = Int(hm[0]); comps.minute = Int(hm[1])
            comps.year = cal.component(.year, from: now)
            if let date = cal.date(from: comps), date > now.addingTimeInterval(86_400) { comps.year! -= 1 }   // čas bez roku = poslední rok
        } else { comps.year = Int(yearOrTime) }
        return cal.date(from: comps)
    }

    private static let dosRegex = try! NSRegularExpression(pattern: #"^(\d{2})-(\d{2})-(\d{2,4})\s+(\d{1,2}):(\d{2})\s*([AP]M)?\s+(<DIR>|\d+)\s+(.+)$"#)

    static func parseDOS(_ line: String) -> ParsedListEntry? {
        let ns = line as NSString
        guard let m = dosRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func g(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        var year = Int(g(3)) ?? 0; if year < 100 { year += year < 70 ? 2000 : 1900 }
        var hour = Int(g(4)) ?? 0
        if g(6) == "PM" && hour < 12 { hour += 12 }; if g(6) == "AM" && hour == 12 { hour = 0 }
        let date = cal.date(from: DateComponents(year: year, month: Int(g(1)), day: Int(g(2)), hour: hour, minute: Int(g(5))))
        let isDir = g(7) == "<DIR>"
        return ParsedListEntry(name: g(8), isDirectory: isDir, isSymlink: false, size: isDir ? 0 : Int64(g(7)) ?? 0, modified: date, permissions: isDir ? 0o755 : 0o644)
    }
}

/// FTP/FTPS souborový systém přes libcurl. Cesty jsou relativní k přihlašovacímu adresáři ("/" = domovský adresář).
public final class RemoteFileSystem: VirtualFileSystem, @unchecked Sendable {
    public let connection: RemoteConnection
    private let lock = NSLock()
    private var mlsdSupported = true
    private static let initOnce: Void = { _ = mc_global_init() }()

    public init(connection: RemoteConnection) {
        self.connection = connection
        _ = Self.initOnce
    }

    // MARK: URL a volání libcurl

    func normalize(_ url: URL) -> String { Self.normalize(url.path) }

    static func normalize(_ p: String) -> String {
        let parts = p.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
        return "/" + parts.joined(separator: "/")
    }

    func urlString(_ path: String, directory: Bool) -> String {
        let scheme = connection.security == .implicitTLS ? "ftps" : "ftp"
        let comps = Self.normalize(path).split(separator: "/").map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? String($0) }
        var s = "\(scheme)://\(connection.host)"
        if let p = connection.port { s += ":\(p)" }
        s += "/" + comps.joined(separator: "/")
        if directory && !s.hasSuffix("/") { s += "/" }
        return s
    }

    private func withOpts<T>(timeout: Long = 0, _ body: (UnsafePointer<mc_opts>) -> T) -> T {
        connection.user.withCString { u in
            connection.password.withCString { p in
                var o = mc_opts(user: u, password: p, tls: connection.security == .none ? 0 : 1,
                                insecure: connection.allowSelfSigned ? 1 : 0, connect_timeout: 15, low_speed_timeout: timeout)
                return withUnsafePointer(to: &o) { body($0) }
            }
        }
    }

    typealias Long = Int

    private func errorString(_ buf: [CChar]) -> String { String(cString: buf) }

    private func list(path: String, mlsd: Bool) throws -> String {
        var out: UnsafeMutablePointer<CChar>?
        var len = 0
        var err = [CChar](repeating: 0, count: 256)
        let rc = urlString(path, directory: true).withCString { url in
            withOpts { mc_list($0, url, mlsd ? 1 : 0, &out, &len, &err, err.count) }
        }
        guard rc == 0, let out else { throw RemoteError(code: rc, message: errorString(err).isEmpty ? "Chyba FTP (\(rc))" : errorString(err)) }
        defer { mc_free(out) }
        let data = Data(bytes: out, count: len)
        return TextDecoding.decode(data).text
    }

    /// Chyby spojení a přihlášení se nemají zkoušet znovu příkazem LIST.
    private static let fatalCodes: Set<Int32> = [5, 6, 7, 9, 28, 35, 51, 58, 60, 67]

    // MARK: VirtualFileSystem

    public func list(_ dir: URL, includeHidden: Bool) throws -> [FileEntry] {
        let path = normalize(dir)
        lock.lock(); let tryMLSD = mlsdSupported; lock.unlock()
        var text = "", usedMLSD = false
        if tryMLSD {
            do { text = try list(path: path, mlsd: true); usedMLSD = true }
            catch let e as RemoteError where !Self.fatalCodes.contains(e.code) {
                lock.lock(); mlsdSupported = false; lock.unlock()
            }
        }
        if !usedMLSD { text = try list(path: path, mlsd: false) }
        return FTPListParser.parse(text, mlsd: usedMLSD).compactMap { p in
            let name = p.name
            let e = FileEntry(url: URL(fileURLWithPath: path == "/" ? "/" + name : path + "/" + name), name: name, isDirectory: p.isDirectory,
                              isSymlink: p.isSymlink, isHidden: name.hasPrefix("."), size: p.size, modified: p.modified, permissions: p.permissions)
            return includeHidden || !e.isHidden ? e : nil
        }
    }

    public func stat(_ url: URL) throws -> FileEntry {
        let path = normalize(url)
        if path == "/" { return FileEntry(url: URL(fileURLWithPath: "/"), name: "/", isDirectory: true) }
        let parent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        guard let e = try list(URL(fileURLWithPath: parent), includeHidden: true).first(where: { $0.name == name }) else {
            throw RemoteError(code: 78, message: "Na serveru neexistuje: \(path)")
        }
        return e
    }

    public func exists(_ url: URL) -> Bool { (try? stat(url)) != nil }

    private func run(_ commands: [String]) throws {
        var err = [CChar](repeating: 0, count: 256)
        let rc: Int32 = urlString("/", directory: true).withCString { url in
            var cstrs = commands.map { strdup($0) }
            defer { cstrs.forEach { free($0) } }
            return cstrs.withUnsafeMutableBufferPointer { buf in
                buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { ptr in
                    withOpts { mc_command($0, url, ptr, Int32(commands.count), &err, err.count) }
                }
            }
        }
        if rc != 0 { throw RemoteError(code: rc, message: errorString(err).isEmpty ? "Chyba FTP (\(rc))" : errorString(err)) }
    }

    private func rel(_ path: String) -> String { String(Self.normalize(path).dropFirst()) }

    public func createDirectory(_ url: URL) throws {
        var acc = ""
        for c in Self.normalize(url.path).split(separator: "/") {
            acc += "/" + c
            if !exists(URL(fileURLWithPath: acc)) { try run(["MKD " + rel(acc)]) }
        }
    }

    public func createFile(_ url: URL) throws {
        guard !exists(url) else { throw RemoteError(code: 0, message: "Soubor už existuje") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try uploadFile(local: tmp, remotePath: normalize(url), progress: nil)
    }

    public func copy(_ src: URL, to dst: URL) throws { throw RemoteError(code: 0, message: "Kopie na serveru není podporována; použijte stažení a nahrání") }
    public func move(_ src: URL, to dst: URL) throws { try run(["RNFR " + rel(src.path), "RNTO " + rel(dst.path)]) }
    public func trash(_ url: URL) throws { try remove(url) }

    public func remove(_ url: URL) throws {
        let e = try stat(url)
        if e.isDirectory && !e.isSymlink {
            for c in try list(url, includeHidden: true) { try remove(c.url) }
            try run(["RMD " + rel(url.path)])
        } else {
            try run(["DELE " + rel(url.path)])
        }
    }

    // MARK: Přenos dat

    final class ProgressBox { let handler: (Int64, Int64) -> Bool; init(_ h: @escaping (Int64, Int64) -> Bool) { handler = h } }

    private static let progressCallback: mc_progress_fn = { ctx, now, total in
        guard let ctx else { return 0 }
        return Unmanaged<ProgressBox>.fromOpaque(ctx).takeUnretainedValue().handler(now, total) ? 0 : 1
    }

    func downloadFile(remotePath: String, local: URL, resumeFrom: Int64, progress: ((Int64, Int64) -> Bool)?) throws {
        var err = [CChar](repeating: 0, count: 256)
        let box = ProgressBox(progress ?? { _, _ in true })
        let rc: Int32 = urlString(remotePath, directory: false).withCString { url in
            local.path.withCString { lp in
                withOpts(timeout: 60) { mc_download($0, url, lp, resumeFrom, Self.progressCallback, Unmanaged.passUnretained(box).toOpaque(), &err, err.count) }
            }
        }
        if rc != 0 { throw RemoteError(code: rc, message: rc == Int32(MC_ABORTED) ? "Přerušeno" : (errorString(err).isEmpty ? "Chyba FTP (\(rc))" : errorString(err))) }
    }

    func uploadFile(local: URL, remotePath: String, progress: ((Int64, Int64) -> Bool)?) throws {
        var err = [CChar](repeating: 0, count: 256)
        let box = ProgressBox(progress ?? { _, _ in true })
        let rc: Int32 = urlString(remotePath, directory: false).withCString { url in
            local.path.withCString { lp in
                withOpts(timeout: 60) { mc_upload($0, url, lp, Self.progressCallback, Unmanaged.passUnretained(box).toOpaque(), &err, err.count) }
            }
        }
        if rc != 0 { throw RemoteError(code: rc, message: rc == Int32(MC_ABORTED) ? "Přerušeno" : (errorString(err).isEmpty ? "Chyba FTP (\(rc))" : errorString(err))) }
    }

    /// Soubory a bajty ve stromu na serveru.
    public func scan(_ path: String) -> (files: Int, bytes: Int64) {
        guard let e = try? stat(URL(fileURLWithPath: path)) else { return (0, 0) }
        if !e.isDirectory || e.isSymlink { return (1, e.size) }
        var files = 0, bytes: Int64 = 0
        for c in (try? list(URL(fileURLWithPath: path), includeHidden: true)) ?? [] {
            let s = scan(c.url.path); files += s.files; bytes += s.bytes
        }
        return (files, bytes)
    }
}

public enum RemoteTransfer {
    private static let partSuffix = ".macTCpart"

    /// Stáhne položky ze serveru do `dest` (adresáře); rozpracované soubory `.macTCpart` se příště obnoví.
    public static func download(_ fs: RemoteFileSystem, _ paths: [String], to dest: URL, policy: ConflictPolicy = .overwrite,
                                control: OperationControl = OperationControl(),
                                progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        var report = OperationReport()
        var p = TransferProgress()
        for path in paths { let s = fs.scan(path); p.filesTotal += s.files; p.bytesTotal += s.bytes }
        let helper = FileOperations()
        func emit() { progress?(p) }
        emit()

        func fetch(_ remote: URL, into dir: URL, top: Bool) throws {
            guard control.checkpoint() else { throw CancellationError() }
            let e = try fs.stat(remote)
            var local = dir.appendingPathComponent(e.name)
            let fm = FileManager.default
            if e.isDirectory && !e.isSymlink {
                try fm.createDirectory(at: local, withIntermediateDirectories: true)
                for c in try fs.list(remote, includeHidden: true) { try fetch(c.url, into: local, top: false) }
                if let m = e.modified { try? fm.setAttributes([.modificationDate: m], ofItemAtPath: local.path) }
                if top { report.succeeded += 1 }
                return
            }
            if fm.fileExists(atPath: local.path) {
                switch policy {
                case .skip: report.skipped += 1; p.bytesDone += e.size; p.filesDone += 1; emit(); return
                case .overwriteOlder:
                    let d = (try? fm.attributesOfItem(atPath: local.path)[.modificationDate] as? Date) ?? .distantPast
                    if (e.modified ?? .distantPast) <= d { report.skipped += 1; p.bytesDone += e.size; p.filesDone += 1; emit(); return }
                    try fm.removeItem(at: local)
                case .overwrite: try fm.removeItem(at: local)
                case .keepBoth: local = helper.uniqueName(local)
                }
            }
            let part = local.deletingLastPathComponent().appendingPathComponent(local.lastPathComponent + partSuffix)
            var resume: Int64 = 0
            if let a = try? fm.attributesOfItem(atPath: part.path), let s = (a[.size] as? NSNumber)?.int64Value {
                if s < e.size { resume = s } else { try? fm.removeItem(at: part) }
            }
            let base = p.bytesDone + resume
            p.current = e.name
            p.bytesDone = base
            do {
                try fs.downloadFile(remotePath: remote.path, local: part, resumeFrom: resume) { now, _ in
                    p.bytesDone = base + now; emit()
                    return control.checkpoint()
                }
            } catch let err as RemoteError where err.code == Int32(MC_ABORTED) { throw CancellationError() }
            try fm.moveItem(at: part, to: local)
            if let m = e.modified { try? fm.setAttributes([.modificationDate: m], ofItemAtPath: local.path) }
            p.bytesDone = base - resume + e.size
            p.filesDone += 1; emit()
            if top { report.succeeded += 1 }
        }

        do {
            for path in paths { try fetch(URL(fileURLWithPath: path), into: dest, top: true) }
        } catch is CancellationError { report.cancelled = true }
        catch { report.failures.append(.init(url: dest, message: error.localizedDescription)) }
        emit()
        return report
    }

    /// Nahraje místní soubory a složky do adresáře `remoteDir` na serveru.
    public static func upload(_ fs: RemoteFileSystem, _ locals: [URL], into remoteDir: String, policy: ConflictPolicy = .overwrite,
                              control: OperationControl = OperationControl(),
                              progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        var report = OperationReport()
        var p = TransferProgress()
        let ops = FileOperations()
        for u in locals { let s = ops.scan(u); p.filesTotal += s.files; p.bytesTotal += s.bytes }
        func emit() { progress?(p) }
        emit()
        let local = LocalFileSystem()
        var listings: [String: [String: FileEntry]] = [:]

        func existing(_ dir: String) -> [String: FileEntry] {
            if let c = listings[dir] { return c }
            let m = Dictionary(((try? fs.list(URL(fileURLWithPath: dir), includeHidden: true)) ?? []).map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
            listings[dir] = m
            return m
        }

        func put(_ url: URL, into dir: String, top: Bool) throws {
            guard control.checkpoint() else { throw CancellationError() }
            let info = try local.stat(url)
            var name = info.name
            let remoteEntry = existing(dir)[name]
            if info.isDirectory && !info.isSymlink {
                let target = (dir == "/" ? "" : dir) + "/" + name
                if remoteEntry == nil { try fs.createDirectory(URL(fileURLWithPath: target)); listings[dir] = nil }
                for c in try local.list(url, includeHidden: true) { try put(c.url, into: target, top: false) }
                if top { report.succeeded += 1 }
                return
            }
            if let r = remoteEntry {
                switch policy {
                case .skip: report.skipped += 1; p.bytesDone += info.size; p.filesDone += 1; emit(); return
                case .overwriteOlder:
                    if (info.modified ?? .distantPast) <= (r.modified ?? .distantPast) { report.skipped += 1; p.bytesDone += info.size; p.filesDone += 1; emit(); return }
                case .overwrite: break
                case .keepBoth:
                    var n = 1; let ext = (name as NSString).pathExtension; let base = (name as NSString).deletingPathExtension
                    repeat { name = ext.isEmpty ? "\(base) copy\(n == 1 ? "" : " \(n)")" : "\(base) copy\(n == 1 ? "" : " \(n)").\(ext)"; n += 1 } while existing(dir)[name] != nil
                }
            }
            p.current = name
            let base = p.bytesDone
            do {
                try fs.uploadFile(local: url, remotePath: (dir == "/" ? "" : dir) + "/" + name) { now, _ in
                    p.bytesDone = base + now; emit()
                    return control.checkpoint()
                }
            } catch let err as RemoteError where err.code == Int32(MC_ABORTED) { throw CancellationError() }
            listings[dir] = nil
            p.bytesDone = base + info.size
            p.filesDone += 1; emit()
            if top { report.succeeded += 1 }
        }

        do { for u in locals { try put(u, into: RemoteFileSystem.normalize(remoteDir), top: true) } }
        catch is CancellationError { report.cancelled = true }
        catch { report.failures.append(.init(url: locals.first ?? URL(fileURLWithPath: "/"), message: error.localizedDescription)) }
        emit()
        return report
    }
}
