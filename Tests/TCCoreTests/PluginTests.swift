import Testing
import Foundation
@testable import TCCore

/// Vytváří ukázkové pluginy (Python 3) v dočasné složce.
enum SamplePlugins {
    static func install(_ name: String, manifest: String, script: String, in dir: URL) throws {
        let d = dir.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try manifest.write(to: d.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try script.write(to: d.appendingPathComponent("plugin.py"), atomically: true, encoding: .utf8)
    }

    static let wordcount = ("""
    {"name": "wordcount", "version": "1.0", "executable": "plugin.py", "interpreter": "/usr/bin/python3",
     "capabilities": {"columns": [{"id": "words", "title": "Slov", "width": 70, "align": "right", "extensions": ["txt", "md"]},
                                  {"id": "chars", "title": "Znaků"}]}}
    """, #"""
    import sys, json
    if sys.argv[1] == "columns":
        paths = json.load(sys.stdin)
        out = {}
        for p in paths:
            try:
                t = open(p, encoding="utf-8").read()
                out[p] = str(len(t.split())) if sys.argv[2] == "words" else str(len(t))
            except Exception:
                pass
        print(json.dumps(out))
    """#)

    static let csvview = ("""
    {"name": "csvview", "executable": "plugin.py", "interpreter": "/usr/bin/python3", "capabilities": {"viewer": {"extensions": ["csv"]}}}
    """, #"""
    import sys, json, csv
    if sys.argv[1] == "view":
        rows = list(csv.reader(open(sys.argv[2], encoding="utf-8")))
        html = "<table>" + "".join("<tr>" + "".join("<td>%s</td>" % c for c in r) + "</tr>" for r in rows) + "</table>"
        print(json.dumps({"kind": "html", "content": html}))
    """#)

    static let demozip = ("""
    {"name": "demozip", "executable": "plugin.py", "interpreter": "/usr/bin/python3", "capabilities": {"archive": {"extensions": ["dz"]}}}
    """, #"""
    import sys, os
    if sys.argv[1] == "unpack":
        for line in open(sys.argv[2], encoding="utf-8").read().splitlines():
            name, _, content = line.partition("\t")
            path = os.path.join(sys.argv[3], name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w", encoding="utf-8").write(content)
    """#)

    static let memfs = ("""
    {"name": "memfs", "executable": "plugin.py", "interpreter": "/usr/bin/python3", "capabilities": {"filesystem": {"scheme": "mem"}}}
    """, #"""
    import sys, os, json, shutil
    root = sys.argv[2]
    cmd = sys.argv[3]
    def real(p): return os.path.join(root, p.lstrip("/"))
    if cmd == "list":
        d = real(sys.argv[4])
        if not os.path.isdir(d): sys.stderr.write("no such directory"); sys.exit(2)
        out = []
        for n in sorted(os.listdir(d)):
            s = os.stat(os.path.join(d, n))
            out.append({"name": n, "dir": os.path.isdir(os.path.join(d, n)), "size": s.st_size, "mtime": s.st_mtime, "mode": s.st_mode & 0o777})
        print(json.dumps(out))
    elif cmd == "get": shutil.copyfile(real(sys.argv[4]), sys.argv[5])
    elif cmd == "put": shutil.copyfile(sys.argv[4], real(sys.argv[5]))
    elif cmd == "rm":
        p = real(sys.argv[4])
        if os.path.isdir(p): os.rmdir(p)
        else: os.remove(p)
    elif cmd == "mkdir": os.makedirs(real(sys.argv[4]), exist_ok=True)
    elif cmd == "mv": os.rename(real(sys.argv[4]), real(sys.argv[5]))
    """#)

    static let hang = ("""
    {"name": "hang", "executable": "plugin.py", "interpreter": "/usr/bin/python3", "capabilities": {"viewer": {"extensions": ["slow"]}}}
    """, "import time\ntime.sleep(30)\n")

    static let crash = ("""
    {"name": "crash", "executable": "plugin.py", "interpreter": "/usr/bin/python3", "capabilities": {"viewer": {"extensions": ["boom"]}}}
    """, "import sys\nsys.stderr.write('něco se pokazilo')\nsys.exit(3)\n")
}

@Suite(.serialized) struct PluginHostTests {
    func host(_ plugins: [(String, (String, String))]) throws -> (PluginHost, URL) {
        let d = try makeTempDir()
        for (name, p) in plugins { try SamplePlugins.install(name, manifest: p.0, script: p.1, in: d) }
        let h = PluginHost(directory: d)
        ContentColumnRegistry.shared.removeAll()
        h.reload()
        return (h, d)
    }

    @Test func loadsValidPluginsAndReportsBrokenOnes() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        try SamplePlugins.install("good", manifest: SamplePlugins.csvview.0, script: SamplePlugins.csvview.1, in: d)
        try SamplePlugins.install("badjson", manifest: "{ not json", script: "", in: d)
        try SamplePlugins.install("noexe", manifest: #"{"name":"noexe","executable":"missing.py","capabilities":{}}"#, script: "", in: d)
        try SamplePlugins.install("evil", manifest: #"{"name":"evil","executable":"../../bin/sh","capabilities":{}}"#, script: "", in: d)
        let h = PluginHost(directory: d)
        let list = h.reload()
        #expect(list.count == 4 && h.valid.map(\.id) == ["csvview"])
        let errors = Dictionary(uniqueKeysWithValues: list.filter { $0.error != nil }.map { ($0.directory.lastPathComponent, $0.error!) })
        #expect(errors["badjson"] != nil && errors["noexe"]?.contains("Chybí") == true && errors["evil"]?.contains("Neplatná") == true)
    }

    @Test func contentColumnsFillCacheAndRespectExtensions() throws {
        let (h, d) = try host([("wordcount", SamplePlugins.wordcount)]); defer { try? FileManager.default.removeItem(at: d); ContentColumnRegistry.shared.removeAll() }
        let txt = try write(d, "a.txt", "one two three\nfour"), bin = try write(d, "b.bin", "x y z")
        _ = h
        let words = PanelColumn(rawValue: "plugin:wordcount:words"), chars = PanelColumn(rawValue: "plugin:wordcount:chars")
        #expect(PanelColumn.allCases.contains(words) && words.isPlugin && words.title == "Slov" && words.defaultWidth == 70)
        #expect(ContentColumnRegistry.shared.info(for: words)?.rightAligned == true)
        let fs = LocalFileSystem()
        let entries = [try fs.stat(txt), try fs.stat(bin)]
        #expect(ContentColumnRegistry.shared.cached(words, entries[0]) == nil)
        #expect(ContentColumnRegistry.shared.fill([words, chars], for: entries))
        #expect(ContentColumnRegistry.shared.cached(words, entries[0]) == "4")
        #expect(ContentColumnRegistry.shared.cached(words, entries[1]) == "")           // přípona .bin je mimo rozsah sloupce
        #expect(ContentColumnRegistry.shared.cached(chars, entries[1]) == "5")
        #expect(!ContentColumnRegistry.shared.fill([words, chars], for: entries))        // už je vše v mezipaměti
        #expect(ColumnSet.parse("size, plugin:wordcount:words, bogus") == [.name, .size, words])
        // změna souboru zneplatní mezipaměť (klíč obsahuje mtime a velikost)
        try "just two".write(to: txt, atomically: true, encoding: .utf8)
        let changed = try fs.stat(txt)
        #expect(ContentColumnRegistry.shared.cached(words, changed) == nil)
        ContentColumnRegistry.shared.fill([words], for: [changed])
        #expect(ContentColumnRegistry.shared.cached(words, changed) == "2")
    }

    @Test func viewerPluginRendersHTML() throws {
        let (h, d) = try host([("csvview", SamplePlugins.csvview)]); defer { try? FileManager.default.removeItem(at: d); ContentColumnRegistry.shared.removeAll() }
        let csv = try write(d, "t.csv", "a,b\n1,2\n")
        let plugin = try #require(h.viewerPlugin(for: "T.CSV"))
        #expect(h.viewerPlugin(for: "x.txt") == nil)
        let r = try h.render(csv, with: plugin)
        #expect(r.kind == "html" && r.content == "<table><tr><td>a</td><td>b</td></tr><tr><td>1</td><td>2</td></tr></table>")
    }

    @Test func archivePluginUnpacksIntoFolder() throws {
        let (h, d) = try host([("demozip", SamplePlugins.demozip)]); defer { try? FileManager.default.removeItem(at: d); ContentColumnRegistry.shared.removeAll() }
        let a = try write(d, "pack.DZ", "one.txt\thello\nsub/two.txt\tworld\n")
        let plugin = try #require(h.archivePlugin(for: "pack.DZ"))
        #expect(h.archivePlugin(for: "x.zip") == nil)
        let out = d.appendingPathComponent("out")
        try h.unpack(a, with: plugin, into: out)
        #expect(try String(contentsOf: out.appendingPathComponent("sub/two.txt"), encoding: .utf8) == "world")
    }

    @Test func failingAndHangingPluginsGiveClearErrors() throws {
        let (h, d) = try host([("hang", SamplePlugins.hang), ("crash", SamplePlugins.crash)]); defer { try? FileManager.default.removeItem(at: d) }
        let hang = try #require(h.valid.first { $0.id == "hang" }), crash = try #require(h.valid.first { $0.id == "crash" })
        do { _ = try h.run(crash, arguments: ["view", "x"]); Issue.record("měl selhat") }
        catch let e as PluginError { #expect(e.message == "něco se pokazilo") }
        let started = Date()
        do { _ = try h.run(hang, arguments: ["view", "x"], timeout: 1); Issue.record("měl vypršet") }
        catch let e as PluginError { #expect(e.message.contains("neodpověděl")) }
        #expect(Date().timeIntervalSince(started) < 10)
    }
}

extension PluginHostTests {
@Suite(.serialized) struct PluginFileSystemTests {
    @Test func browsesAndTransfersThroughPlugin() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d); ContentColumnRegistry.shared.removeAll() }
        try SamplePlugins.install("memfs", manifest: SamplePlugins.memfs.0, script: SamplePlugins.memfs.1, in: d)
        let h = PluginHost(directory: d.appendingPathComponent("memfs").deletingLastPathComponent()); h.reload()
        let store = d.appendingPathComponent("store"); try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try write(store, "a.txt", "AAA"); try write(store, "dir/b.txt", "BB")
        let plugin = try #require(h.filesystemPlugin(scheme: "MEM"))
        let fs = PluginFileSystem(plugin: plugin, connection: store.path, host: h)
        #expect(fs.displayName == "mem://\(store.path)")
        let root = try fs.list(URL(fileURLWithPath: "/"), includeHidden: true)
        #expect(root.map(\.name) == ["a.txt", "dir"] && root[1].isDirectory && root[0].size == 3)
        #expect(try fs.stat(URL(fileURLWithPath: "/dir/b.txt")).size == 2 && !fs.exists(URL(fileURLWithPath: "/nope")))
        #expect(throws: Error.self) { try fs.list(URL(fileURLWithPath: "/nope"), includeHidden: true) }

        let out = d.appendingPathComponent("out"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let r = RemoteTransfer.download(fs, ["/a.txt", "/dir"], to: out)
        #expect(r.failures.isEmpty && r.succeeded == 2, "\(r.failures.map(\.message))")
        #expect(try String(contentsOf: out.appendingPathComponent("dir/b.txt"), encoding: .utf8) == "BB")

        let up = try write(d, "up/new.txt", "NEW")
        #expect(RemoteTransfer.upload(fs, [up], into: "/dir").failures.isEmpty)
        #expect(try String(contentsOf: store.appendingPathComponent("dir/new.txt"), encoding: .utf8) == "NEW")
        try fs.createDirectory(URL(fileURLWithPath: "/x/y"))
        try fs.move(URL(fileURLWithPath: "/a.txt"), to: URL(fileURLWithPath: "/x/y/moved.txt"))
        #expect(FileManager.default.fileExists(atPath: store.appendingPathComponent("x/y/moved.txt").path))
        try fs.remove(URL(fileURLWithPath: "/x"))
        #expect(!FileManager.default.fileExists(atPath: store.appendingPathComponent("x").path))
    }

    @MainActor @Test func panelAttachesPluginFileSystem() async throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d); ContentColumnRegistry.shared.removeAll() }
        try SamplePlugins.install("memfs", manifest: SamplePlugins.memfs.0, script: SamplePlugins.memfs.1, in: d)
        let h = PluginHost(directory: d); h.reload()
        let store = d.appendingPathComponent("store"); try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
        try write(store, "a.txt", "A"); try write(store, "dir/b.txt", "B")
        let fs = PluginFileSystem(plugin: try #require(h.filesystemPlugin(scheme: "mem")), connection: store.path, host: h)
        let tab = PanelTab(path: d)
        tab.attachRemote(fs, path: "/", items: try fs.list(URL(fileURLWithPath: "/"), includeHidden: false))
        #expect(tab.entries.map(\.name) == ["..", "dir", "a.txt"])
        tab.moveCursor(to: 1); _ = tab.activateCursor()
        for _ in 0..<100 { if tab.path.path == "/dir" && !tab.isLoading { break }; try await Task.sleep(nanoseconds: 100_000_000) }
        #expect(tab.entries.map(\.name) == ["..", "b.txt"])
    }
}
}
