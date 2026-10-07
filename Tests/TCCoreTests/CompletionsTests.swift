import Testing
import Foundation
@testable import TCCore

@Suite struct AttributeCompletionTests {
    @Test func ownerGroupAndFlags() throws {
        let d = try makeTempDir(); defer { try? FileAttributes.setFlags(d.appendingPathComponent("f"), set: [], clear: [.immutable]); try? FileManager.default.removeItem(at: d) }
        let f = try write(d, "f", "x")
        let e = try LocalFileSystem().stat(f)
        #expect(FileAttributes.ownerName(e.ownerID) == NSUserName() && !FileAttributes.groupName(e.groupID).isEmpty)
        #expect(FileAttributes.flags(of: f) == [])
        try FileAttributes.setFlags(f, set: [.hidden, .noDump], clear: [])
        #expect(FileAttributes.flags(of: f) == [.hidden, .noDump])
        try FileAttributes.setFlags(f, set: [], clear: [.hidden])
        #expect(FileAttributes.flags(of: f) == [.noDump])
        #expect(FileAttributes.flags(of: d.appendingPathComponent("missing")) == nil)
    }

    @Test func recursiveApplyIncludingLockedFiles() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "t/a.txt"), b = try write(d, "t/sub/b.txt")
        try FileAttributes.setFlags(b, set: [.immutable], clear: [])                 // zamčený soubor v adresáři
        let when = Date(timeIntervalSince1970: 1_500_000_000)
        let errors = FileAttributes.applyRecursively(d.appendingPathComponent("t"), permissions: 0o750, modified: when, recursive: true)
        #expect(errors.isEmpty, "\(errors)")
        for u in [a, b] {
            let e = try LocalFileSystem().stat(u)
            #expect(e.permissions == 0o750 && e.modified == when, "\(u.lastPathComponent)")
        }
        #expect(FileAttributes.flags(of: b) == [.immutable])                         // zámek zůstal zachován
        try FileAttributes.setFlags(b, set: [], clear: [.immutable])
        // bez rekurze se potomci nemění
        _ = FileAttributes.applyRecursively(d.appendingPathComponent("t"), permissions: 0o700, modified: nil, recursive: false)
        #expect(try LocalFileSystem().stat(a).permissions == 0o750 && LocalFileSystem().stat(d.appendingPathComponent("t")).permissions == 0o700)
        // adresář bez práva vstupu: obsah se zpracuje dřív, takže operace uspěje
        let errs = FileAttributes.applyRecursively(d.appendingPathComponent("t"), permissions: 0o600, modified: nil, recursive: true)
        #expect(errs.isEmpty)
        try FileAttributes.apply(d.appendingPathComponent("t"), permissions: 0o700); try FileAttributes.apply(d.appendingPathComponent("t/sub"), permissions: 0o700)
    }
}

@Suite struct SearchOlderThanTests {
    @Test func olderThanDaysFindsOnlyOldFiles() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        try write(d, "old.txt", "x", mtime: Date().addingTimeInterval(-40 * 86_400)); try write(d, "new.txt", "x", mtime: Date().addingTimeInterval(-2 * 86_400))
        var t = SearchTemplate(name: "x", olderDays: "30")
        nonisolated(unsafe) var names: [String] = []
        FileSearch().run(t.criteria(root: d)) { names.append($0.url.lastPathComponent) }
        #expect(names == ["old.txt"])
        t.olderDays = ""; t.days = "30"; names = []
        FileSearch().run(t.criteria(root: d)) { names.append($0.url.lastPathComponent) }
        #expect(names == ["new.txt"])
        // šablona uložená starší verzí (bez olderDays) se načte
        let json = #"{"name":"stará","masks":"*.log"}"#
        let old = try JSONDecoder().decode(SearchTemplate.self, from: Data(json.utf8))
        #expect(old.olderDays.isEmpty && old.masks == "*.log" && old.subdirectories)
    }
}

@Suite struct DiffMergeTests {
    func rows(_ a: [String], _ b: [String]) -> [LineDiff.Row] { LineDiff.sideBySide(a, b, LineDiff.diff(a, b)!) }

