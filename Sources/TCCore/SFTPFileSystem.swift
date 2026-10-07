import Foundation

public struct SFTPConnection: Sendable, Equatable {
    public var host: String
    public var port: Int?
    public var user: String
    /// Heslo se předává přes SSH_ASKPASS (nikdy v příkazové řádce); prázdné = klíč nebo agent.
    public var password: String
    /// Soubor soukromého klíče; prázdné = výchozí klíče a ssh-agent.
    public var identityFile: String
    /// Soubor known_hosts; nil = výchozí (~/.ssh/known_hosts) s automatickým přijetím nového serveru.
    public var knownHostsFile: String?
    public var strictHostKeyChecking: String
    public var initialPath: String
    public var multiplex: Bool
    /// Proxy: socks5://host:port, socks4://host:port nebo http://host:port (přes nc); prázdné = bez proxy.
    public var proxy: String

    public init(host: String, port: Int? = nil, user: String, password: String = "", identityFile: String = "",
                knownHostsFile: String? = nil, strictHostKeyChecking: String = "accept-new", initialPath: String = "",
                multiplex: Bool = true, proxy: String = "") {
        self.proxy = proxy
        self.host = host; self.port = port; self.user = user; self.password = password; self.identityFile = identityFile
        self.knownHostsFile = knownHostsFile; self.strictHostKeyChecking = strictHostKeyChecking
        self.initialPath = initialPath; self.multiplex = multiplex
    }

    public var displayName: String { "sftp://\(user.isEmpty ? "" : user + "@")\(host)\(port.map { ":\($0)" } ?? "")" }

    /// ProxyCommand pro ssh podle adresy proxy (socks5://, socks4://, http://); nil pro prázdnou nebo neplatnou adresu.
    public static func proxyCommand(from proxy: String) -> String? {
        guard let c = URLComponents(string: proxy.trimmingCharacters(in: .whitespaces)), let host = c.host, !host.isEmpty, let port = c.port,
              let scheme = c.scheme?.lowercased() else { return nil }
        let kind: String
        switch scheme {
        case "socks5", "socks5h", "socks": kind = "5"
        case "socks4", "socks4a": kind = "4"
        case "http", "https": kind = "connect"
        default: return nil
        }
        return "/usr/bin/nc -X \(kind) -x \(host):\(port) %h %p"
    }
}

/// SFTP přes systémový `sftp` (OpenSSH). Cesty jsou absolutní cesty na serveru.
public final class SFTPFileSystem: RemoteFileSystemProtocol, @unchecked Sendable {
    public let connection: SFTPConnection
    public var displayName: String { connection.displayName }
    public var preservesTimesOnDownload: Bool { true }       // get -p / reget -p
    private let controlDir: URL
    private let askpass: URL?

    public init(connection: SFTPConnection) {
        self.connection = connection
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("macTC/ssh")
        try? FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        controlDir = caches
        if connection.password.isEmpty { askpass = nil } else {
            // pomocný skript vypíše heslo z proměnné prostředí; heslo se na disk nezapisuje
            let script = caches.appendingPathComponent("askpass-\(UUID().uuidString).sh")
            try? "#!/bin/sh\nprintf '%s\\n' \"$MACTC_SSH_PASSWORD\"\n".write(to: script, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            askpass = script
        }
    }

    deinit { if let askpass { try? FileManager.default.removeItem(at: askpass) } }

    // MARK: Spuštění sftp

    private var baseArguments: [String] {
        var a = ["-o", "StrictHostKeyChecking=\(connection.strictHostKeyChecking)", "-o", "ConnectTimeout=15",
                 "-o", "ServerAliveInterval=15", "-o", "LogLevel=ERROR"]
        if let kh = connection.knownHostsFile { a += ["-o", "UserKnownHostsFile=\(kh)"] }
        if let p = connection.port { a += ["-P", String(p)] }
        if !connection.identityFile.isEmpty { a += ["-i", connection.identityFile, "-o", "IdentitiesOnly=yes"] }
        if !connection.password.isEmpty {
            a += ["-o", "BatchMode=no", "-o", "PreferredAuthentications=password,keyboard-interactive", "-o", "NumberOfPasswordPrompts=1"]
        }
        if let pc = SFTPConnection.proxyCommand(from: connection.proxy) { a += ["-o", "ProxyCommand=\(pc)"] }
        if connection.multiplex {
            a += ["-o", "ControlMaster=auto", "-o", "ControlPath=\(controlDir.path)/%C", "-o", "ControlPersist=120"]
        }
        return a
    }

    private var target: String { (connection.user.isEmpty ? "" : connection.user + "@") + connection.host }

    private func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let askpass {
            env["SSH_ASKPASS"] = askpass.path
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["MACTC_SSH_PASSWORD"] = connection.password
            env["DISPLAY"] = env["DISPLAY"] ?? ":0"
        }
        return env
    }

