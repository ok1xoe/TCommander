import Testing
import Foundation
@testable import TCCore

@Suite struct PlantUMLTests {
    @Test func recognizesDiagramFilesAndOffersDiagramFirst() {
        for n in ["a.puml", "a.PLANTUML", "a.pu", "a.wsd", "a.iuml"] { #expect(PlantUML.isDiagramFile(URL(fileURLWithPath: "/x/\(n)")), "\(n)") }
        #expect(!PlantUML.isDiagramFile(URL(fileURLWithPath: "/x/a.txt")))
        #expect(ListerSupport.modes(for: URL(fileURLWithPath: "/x/a.puml"), sample: Data("@startuml".utf8)) == [.diagram, .text, .hex])
    }

    @Test func ordersRenderedImagesByDiagramNumber() {
        func i(_ n: String) -> Int { PlantUML.diagramIndex(of: URL(fileURLWithPath: "/o/\(n)")) }
        #expect(i("d.png") == 0 && i("d_001.png") == 1 && i("d_010.png") == 10 && i("my_file.png") == 0 && i("my_file_002.png") == 2)
    }

    @Test func configuredPathIsNotOverriddenByAutoDetection() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("puml-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        #expect(PlantUML.locate(configured: d.appendingPathComponent("neexistuje.jar").path) == nil)           // zadaná cesta neexistuje → nic nenajde
        let exe = d.appendingPathComponent("plantuml"); try "#!/bin/sh\n".write(to: exe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
        #expect(PlantUML.locate(configured: exe.path) == PlantUML.Launcher(executable: exe.path, prefixArguments: []))
        let plain = d.appendingPathComponent("plain"); try "x".write(to: plain, atomically: true, encoding: .utf8)
        #expect(PlantUML.locate(configured: plain.path) == nil)                                               // nespustitelný soubor
    }

    @Test func rendersWithAFakeLauncherAndReportsErrors() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("puml-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        let src = d.appendingPathComponent("a.puml"); try "@startuml\nA->B\n@enduml".write(to: src, atomically: true, encoding: .utf8)
        // „PlantUML“ ze skriptu: vytvoří dva obrázky v adresáři za přepínačem -output
        let ok = d.appendingPathComponent("fake-ok.sh")
        try "#!/bin/sh\nwhile [ $# -gt 0 ]; do [ \"$1\" = -output ] && out=\"$2\"; shift; done\nprintf x > \"$out/a.png\"; printf y > \"$out/a_001.png\"\n".write(to: ok, atomically: true, encoding: .utf8)
        let bad = d.appendingPathComponent("fake-bad.sh")
        try "#!/bin/sh\necho 'Syntax Error?' >&2\nexit 200\n".write(to: bad, atomically: true, encoding: .utf8)
        for f in [ok, bad] { try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.path) }
        let images = try PlantUML.render(file: src, into: d.appendingPathComponent("out"), launcher: .init(executable: ok.path, prefixArguments: []))
        #expect(images.map(\.lastPathComponent) == ["a.png", "a_001.png"])
        #expect(throws: PlantUML.RenderError.self) { try PlantUML.render(file: src, into: d.appendingPathComponent("out2"), launcher: .init(executable: bad.path, prefixArguments: [])) }
        do { _ = try PlantUML.render(file: src, into: d.appendingPathComponent("out3"), launcher: .init(executable: bad.path, prefixArguments: [])) }
        catch { #expect("\(error.localizedDescription)".contains("Syntax Error")) }
    }

    @Test(.enabled(if: PlantUML.locate(extraJarDirectories: [NSHomeDirectory() + "/Library/Application Support/macTC"]) != nil, "PlantUML není nainstalovaný"))
    func rendersARealDiagram() throws {
        let launcher = try #require(PlantUML.locate(extraJarDirectories: [NSHomeDirectory() + "/Library/Application Support/macTC"]))
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("puml-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: d) }
        let src = d.appendingPathComponent("two.puml")
        try "@startuml\nAlice -> Bob : ahoj\n@enduml\n@startuml\nclass A\n@enduml\n".write(to: src, atomically: true, encoding: .utf8)
        let images = try PlantUML.render(file: src, into: d.appendingPathComponent("o"), launcher: launcher)
        #expect(images.count == 2)
        for u in images { #expect(try Data(contentsOf: u).prefix(4) == Data([0x89, 0x50, 0x4E, 0x47])) }           // PNG
    }
}
