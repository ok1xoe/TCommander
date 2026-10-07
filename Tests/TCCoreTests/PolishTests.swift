import Testing
import Foundation
@testable import TCCore

@Suite struct SearchPolishTests {
    func run(_ c: SearchCriteria) -> [String] {
        nonisolated(unsafe) var names: [String] = []
        FileSearch().run(c) { names.append($0.url.lastPathComponent) }
        return names.sorted()
    }

    @Test func attributesAndExclusionFilters() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let script = try write(d, "run.sh"), ro = try write(d, "ro.txt"), plain = try write(d, "plain.txt"); try write(d, ".secret", "x"); try write(d, "skip.tmp")
        try FileAttributes.apply(script, permissions: 0o755); try FileAttributes.apply(ro, permissions: 0o444); try FileAttributes.apply(plain, permissions: 0o644)
        var c = SearchCriteria(root: d)
        c.attributes = .executable; #expect(run(c) == ["run.sh"])
        c.attributes = .readOnly; #expect(run(c) == ["ro.txt"])
        c.attributes = .hidden; #expect(run(c) == [".secret"])           // skryté se najdou i bez volby „skryté“
        c = SearchCriteria(root: d); c.excludeMasks = "*.tmp;*.sh"
        #expect(run(c) == ["plain.txt", "ro.txt"])
    }

    @Test func templateBuildsCriteria() {
        let t = SearchTemplate(name: "Logy", masks: "*.log", excludeMasks: "old*", text: "ERROR", hidden: true, regex: true, minKB: "1", maxKB: "100", days: "7", attributes: .readOnly)
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        let c = t.criteria(root: URL(fileURLWithPath: "/x"), now: now)
        #expect(c.masks == "*.log" && c.excludeMasks == "old*" && c.text == "ERROR" && c.includeHidden && c.useRegex)
        #expect(c.minSize == 1024 && c.maxSize == 102_400 && c.modifiedAfter == now.addingTimeInterval(-7 * 86_400) && c.attributes == .readOnly)
        #expect(SearchTemplate(name: "x", masks: "").criteria(root: URL(fileURLWithPath: "/")).masks == "*")
        let back = try? JSONDecoder().decode(SearchTemplate.self, from: JSONEncoder().encode(t))
        #expect(back == t)
    }
}

@Suite struct ListerPolishTests {
    @Test func parsesHexAndTextQueries() {
        #expect(HexSearch.pattern(from: "4D 5A") == Data([0x4D, 0x5A]))
        #expect(HexSearch.pattern(from: "0x4d5a") == Data([0x4D, 0x5A]))
        #expect(HexSearch.pattern(from: "deadbeef") == Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(HexSearch.pattern(from: "hello") == Data("hello".utf8))
        #expect(HexSearch.pattern(from: "abc") == Data("abc".utf8))            // lichý počet číslic = text
        #expect(HexSearch.pattern(from: "  ") == nil)
    }

    @Test func findsOccurrencesCyclically() {
        let d = Data("..abc..abc..".utf8), p = Data("abc".utf8)
        #expect(HexSearch.find(p, in: d, from: 0) == 2)
        #expect(HexSearch.find(p, in: d, from: 3) == 7)
        #expect(HexSearch.find(p, in: d, from: 8) == 2)                          // od konce zpět na začátek
        #expect(HexSearch.find(Data("zzz".utf8), in: d, from: 0) == nil && HexSearch.find(Data(), in: d, from: 0) == nil)
    }

    @Test func pagesRespectLineAndCharacterBoundaries() {
        let text = (0..<2000).map { "řádek číslo \($0) žluťoučký\n" }.joined()
        let data = Data(text.utf8)
        let size = 4096
        let n = TextPager.count(of: data.count, size: size)
        var rebuilt = Data()
        for i in 0..<n {
            let r = TextPager.range(in: data, index: i, size: size)
            let chunk = data[r]
            #expect(String(data: chunk, encoding: .utf8) != nil, "část \(i) rozděluje znak UTF-8")
            if i < n - 1 { #expect(chunk.last == 10, "část \(i) nekončí řádkem") }
            rebuilt.append(chunk)
        }
        #expect(rebuilt == data)                                                  // části navazují bez mezer a překryvů
        #expect(TextPager.range(in: Data("abc".utf8), index: 0, size: 100) == 0..<3 && TextPager.count(of: 0, size: 10) == 1)
    }
}

@MainActor @Suite struct ResultsPanelAndArchiveSyncTests {
    @Test func resultsPanelListsFlatFilesAndLeavesOnNavigate() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "x/a.txt", "A"), b = try write(d, "y/z/b.txt", "BB")
        let t = PanelTab(path: d)
        t.showResults([a, b, d.appendingPathComponent("missing")], title: "Výsledky (2)")
        #expect(t.resultURLs?.count == 3 && t.displayPath == "Výsledky (2)" && t.isBranch)
        #expect(t.entries.filter { !$0.isParentLink }.map(\.url) == [a, b])
        t.moveCursor(to: t.entries.firstIndex { $0.url == b }!)
        #expect(t.targets.map(\.url) == [b])                                      // operace se skutečnými soubory
        try FileManager.default.removeItem(at: a)
        t.reload()
        #expect(t.entries.filter { !$0.isParentLink }.map(\.url) == [b])          // po obnovení zmizelé soubory vypadnou
        t.navigate(to: d.appendingPathComponent("x"))
        #expect(t.resultURLs == nil && !t.isBranch && t.displayPath == d.appendingPathComponent("x").standardizedFileURL.path)
    }

    @Test func archiveSyncRoundTrip() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let src = try write(d, "src/keep.txt", "keep"); try write(d, "src/dir/old.txt", "old")
        let zip = d.appendingPathComponent("a.zip")
        #expect(ArchiveWriter.create(zip, format: .zip, sources: [src, src.deletingLastPathComponent().appendingPathComponent("dir")]).failures.isEmpty)
        let local = d.appendingPathComponent("local"); try write(d, "local/keep.txt", "keep"); try write(d, "local/new.txt", "new")
        let staged = try ArchiveSyncSupport.extractToTemporary(zip); defer { ArchiveSyncSupport.cleanup(staged) }
        // porovnání lokálního adresáře s rozbaleným archivem a zrcadlení zleva doprava
        let plan = SyncPlanner.plan(DirectoryComparer.compare(left: local, right: staged.directory), direction: .mirrorLeftToRight)
        #expect(SyncPlanner.execute(plan, left: local, right: staged.directory, toTrash: false).failures.isEmpty)
        #expect(ArchiveSyncSupport.repack(staged).failures.isEmpty)
        let result = try ArchiveFileSystem(archiveURL: zip)
        #expect(Set(result.entries.filter { !$0.isDirectory }.map(\.path)) == ["keep.txt", "new.txt"])
        #expect(staged.format == .zip)
        // formát jen pro čtení se nepřepíše
        let iso = d.appendingPathComponent("a.iso"); try FileManager.default.copyItem(at: zip, to: iso)
        let st2 = try ArchiveSyncSupport.extractToTemporary(iso); defer { ArchiveSyncSupport.cleanup(st2) }
        #expect(ArchiveSyncSupport.repack(st2).failures.count == 1)
    }
}
