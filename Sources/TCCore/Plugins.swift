import Foundation

// MARK: Obsahové sloupce (obdoba WDX)

public struct ContentColumn: Sendable, Hashable {
    public let providerID: String
    public let id: String
    public let title: String
    public let width: Double
    public let rightAligned: Bool
    public var panelColumn: PanelColumn { PanelColumn(rawValue: "plugin:\(providerID):\(id)") }
    public init(providerID: String, id: String, title: String, width: Double = 100, rightAligned: Bool = false) {
        self.providerID = providerID; self.id = id; self.title = title; self.width = width; self.rightAligned = rightAligned
    }
}

/// Poskytovatel hodnot sloupců pro soubory (vestavěný nebo z pluginu).
public protocol ContentColumnProvider: Sendable {
    var providerID: String { get }
    var columns: [ContentColumn] { get }
    /// Hodnoty pro dávku souborů; chybějící klíč = žádná hodnota. Volá se mimo hlavní vlákno.
    func values(column: String, for urls: [URL]) -> [URL: String]
}

public final class ContentColumnRegistry: @unchecked Sendable {
    public static let shared = ContentColumnRegistry()
    private let lock = NSLock()
    private var providers: [any ContentColumnProvider] = []
    private var cache: [String: String] = [:]          // "sloupec|cesta|mtime" -> hodnota ("" = žádná)

    public func register(_ p: any ContentColumnProvider) {
        lock.lock(); providers.removeAll { $0.providerID == p.providerID }; providers.append(p); lock.unlock()
    }

    public func unregister(providerID: String) {
        lock.lock(); providers.removeAll { $0.providerID == providerID }; cache.removeAll(); lock.unlock()
    }

    public func removeAll() { lock.lock(); providers.removeAll(); cache.removeAll(); lock.unlock() }

    public var allColumns: [ContentColumn] { lock.lock(); defer { lock.unlock() }; return providers.flatMap(\.columns) }

    public func info(for column: PanelColumn) -> ContentColumn? { allColumns.first { $0.panelColumn == column } }

    private func key(_ column: PanelColumn, _ e: FileEntry) -> String { "\(column.rawValue)|\(e.url.path)|\(e.modified?.timeIntervalSince1970 ?? 0)|\(e.size)" }

    /// Hodnota z mezipaměti (nil = zatím nezjištěno; prázdný řetězec = žádná hodnota).
    public func cached(_ column: PanelColumn, _ e: FileEntry) -> String? {
        lock.lock(); defer { lock.unlock() }; return cache[key(column, e)]
    }

    /// Doplní chybějící hodnoty v dávce; vrací, zda přibylo něco nového. Volat z pozadí.
    @discardableResult
    public func fill(_ columns: [PanelColumn], for entries: [FileEntry]) -> Bool {
        var added = false
        for column in columns where column.isPlugin {
            let parts = column.rawValue.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { continue }
            lock.lock(); let provider = providers.first { $0.providerID == parts[1] }; lock.unlock()
            guard let provider else { continue }
            let missing = entries.filter { !$0.isDirectory && !$0.isParentLink && cached(column, $0) == nil }
            guard !missing.isEmpty else { continue }
            let result = provider.values(column: parts[2], for: missing.map(\.url))
            lock.lock()
            for e in missing { cache[key(column, e)] = result[e.url] ?? "" }
            lock.unlock()
            added = true
        }
        return added
    }
}

// MARK: Manifest a hostitel pluginů

public struct PluginManifest: Codable, Sendable, Equatable {
    public struct ColumnSpec: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var width: Double?
        public var align: String?
        public var extensions: [String]?
    }
    public struct ViewerSpec: Codable, Sendable, Equatable { public var extensions: [String] }
    public struct ArchiveSpec: Codable, Sendable, Equatable { public var extensions: [String] }
    public struct FileSystemSpec: Codable, Sendable, Equatable { public var scheme: String; public var title: String? }
    public struct Capabilities: Codable, Sendable, Equatable {
        public var columns: [ColumnSpec]?
        public var viewer: ViewerSpec?
        public var archive: ArchiveSpec?
        public var filesystem: FileSystemSpec?
    }

    public var name: String
    public var version: String?
    public var description: String?
    /// Spustitelný soubor (relativně ke složce pluginu).
    public var executable: String
    /// Volitelný interpret, např. /usr/bin/python3.
    public var interpreter: String?
    public var capabilities: Capabilities
}