    @Test func findsBlocksAndCopiesThem() {
        let r = rows(["a", "b", "c", "d", "e"], ["a", "X", "c", "d", "e", "f"])
        #expect(DiffMerge.blocks(r) == [1..<2, 5..<6])
        #expect(DiffMerge.block(containing: 0, in: r) == 1..<2 && DiffMerge.block(containing: 3, in: r) == 5..<6 && DiffMerge.block(containing: 6, in: r) == nil)
        let toRight = DiffMerge.apply(r, block: 1..<2, toRight: true)
        #expect(DiffMerge.lines(toRight, right: true) == ["a", "b", "c", "d", "e", "f"] && DiffMerge.lines(toRight, right: false) == ["a", "b", "c", "d", "e"])
        let toLeft = DiffMerge.apply(r, block: 5..<6, toRight: false)           // řádek „f“ jen vpravo se zkopíruje doleva
        #expect(DiffMerge.lines(toLeft, right: false) == ["a", "b", "c", "d", "e", "f"])
        // přenos „doprava“ u bloku, kde vlevo řádek chybí, řádek vpravo smaže
        let drop = DiffMerge.apply(r, block: 5..<6, toRight: true)
        #expect(DiffMerge.lines(drop, right: true) == ["a", "X", "c", "d", "e"])
        // po přenosu všech bloků jsou strany shodné
        var all = r
        for b in DiffMerge.blocks(r).reversed() { all = DiffMerge.apply(all, block: b, toRight: true) }
        #expect(DiffMerge.lines(all, right: true) == DiffMerge.lines(all, right: false) && DiffMerge.blocks(all).isEmpty)
    }

    @Test func binaryDiffReportsDifferences() {
        let a = Data(repeating: 1, count: 100)
        var b = a; b[3] = 9; b[40] = 9; b[41] = 9
        let r = BinaryDiff.compare(a, b)
        #expect(r.sameSize && r.differingBytes == 3 && r.rows == [0, 2] && !r.identical && !r.truncated)
        #expect(BinaryDiff.compare(a, a).identical)
        let longer = BinaryDiff.compare(a, a + Data(repeating: 2, count: 40))
        #expect(!longer.sameSize && longer.differingBytes == 40 && longer.rows.first == 6)
        #expect(BinaryDiff.compare(Data(repeating: 0, count: 50_000), Data(repeating: 1, count: 50_000), maxRows: 100).truncated)
    }
}

@Suite struct ListerCompletionTests {
    @Test func forcedEncodingsAndOffsets() {
        let cp = Data([0x50, 0xF8, 0xED, 0x6C, 0x69, 0x9A])                      // „Příliš“ ve Windows-1250
        #expect(TextDecoding.decode(cp, forced: "Windows-1250") == "Příliš" && TextDecoding.decode(cp, forced: "Automaticky") == "Příliš")
        #expect(TextDecoding.decode(Data("žluť".utf8), forced: "UTF-8") == "žluť")
        #expect(TextDecoding.decode(Data([0xFF, 0xFE, 0x41, 0x00]), forced: "UTF-16 LE") == "A")
        #expect(TextDecoding.decode(Data([0xE8]), forced: "ISO-8859-2") == "č")
        #expect(TextDecoding.selectableEncodings.first == "Automaticky")
        #expect(TextDecoding.parseOffset("255") == 255 && TextDecoding.parseOffset("0xFF") == 255 && TextDecoding.parseOffset("ff") == 255 && TextDecoding.parseOffset("zz") == nil)
    }
}

@Suite struct SFTPProxyTests {
    @Test func buildsProxyCommands() {
        #expect(SFTPConnection.proxyCommand(from: "socks5://127.0.0.1:1080") == "/usr/bin/nc -X 5 -x 127.0.0.1:1080 %h %p")
        #expect(SFTPConnection.proxyCommand(from: "socks4://proxy.local:9050") == "/usr/bin/nc -X 4 -x proxy.local:9050 %h %p")
        #expect(SFTPConnection.proxyCommand(from: "http://proxy:3128") == "/usr/bin/nc -X connect -x proxy:3128 %h %p")
        for bad in ["", "ftp://x:1", "socks5://nohost", "proxy:3128", "socks5://:1080"] { #expect(SFTPConnection.proxyCommand(from: bad) == nil, "\(bad)") }
        #expect(SavedConnection(name: "s", kind: .sftp, host: "h", proxy: "socks5://a:1").sftpConnection(password: "").proxy == "socks5://a:1")
    }
}