    /// Quoting argumentu pro dávkový soubor sftp.
    static func q(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func makeProcess(_ commands: [String]) throws -> (Process, URL, Pipe, Pipe) {
        let batch = FileManager.default.temporaryDirectory.appendingPathComponent("macTC-sftp-\(UUID().uuidString).batch")
        try (commands.joined(separator: "\n") + "\n").write(to: batch, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        p.arguments = ["-b", batch.path] + baseArguments + [target]
        p.environment = environment()
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        return (p, batch, out, err)
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock(); private var data = Data()
        func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
        var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    }

    /// Provede příkazy v jedné relaci; při nenulovém kódu vyhodí chybu se zprávou ze stderr.
    /// `poll` se volá cca každých 100 ms a může přenos zrušit vrácením false.
    @discardableResult
    func run(_ commands: [String], poll: (() -> Bool)? = nil) throws -> String {
        let (p, batch, out, err) = try makeProcess(commands)
        defer { try? FileManager.default.removeItem(at: batch) }
        let so = Collector(), se = Collector()
        out.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; if !d.isEmpty { so.append(d) } }
        err.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; if !d.isEmpty { se.append(d) } }
        do { try p.run() } catch { throw RemoteError(code: -1, message: "Nelze spustit sftp: \(error.localizedDescription)") }
        var aborted = false
        while p.isRunning {
            Thread.sleep(forTimeInterval: 0.1)
            if let poll, !poll() { aborted = true; p.terminate(); break }
        }
        p.waitUntilExit()
        out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
        if let rest = try? out.fileHandleForReading.readToEnd() { so.append(rest) }
        if let rest = try? err.fileHandleForReading.readToEnd() { se.append(rest) }
        if aborted { throw RemoteError(code: RemoteAbort.code, message: "Přerušeno") }
        if p.terminationStatus != 0 {
            let msg = se.text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("BSM audit") }.last
                ?? so.text.split(separator: "\n").last.map(String.init) ?? "sftp skončil s chybou \(p.terminationStatus)"
            throw RemoteError(code: p.terminationStatus, message: msg)
        }
        return so.text
    }

    /// Ukončí sdílené spojení (ControlMaster).
    public func close() {
        guard connection.multiplex else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = ["-O", "exit", "-o", "ControlPath=\(controlDir.path)/%C"] + (connection.port.map { ["-p", String($0)] } ?? []) + [target]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
    }

    /// Domovský adresář (výsledek `pwd`).
    public func homeDirectory() throws -> String {
        let out = try run(["pwd"])
        for l in out.split(separator: "\n") where l.hasPrefix("Remote working directory:") {
            return String(l.dropFirst("Remote working directory:".count)).trimmingCharacters(in: .whitespaces)
        }
        return "/"
    }

    // MARK: VirtualFileSystem

    private func path(_ url: URL) -> String { RemoteFileSystem.normalize(url.path) }

    public func list(_ dir: URL, includeHidden: Bool) throws -> [FileEntry] {
        let d = path(dir)
        let out = try run(["cd " + Self.q(d), "ls -la"])
        let body = out.split(separator: "\n", omittingEmptySubsequences: true)
            .filter { !$0.hasPrefix("sftp>") && !$0.hasPrefix("Remote working directory") }.joined(separator: "\n")
        return FTPListParser.parse(body, mlsd: false, timeZone: .current).compactMap { p in
            let e = FileEntry(url: URL(fileURLWithPath: d == "/" ? "/" + p.name : d + "/" + p.name), name: p.name, isDirectory: p.isDirectory,
                              isSymlink: p.isSymlink, isHidden: p.name.hasPrefix("."), size: p.size, modified: p.modified, permissions: p.permissions)
            return includeHidden || !e.isHidden ? e : nil
        }
    }

    public func stat(_ url: URL) throws -> FileEntry {
        let p = path(url)
        if p == "/" { return FileEntry(url: URL(fileURLWithPath: "/"), name: "/", isDirectory: true) }
        let parent = (p as NSString).deletingLastPathComponent, name = (p as NSString).lastPathComponent
        guard let e = try list(URL(fileURLWithPath: parent), includeHidden: true).first(where: { $0.name == name }) else {
            throw RemoteError(code: 78, message: "Na serveru neexistuje: \(p)")
        }
        return e
    }

    public func exists(_ url: URL) -> Bool { (try? stat(url)) != nil }

    public func createDirectory(_ url: URL) throws {
        var acc = ""
        for c in path(url).split(separator: "/") {
            acc += "/" + c
            if !exists(URL(fileURLWithPath: acc)) { try run(["mkdir " + Self.q(acc)]) }
        }
    }

    public func createFile(_ url: URL) throws {
        guard !exists(url) else { throw RemoteError(code: 0, message: "Soubor už existuje") }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try uploadFile(local: tmp, remotePath: path(url), progress: nil)
    }

    public func copy(_ src: URL, to dst: URL) throws { throw RemoteError(code: 0, message: "Kopie na serveru není podporována; použijte stažení a nahrání") }
    public func move(_ src: URL, to dst: URL) throws { try run(["rename " + Self.q(path(src)) + " " + Self.q(path(dst))]) }
    public func trash(_ url: URL) throws { try remove(url) }

    public func remove(_ url: URL) throws {
        let e = try stat(url)
        if e.isDirectory && !e.isSymlink {
            for c in try list(url, includeHidden: true) { try remove(c.url) }
            try run(["rmdir " + Self.q(path(url))])
        } else {
            try run(["rm " + Self.q(path(url))])
        }
    }

    // MARK: Přenos dat

    public func downloadFile(remotePath: String, local: URL, resumeFrom: Int64, progress: ((Int64, Int64) -> Bool)?) throws {
        let cmd = (resumeFrom > 0 ? "reget -p " : "get -p ") + Self.q(RemoteFileSystem.normalize(remotePath)) + " " + Self.q(local.path)
        _ = progress?(resumeFrom, 0)
        try run([cmd], poll: {
            let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
            return progress?(size, 0) ?? true
        })
        let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
        _ = progress?(size, size)
    }

    public func uploadFile(local: URL, remotePath: String, progress: ((Int64, Int64) -> Bool)?) throws {
        let total = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard progress?(0, total) ?? true else { throw RemoteError(code: RemoteAbort.code, message: "Přerušeno") }
        try run(["put -p " + Self.q(local.path) + " " + Self.q(RemoteFileSystem.normalize(remotePath))], poll: { progress?(0, total) ?? true })
        _ = progress?(total, total)
    }

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