public struct LoadedPlugin: Sendable, Identifiable {
    public var id: String { manifest?.name ?? directory.lastPathComponent }
    public let directory: URL
    public let manifest: PluginManifest?
    public let error: String?
}

public struct PluginError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

public final class PluginHost: @unchecked Sendable {
    public static let shared = PluginHost()
    public private(set) var plugins: [LoadedPlugin] = []
    public private(set) var directory: URL
    private let lock = NSLock()

    public static func defaultDirectory() -> URL {
        AppPaths.plugins
    }

    public init(directory: URL = PluginHost.defaultDirectory()) { self.directory = directory }

    /// Načte manifesty ze všech podsložek; chybné pluginy se uvedou s chybou, ostatní to neovlivní.
    @discardableResult
    public func reload(directory newDirectory: URL? = nil) -> [LoadedPlugin] {
        if let newDirectory { directory = newDirectory }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var list: [LoadedPlugin] = []
        let dirs = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for d in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: d.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let mf = d.appendingPathComponent("plugin.json")
            guard let data = try? Data(contentsOf: mf) else { continue }
            do {
                let m = try JSONDecoder().decode(PluginManifest.self, from: data)
                let exe = d.appendingPathComponent(m.executable)
                guard !m.executable.contains("..") else { throw PluginError(message: "Neplatná cesta ke spustitelnému souboru") }
                guard FileManager.default.fileExists(atPath: exe.path) else { throw PluginError(message: "Chybí spustitelný soubor \(m.executable)") }
                list.append(LoadedPlugin(directory: d, manifest: m, error: nil))
            } catch {
                list.append(LoadedPlugin(directory: d, manifest: nil, error: "plugin.json: \(error.localizedDescription)"))
            }
        }
        lock.lock(); plugins = list; lock.unlock()
        registerColumns()
        return list
    }

    public var valid: [LoadedPlugin] { lock.lock(); defer { lock.unlock() }; return plugins.filter { $0.manifest != nil } }

    private func registerColumns() {
        for p in plugins {
            guard let m = p.manifest else { continue }
            ContentColumnRegistry.shared.unregister(providerID: m.name)
        }
        for p in valid {
            if let m = p.manifest, let cols = m.capabilities.columns, !cols.isEmpty {
                ContentColumnRegistry.shared.register(PluginColumnProvider(plugin: p, host: self))
            }
        }
    }

    // MARK: Spuštění

    /// Spustí plugin s argumenty; `stdin` se předá na vstup. Při překročení limitu se proces ukončí.
    public func run(_ plugin: LoadedPlugin, arguments: [String], stdin: Data? = nil, timeout: TimeInterval = 30) throws -> (stdout: Data, status: Int32) {
        guard let m = plugin.manifest else { throw PluginError(message: plugin.error ?? "Neplatný plugin") }
        let p = Process()
        let exe = plugin.directory.appendingPathComponent(m.executable)
        if let interp = m.interpreter, !interp.isEmpty {
            p.executableURL = URL(fileURLWithPath: interp)
            p.arguments = [exe.path] + arguments
        } else {
            p.executableURL = exe
            p.arguments = arguments
        }
        p.currentDirectoryURL = plugin.directory
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = inp
        var env = ProcessInfo.processInfo.environment
        env["TCOMMANDER_PLUGIN_DIR"] = plugin.directory.path
        env["MACTC_PLUGIN_DIR"] = plugin.directory.path                 // starší název (kvůli již napsaným pluginům)
        p.environment = env
        do { try p.run() } catch { throw PluginError(message: "Plugin \(m.name) nelze spustit: \(error.localizedDescription)") }
        let collected = DataBox()
        out.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; if !d.isEmpty { collected.append(d) } }
        let errBox = DataBox()
        err.fileHandleForReading.readabilityHandler = { h in let d = h.availableData; if !d.isEmpty { errBox.append(d) } }
        if let stdin { inp.fileHandleForWriting.write(stdin) }
        try? inp.fileHandleForWriting.close()
        nonisolated(unsafe) var timedOut = false
        let item = DispatchWorkItem { timedOut = true; p.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        p.waitUntilExit()
        item.cancel()
        out.fileHandleForReading.readabilityHandler = nil; err.fileHandleForReading.readabilityHandler = nil
        if let rest = try? out.fileHandleForReading.readToEnd() { collected.append(rest) }
        if let rest = try? err.fileHandleForReading.readToEnd() { errBox.append(rest) }
        if timedOut { throw PluginError(message: "Plugin \(m.name) neodpověděl do \(Int(timeout)) s") }
        if p.terminationStatus != 0 && collected.data.isEmpty {
            let msg = String(decoding: errBox.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw PluginError(message: msg.isEmpty ? "Plugin \(m.name) skončil s kódem \(p.terminationStatus)" : msg)
        }
        return (collected.data, p.terminationStatus)
    }

    private final class DataBox: @unchecked Sendable {
        private let lock = NSLock(); private var d = Data()
        func append(_ x: Data) { lock.lock(); d.append(x); lock.unlock() }
        var data: Data { lock.lock(); defer { lock.unlock() }; return d }
    }

    // MARK: Prohlížeče (obdoba WLX)

    public struct ViewResult: Codable, Sendable, Equatable {
        /// "text", "html" nebo "image" (u obrázku je `content` cesta k souboru).
        public var kind: String
        public var content: String
    }

    public func viewerPlugin(for fileName: String) -> LoadedPlugin? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return valid.first { $0.manifest?.capabilities.viewer?.extensions.map { $0.lowercased() }.contains(ext) == true }
    }

    public func render(_ url: URL, with plugin: LoadedPlugin) throws -> ViewResult {
        let r = try run(plugin, arguments: ["view", url.path])
        do { return try JSONDecoder().decode(ViewResult.self, from: r.stdout) }
        catch { throw PluginError(message: "Neplatná odpověď prohlížeče: \(error.localizedDescription)") }
    }

    // MARK: Archivy (obdoba WCX): plugin rozbalí archiv do složky

    public func archivePlugin(for fileName: String) -> LoadedPlugin? {
        let l = fileName.lowercased()
        return valid.first { p in p.manifest?.capabilities.archive?.extensions.contains { l.hasSuffix("." + $0.lowercased()) } == true }
    }

    public func unpack(_ archive: URL, with plugin: LoadedPlugin, into dest: URL) throws {
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let r = try run(plugin, arguments: ["unpack", archive.path, dest.path], timeout: 600)
        if r.status != 0 { throw PluginError(message: "Rozbalení pluginem selhalo (kód \(r.status))") }
    }

    // MARK: Souborové systémy (obdoba WFX)

    public func filesystemPlugin(scheme: String) -> LoadedPlugin? {
        valid.first { $0.manifest?.capabilities.filesystem?.scheme.lowercased() == scheme.lowercased() }
    }
}

