import Testing
import Foundation
@testable import TCCore

/// Spouští skutečné ukázkové pluginy z `docs/plugin-examples` (kopie v dočasné složce).
enum ExamplePlugins {
    static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/plugin-examples")
    }

    static func host(_ names: [String]) throws -> (PluginHost, URL) {
        let d = try makeTempDir()
        for n in names { try FileManager.default.copyItem(at: sourceRoot.appendingPathComponent(n), to: d.appendingPathComponent(n)) }
        let h = PluginHost(directory: d)
        ContentColumnRegistry.shared.removeAll()
        h.reload()
        return (h, d)
    }

    static func python(_ args: [String], input: Data? = nil) throws -> (out: String, status: Int32) {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); p.arguments = args
        let o = Pipe(), i = Pipe(); p.standardOutput = o; p.standardError = FileHandle.nullDevice; p.standardInput = i
        try p.run()
        if let input { i.fileHandleForWriting.write(input) }
        try? i.fileHandleForWriting.close()
        let data = o.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus)
    }
}

/// Vnořeno do `PluginHostTests` (serializované), protože testy sdílejí globální registr sloupců.
extension PluginHostTests {
@Suite(.serialized) struct ExampleTests {
    static let all = ["wordcount", "csvview", "demozip", "memfs", "adifview", "filehash", "structview", "macpackages", "httpindex", "photoinfo"]