/// Plugin jako poskytovatel sloupců: pro dávku souborů jednou spustí `columns <id>` a na vstup pošle JSON se seznamem cest.
public final class PluginColumnProvider: ContentColumnProvider, @unchecked Sendable {
    public let providerID: String
    public let columns: [ContentColumn]
    private let plugin: LoadedPlugin
    private let extensions: [String: [String]]     // sloupec -> přípony (prázdné = všechny)
    private unowned let host: PluginHost

    init(plugin: LoadedPlugin, host: PluginHost) {
        self.plugin = plugin; self.host = host
        let m = plugin.manifest!
        providerID = m.name
        let specs = m.capabilities.columns ?? []
        columns = specs.map { ContentColumn(providerID: m.name, id: $0.id, title: $0.title, width: $0.width ?? 100, rightAligned: $0.align == "right") }
        extensions = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, ($0.extensions ?? []).map { $0.lowercased() }) })
    }

    public func values(column: String, for urls: [URL]) -> [URL: String] {
        let exts = extensions[column] ?? []
        let wanted = exts.isEmpty ? urls : urls.filter { exts.contains($0.pathExtension.lowercased()) }
        guard !wanted.isEmpty, let input = try? JSONEncoder().encode(wanted.map(\.path)) else { return [:] }
        guard let r = try? host.run(plugin, arguments: ["columns", column], stdin: input),
              let obj = try? JSONDecoder().decode([String: String].self, from: r.stdout) else { return [:] }
        var out: [URL: String] = [:]
        for u in wanted { if let v = obj[u.path] { out[u] = v } }
        return out
    }
}

/// Souborový systém poskytovaný pluginem; příkazy: `fs <připojení> list|get|put|rm|mkdir|mv …`.
public final class PluginFileSystem: RemoteFileSystemProtocol, @unchecked Sendable {
    public let plugin: LoadedPlugin
    public let connection: String
    private let host: PluginHost
    public var displayName: String { "\(plugin.manifest?.capabilities.filesystem?.scheme ?? "plugin")://\(connection)" }

    public init(plugin: LoadedPlugin, connection: String, host: PluginHost = .shared) {
        self.plugin = plugin; self.connection = connection; self.host = host
    }

    struct Item: Codable { var name: String; var dir: Bool?; var size: Int64?; var mtime: Double?; var mode: Int? }

    private func call(_ args: [String], timeout: TimeInterval = 60) throws -> Data {
        let r = try host.run(plugin, arguments: ["fs", connection] + args, timeout: timeout)
        if r.status != 0 { throw PluginError(message: "Plugin: operace \(args.first ?? "") selhala (kód \(r.status))") }
        return r.stdout
    }

    private func norm(_ url: URL) -> String { RemoteFileSystem.normalize(url.path) }

    public func list(_ dir: URL, includeHidden: Bool) throws -> [FileEntry] {
        let d = norm(dir)
        let items = try JSONDecoder().decode([Item].self, from: try call(["list", d]))
        return items.compactMap { i in
            let e = FileEntry(url: URL(fileURLWithPath: d == "/" ? "/" + i.name : d + "/" + i.name), name: i.name, isDirectory: i.dir ?? false,
                              isHidden: i.name.hasPrefix("."), size: i.size ?? 0, modified: i.mtime.map { Date(timeIntervalSince1970: $0) },
                              permissions: UInt16(i.mode ?? 0o644))
            return includeHidden || !e.isHidden ? e : nil
        }
    }

    public func stat(_ url: URL) throws -> FileEntry {
        let p = norm(url)
        if p == "/" { return FileEntry(url: URL(fileURLWithPath: "/"), name: "/", isDirectory: true) }
        guard let e = try list(URL(fileURLWithPath: (p as NSString).deletingLastPathComponent), includeHidden: true).first(where: { $0.name == (p as NSString).lastPathComponent }) else {
            throw PluginError(message: "Neexistuje: \(p)")
        }
        return e
    }

    public func exists(_ url: URL) -> Bool { (try? stat(url)) != nil }
    public func createDirectory(_ url: URL) throws { _ = try call(["mkdir", norm(url)]) }
    public func createFile(_ url: URL) throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: tmp.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try uploadFile(local: tmp, remotePath: norm(url), progress: nil)
    }
    public func copy(_ src: URL, to dst: URL) throws { throw PluginError(message: "Kopie v rámci serveru není podporována") }
    public func move(_ src: URL, to dst: URL) throws { _ = try call(["mv", norm(src), norm(dst)]) }
    public func trash(_ url: URL) throws { try remove(url) }
    /// Plugin maže soubor nebo prázdný adresář; strom se proto prochází zde.
    public func remove(_ url: URL) throws {
        let e = try stat(url)
        if e.isDirectory { for c in try list(url, includeHidden: true) { try remove(c.url) } }
        _ = try call(["rm", norm(url)])
    }

    public func downloadFile(remotePath: String, local: URL, resumeFrom: Int64, progress: ((Int64, Int64) -> Bool)?) throws {
        _ = progress?(0, 0)
        _ = try call(["get", RemoteFileSystem.normalize(remotePath), local.path], timeout: 3600)
        let size = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
        _ = progress?(size, size)
    }

    public func uploadFile(local: URL, remotePath: String, progress: ((Int64, Int64) -> Bool)?) throws {
        let total = (try? FileManager.default.attributesOfItem(atPath: local.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard progress?(0, total) ?? true else { throw RemoteError(code: RemoteAbort.code, message: "Přerušeno") }
        _ = try call(["put", local.path, RemoteFileSystem.normalize(remotePath)], timeout: 3600)
        _ = progress?(total, total)
    }

    public func scan(_ path: String) -> (files: Int, bytes: Int64) {
        guard let e = try? stat(URL(fileURLWithPath: path)) else { return (0, 0) }
        if !e.isDirectory { return (1, e.size) }
        var files = 0, bytes: Int64 = 0
        for c in (try? list(URL(fileURLWithPath: path), includeHidden: true)) ?? [] { let s = scan(c.url.path); files += s.files; bytes += s.bytes }
        return (files, bytes)
    }
}