    @Test func everyExampleHasAValidManifestAndExecutable() throws {
        let (h, d) = try ExamplePlugins.host(Self.all); defer { try? FileManager.default.removeItem(at: d); ContentColumnRegistry.shared.removeAll() }
        let loaded = h.reload()
        #expect(loaded.count == Self.all.count)
        for p in loaded { #expect(p.error == nil, "\(p.directory.lastPathComponent): \(p.error ?? "")"); #expect(p.manifest?.description?.isEmpty == false || ["wordcount", "csvview", "demozip", "memfs"].contains(p.id), "\(p.id) bez popisu") }
        #expect(h.viewerPlugin(for: "log.ADI")?.id == "adifview" && h.viewerPlugin(for: "a.plist")?.id == "structview" && h.viewerPlugin(for: "x.json")?.id == "structview")
        #expect(h.archivePlugin(for: "Tool.DMG")?.id == "macpackages" && h.filesystemPlugin(scheme: "http")?.id == "httpindex")
    }

    @Test func adifViewShowsQsosSortedWithSummary() throws {
        let (h, d) = try ExamplePlugins.host(["adifview"]); defer { try? FileManager.default.removeItem(at: d) }
        let text = "ADIF export\n<ADIF_VER:5>3.1.0\n<PROGRAMID:9>TCommander\n<EOH>\n"
            + "<CALL:5>OK1XO <QSO_DATE:8>20261007 <TIME_ON:4>1530 <BAND:3>20m <MODE:3>SSB <RST_SENT:2>59 <RST_RCVD:2>57 <QTH:7>Příbram <EOR>\n"
            + "<CALL:4>DL1A <QSO_DATE:8>20261006 <TIME_ON:6>080000 <BAND:3>40m <MODE:2>CW <COMMENT:20>Dobrý signál díky! <EOR>\n"
            + "<CALL:5>OK2&A <QSO_DATE:8>20261008 <EOR>"
        let f = try write(d, "log.adi", text)
        let r = try h.render(f, with: try #require(h.viewerPlugin(for: "log.adi")))
        #expect(r.kind == "html")
        let c = r.content
        #expect(c.contains("3 spojení") && c.contains("3 různých značek") && c.contains("2026-10-06 – 2026-10-08"))
        #expect(c.range(of: "DL1A")!.lowerBound < c.range(of: "OK1XO")!.lowerBound, "záznamy se řadí podle data")
        #expect(c.contains("Příbram") && c.contains("Dobrý signál díky!") && c.contains("59/57") && c.contains("08:00") && c.contains("15:30"))
        #expect(c.contains("OK2&amp;A") && !c.contains("OK2&A<"), "hodnoty se escapují")
        #expect(c.contains("TCommander"))
    }

    @Test func fileHashColumnsMatchKnownDigests() throws {
        let (h, d) = try ExamplePlugins.host(["filehash"]); defer { try? FileManager.default.removeItem(at: d); ContentColumnRegistry.shared.removeAll() }
        defer { withExtendedLifetime(h) {} }                                           // poskytovatel sloupců drží hostitele jen neowned
        let f = try write(d, "h.txt", "hello\n")
        let sub = d.appendingPathComponent("adresar"); try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let fs = LocalFileSystem()
        let entries = [try fs.stat(f), try fs.stat(sub)]
        let md5 = PanelColumn(rawValue: "plugin:filehash:md5"), sha1 = PanelColumn(rawValue: "plugin:filehash:sha1"), sha256 = PanelColumn(rawValue: "plugin:filehash:sha256")
        #expect(ContentColumnRegistry.shared.fill([md5, sha1, sha256], for: entries))
        #expect(ContentColumnRegistry.shared.cached(md5, entries[0]) == "b1946ac92492d2347c6235b4d2611184")
        #expect(ContentColumnRegistry.shared.cached(sha1, entries[0]) == "f572d396fae9206628714fb2ce00f72e94f2258f")
        #expect(ContentColumnRegistry.shared.cached(sha256, entries[0]) == "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03")
        #expect(ContentColumnRegistry.shared.cached(md5, entries[1]) == nil, "adresáře se do pluginu vůbec neposílají")
    }

    @Test func structViewPrettyPrintsJsonAndBinaryPlistAndRejectsGarbage() throws {
        let (h, d) = try ExamplePlugins.host(["structview"]); defer { try? FileManager.default.removeItem(at: d) }
        let plugin = try #require(h.viewerPlugin(for: "x.json"))
        let json = try write(d, "m.json", #"{"b":[1,2,{"c":null}],"a":"čeština"}"#)
        let r = try h.render(json, with: plugin)
        #expect(r.kind == "text" && r.content.contains("// JSON") && r.content.contains("\"a\": \"čeština\"") && r.content.contains("      \"c\": null"))
        #expect(r.content.range(of: "\"b\"")!.lowerBound < r.content.range(of: "\"a\"")!.lowerBound, "pořadí klíčů se zachová")
        let xml = try write(d, "t.plist", #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>Name</key><string>Test</string><key>Blob</key><data>AAECAwQ=</data><key>On</key><true/></dict></plist>"#)
        let bin = d.appendingPathComponent("b.plist")
        let conv = Process(); conv.executableURL = URL(fileURLWithPath: "/usr/bin/plutil"); conv.arguments = ["-convert", "binary1", "-o", bin.path, xml.path]
        try conv.run(); conv.waitUntilExit()
        let rb = try h.render(bin, with: plugin)
        #expect(rb.content.contains("plist (binární)") && rb.content.contains("\"Name\": \"Test\"") && rb.content.contains("<data 5 B:") && rb.content.contains("\"On\": true"))
        let bad = try write(d, "bad.json", "nesmysl{")
        #expect(throws: Error.self) { try h.render(bad, with: plugin) }
    }

    static let packagingToolsAvailable = FileManager.default.isExecutableFile(atPath: "/usr/bin/pkgbuild") && FileManager.default.isExecutableFile(atPath: "/usr/bin/hdiutil")

    @Test(.enabled(if: PluginHostTests.ExampleTests.packagingToolsAvailable, "pkgbuild/hdiutil nejsou k dispozici"))
    func macPackagesUnpacksPkgAndDmg() throws {
        let (h, d) = try ExamplePlugins.host(["macpackages"]); defer { try? FileManager.default.removeItem(at: d) }
        let plugin = try #require(h.archivePlugin(for: "demo.pkg"))
        let root = d.appendingPathComponent("root/Applications/Demo.app/Contents"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "hi".write(to: root.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        let pkg = d.appendingPathComponent("demo.pkg")
        let build = Process(); build.executableURL = URL(fileURLWithPath: "/usr/bin/pkgbuild")
        build.arguments = ["--root", d.appendingPathComponent("root").path, "--identifier", "cz.test.demo", "--version", "1.0", pkg.path]
        build.standardOutput = FileHandle.nullDevice; build.standardError = FileHandle.nullDevice
        try build.run(); build.waitUntilExit()
        let outPkg = d.appendingPathComponent("out-pkg"); try FileManager.default.createDirectory(at: outPkg, withIntermediateDirectories: true)
        try h.unpack(pkg, with: plugin, into: outPkg)
        #expect(try String(contentsOf: outPkg.appendingPathComponent("Payload/Applications/Demo.app/Contents/readme.txt"), encoding: .utf8) == "hi")
        #expect(FileManager.default.fileExists(atPath: outPkg.appendingPathComponent("PackageInfo").path))

        let src = d.appendingPathComponent("dmgsrc/Docs"); try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try "obsah".write(to: src.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let dmg = d.appendingPathComponent("demo.dmg")
        let mk = Process(); mk.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        mk.arguments = ["create", "-quiet", "-volname", "Demo", "-srcfolder", d.appendingPathComponent("dmgsrc").path, "-ov", dmg.path]
        try mk.run(); mk.waitUntilExit()
        let outDmg = d.appendingPathComponent("out-dmg"); try FileManager.default.createDirectory(at: outDmg, withIntermediateDirectories: true)
        try h.unpack(dmg, with: plugin, into: outDmg)
        #expect(try String(contentsOf: outDmg.appendingPathComponent("Docs/file.txt"), encoding: .utf8) == "obsah")
        // obraz zůstane po rozbalení odpojený
        let mounts = Process(); mounts.executableURL = URL(fileURLWithPath: "/sbin/mount"); let pipe = Pipe(); mounts.standardOutput = pipe
        try mounts.run(); mounts.waitUntilExit()
        #expect(!String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).contains("tc-dmg-"))
        let broken = try write(d, "broken.dmg", "to není obraz disku")
        #expect(throws: Error.self) { try h.unpack(broken, with: plugin, into: d.appendingPathComponent("out-broken")) }
    }

    @Test func httpIndexBrowsesAndDownloadsFromARealWebServer() throws {
        let (h, d) = try ExamplePlugins.host(["httpindex"]); defer { try? FileManager.default.removeItem(at: d) }
        let web = d.appendingPathComponent("web"); try FileManager.default.createDirectory(at: web.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "ahoj web".write(to: web.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "se mezerou".write(to: web.appendingPathComponent("s mezerou.txt"), atomically: true, encoding: .utf8)
        try "vnořený".write(to: web.appendingPathComponent("sub/in.txt"), atomically: true, encoding: .utf8)
        let server = Process(); server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-c", "import http.server,socketserver,sys,os\nos.chdir(sys.argv[1])\nclass Q(http.server.SimpleHTTPRequestHandler):\n    def log_message(self,*a): pass\ns=socketserver.TCPServer(('127.0.0.1',0),Q)\nprint(s.server_address[1],flush=True)\ns.serve_forever()", web.path]
        let out = Pipe(); server.standardOutput = out
        try server.run(); defer { server.terminate(); server.waitUntilExit() }
        var buf = Data(); let deadline = Date().addingTimeInterval(10)
        while !buf.contains(10), Date() < deadline { let c = out.fileHandleForReading.availableData; if c.isEmpty { Thread.sleep(forTimeInterval: 0.05) } else { buf.append(c) } }
        let port = try #require(Int(String(decoding: buf, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))

        let plugin = try #require(h.filesystemPlugin(scheme: "http"))
        let fs = PluginFileSystem(plugin: plugin, connection: "127.0.0.1:\(port)", host: h)
        let root = try fs.list(URL(fileURLWithPath: "/"), includeHidden: true)
        #expect(Set(root.map(\.name)) == ["a.txt", "s mezerou.txt", "sub"])
        #expect(root.first { $0.name == "sub" }?.isDirectory == true && root.first { $0.name == "a.txt" }?.size == 8)
        let sub = try fs.list(URL(fileURLWithPath: "/sub"), includeHidden: true)
        #expect(sub.map(\.name) == ["in.txt"])
        let dl = d.appendingPathComponent("dl"); try FileManager.default.createDirectory(at: dl, withIntermediateDirectories: true)
        let r = RemoteTransfer.download(fs, ["/s mezerou.txt", "/sub"], to: dl)
        #expect(r.failures.isEmpty, "\(r.failures.map(\.message))")
        #expect(try String(contentsOf: dl.appendingPathComponent("s mezerou.txt"), encoding: .utf8) == "se mezerou")
        #expect(try String(contentsOf: dl.appendingPathComponent("sub/in.txt"), encoding: .utf8) == "vnořený")
        #expect(throws: Error.self) { try fs.remove(URL(fileURLWithPath: "/a.txt")) }                // server je jen pro čtení
        #expect(throws: Error.self) { try PluginFileSystem(plugin: plugin, connection: "127.0.0.1:1", host: h).list(URL(fileURLWithPath: "/"), includeHidden: true) }
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/sips"), "sips není k dispozici"))
    func photoInfoReadsResolutionWithSips() throws {
        let (h, d) = try ExamplePlugins.host(["photoinfo"]); defer { try? FileManager.default.removeItem(at: d); ContentColumnRegistry.shared.removeAll() }
        defer { withExtendedLifetime(h) {} }
        // 1×1 PNG
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let f = d.appendingPathComponent("p.png"); try png.write(to: f)
        let set = Process(); set.executableURL = URL(fileURLWithPath: "/usr/bin/sips"); set.arguments = ["-s", "dpiWidth", "144", "-s", "dpiHeight", "144", f.path]
        set.standardOutput = FileHandle.nullDevice; try set.run(); set.waitUntilExit()
        let fs = LocalFileSystem(); let e = try fs.stat(f)
        let dpi = PanelColumn(rawValue: "plugin:photoinfo:dpi"), camera = PanelColumn(rawValue: "plugin:photoinfo:camera")
        #expect(ContentColumnRegistry.shared.fill([dpi, camera], for: [e]))
        #expect(ContentColumnRegistry.shared.cached(dpi, e) == "144")
        #expect(ContentColumnRegistry.shared.cached(camera, e) == "", "bez EXIF není fotoaparát")
        let txt = try write(d, "n.txt", "x"); let te = try fs.stat(txt)
        ContentColumnRegistry.shared.fill([dpi], for: [te]); #expect(ContentColumnRegistry.shared.cached(dpi, te) == "")   // přípona mimo rozsah
    }
}
}

extension PluginHostTests {
@Suite struct PluginExamplesInstallTests {
    @Test func installsMissingExamplesAndKeepsExistingOnes() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let dest = d.appendingPathComponent("PlugIns")
        let first = PluginExamples.install(from: ExamplePlugins.sourceRoot, to: dest)
        let all = PluginExamples.available(in: ExamplePlugins.sourceRoot)
        #expect(all.count == PluginHostTests.ExampleTests.all.count && Set(all) == Set(PluginHostTests.ExampleTests.all))
        #expect(Set(first.installed) == Set(all) && first.alreadyPresent.isEmpty && first.failed.isEmpty)
        for n in all { #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent(n).appendingPathComponent("plugin.json").path), "\(n)") }
        #expect(FileManager.default.isExecutableFile(atPath: dest.appendingPathComponent("adifview/plugin.py").path))
        // uživatelská úprava přežije další instalaci
        try "{ \"name\": \"upraveno\" }".write(to: dest.appendingPathComponent("filehash/plugin.json"), atomically: true, encoding: .utf8)
        let second = PluginExamples.install(from: ExamplePlugins.sourceRoot, to: dest)
        #expect(second.installed.isEmpty && Set(second.alreadyPresent) == Set(all))
        #expect(try String(contentsOf: dest.appendingPathComponent("filehash/plugin.json"), encoding: .utf8).contains("upraveno"))
        // nainstalované pluginy se načtou bez chyb
        let h = PluginHost(directory: dest); ContentColumnRegistry.shared.removeAll()
        let loaded = h.reload().filter { $0.id != "filehash" }
        #expect(loaded.allSatisfy { $0.error == nil }, "\(loaded.compactMap(\.error))")
        ContentColumnRegistry.shared.removeAll()
    }

    @Test func locatesTheSampleFolderInTheBundleOrNextToTheSources() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let res = d.appendingPathComponent("Resources/PluginExamples"); try FileManager.default.createDirectory(at: res, withIntermediateDirectories: true)
        #expect(PluginExamples.sourceDirectory(resources: d.appendingPathComponent("Resources"), executable: nil)?.path == res.path)
        let exe = ExamplePlugins.sourceRoot.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/debug/TCommander")
        #expect(PluginExamples.sourceDirectory(resources: nil, executable: exe)?.lastPathComponent == "plugin-examples")
        #expect(PluginExamples.sourceDirectory(resources: nil, executable: d.appendingPathComponent("x/y/prog")) == nil)
    }
}
}
