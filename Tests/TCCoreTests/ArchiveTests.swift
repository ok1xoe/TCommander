import Testing
import Foundation
@testable import TCCore

@Suite struct ArchiveTests {
    /// Vytvoří adresář se souborovým stromem a z něj zip a tar.gz pomocí systémových nástrojů.
    func fixture() throws -> (root: URL, zip: URL, tgz: URL) {
        let d = try makeTempDir()
        try write(d, "src/readme.txt", "hello archive", mtime: Date(timeIntervalSince1970: 1_600_000_000))
        try write(d, "src/docs/guide.md", "# guide")
        try write(d, "src/docs/deep/data.bin", String(repeating: "x", count: 100_000))
        try write(d, "src/příliš žluťoučký.txt", "unicode název")
        try FileManager.default.createSymbolicLink(atPath: d.appendingPathComponent("src/link").path, withDestinationPath: "readme.txt")
        let zip = d.appendingPathComponent("a.zip"), tgz = d.appendingPathComponent("a.tar.gz")
        #expect(Shell.run("cd src && zip -qry ../a.zip .", in: d).status == 0)
        #expect(Shell.run("cd src && tar -czf ../a.tar.gz .", in: d).status == 0)
        return (d, zip, tgz)
    }

    @Test func recognizesArchiveNames() {
        for n in ["a.zip", "A.ZIP", "b.tar.gz", "c.tgz", "d.7z", "e.rar", "f.tar.xz", "g.iso"] { #expect(ArchiveSupport.isArchive(n), "\(n)") }
        for n in ["a.txt", "b.gz", "c", "d.app", "zip"] { #expect(!ArchiveSupport.isArchive(n), "\(n)") }
    }

    @Test func listsZipAsDirectoryTree() throws {
        let (d, zip, _) = try fixture(); defer { try? FileManager.default.removeItem(at: d) }
        let fs = try ArchiveFileSystem(archiveURL: zip)
        let root = try fs.list(URL(fileURLWithPath: "/"), includeHidden: true)
        #expect(Set(root.map(\.name)) == ["readme.txt", "docs", "příliš žluťoučký.txt", "link"])
        #expect(root.first { $0.name == "docs" }?.isDirectory == true)
        #expect(try fs.list(URL(fileURLWithPath: "/docs"), includeHidden: true).map(\.name).sorted() == ["deep", "guide.md"])
        let f = try fs.stat(URL(fileURLWithPath: "/docs/deep/data.bin"))
        #expect(f.size == 100_000 && !f.isDirectory)
        #expect(try fs.stat(URL(fileURLWithPath: "/link")).isSymlink)
        #expect(fs.exists(URL(fileURLWithPath: "/docs/deep")) && !fs.exists(URL(fileURLWithPath: "/nope")))
        #expect(throws: Error.self) { try fs.list(URL(fileURLWithPath: "/readme.txt"), includeHidden: true) }
        #expect(throws: Error.self) { try fs.remove(URL(fileURLWithPath: "/readme.txt")) }       // jen pro čtení
    }

    @Test func listsTarGzIncludingImplicitDirectories() throws {
        let (d, _, tgz) = try fixture(); defer { try? FileManager.default.removeItem(at: d) }
        let fs = try ArchiveFileSystem(archiveURL: tgz)
        #expect(Set(try fs.list(URL(fileURLWithPath: "/"), includeHidden: true).map(\.name)) == ["readme.txt", "docs", "příliš žluťoučký.txt", "link"])
        #expect(fs.entries.contains { $0.path == "docs/deep" && $0.isDirectory })
    }

    @Test func extractsSelectionWithStructureAndMetadata() throws {
        let (d, zip, _) = try fixture(); defer { try? FileManager.default.removeItem(at: d) }
        let out = d.appendingPathComponent("out"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let fs = try ArchiveFileSystem(archiveURL: zip)
        final class Box: @unchecked Sendable { var last = TransferProgress() }
        let box = Box()
        let r = fs.extract(["docs", "readme.txt"], to: out, progress: { box.last = $0 })
        #expect(r.failures.isEmpty && r.succeeded == 2)
        #expect(try String(contentsOf: out.appendingPathComponent("docs/guide.md"), encoding: .utf8) == "# guide")
        #expect(try Data(contentsOf: out.appendingPathComponent("docs/deep/data.bin")).count == 100_000)
        #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("link").path))
        let m = try LocalFileSystem().stat(out.appendingPathComponent("readme.txt")).modified
        #expect(abs((m ?? .distantPast).timeIntervalSince1970 - 1_600_000_000) < 3)
        #expect(box.last.bytesDone == box.last.bytesTotal && box.last.bytesTotal == 100_000 + 7 + 13)
    }

    @Test func extractAllRestoresSymlinkAndUnicode() throws {
        let (d, _, tgz) = try fixture(); defer { try? FileManager.default.removeItem(at: d) }
        let out = d.appendingPathComponent("all"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let r = try ArchiveFileSystem(archiveURL: tgz).extractAll(to: out)
        #expect(r.failures.isEmpty)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: out.appendingPathComponent("link").path) == "readme.txt")
        #expect(try String(contentsOf: out.appendingPathComponent("příliš žluťoučký.txt"), encoding: .utf8) == "unicode název")
    }

    @Test func conflictPolicies() throws {
        let (d, zip, _) = try fixture(); defer { try? FileManager.default.removeItem(at: d) }
        let out = d.appendingPathComponent("o"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let existing = try write(out, "readme.txt", "mine")
        let fs = try ArchiveFileSystem(archiveURL: zip)
        var r = fs.extract(["readme.txt"], to: out, policy: .skip)
        let kept = try String(contentsOf: existing, encoding: .utf8)
        #expect(r.skipped == 1 && kept == "mine")
        r = fs.extract(["readme.txt"], to: out, policy: .keepBoth)
        #expect(r.succeeded == 1 && FileManager.default.fileExists(atPath: out.appendingPathComponent("readme copy.txt").path))
        r = fs.extract(["readme.txt"], to: out, policy: .overwrite)
        #expect(try String(contentsOf: existing, encoding: .utf8) == "hello archive")
    }

    @Test func refusesPathTraversal() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let script = """
        import tarfile, io
        t = tarfile.open('evil.tar', 'w')
        for name in ['../evil.txt', 'ok.txt']:
            i = tarfile.TarInfo(name); i.size = 3; t.addfile(i, io.BytesIO(b'bad'))
        t.close()
        """
        try script.write(to: d.appendingPathComponent("mk.py"), atomically: true, encoding: .utf8)
        #expect(Shell.run("python3 mk.py", in: d).status == 0)
        let out = d.appendingPathComponent("sub/out"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let fs = try ArchiveFileSystem(archiveURL: d.appendingPathComponent("evil.tar"))
        let r = fs.extract(["../evil.txt", "ok.txt"], to: out)
        #expect(!FileManager.default.fileExists(atPath: d.appendingPathComponent("sub/evil.txt").path))
        #expect(!FileManager.default.fileExists(atPath: d.appendingPathComponent("evil.txt").path))
        #expect(r.failures.count == 1 && FileManager.default.fileExists(atPath: out.appendingPathComponent("ok.txt").path))
    }

    @Test func cancelAndBadArchive() throws {
        let (d, zip, _) = try fixture(); defer { try? FileManager.default.removeItem(at: d) }
        let out = d.appendingPathComponent("c"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let c = OperationControl(); c.cancel()
        #expect(try ArchiveFileSystem(archiveURL: zip).extractAll(to: out, control: c).cancelled)
        let junk = try write(d, "junk.zip", "this is not an archive")
        #expect(throws: Error.self) { try ArchiveFileSystem(archiveURL: junk) }
        #expect(throws: Error.self) { try ArchiveFileSystem(archiveURL: d.appendingPathComponent("missing.zip")) }
    }
}

@MainActor @Suite struct ArchivePanelTests {
    func zipFixture() throws -> (d: URL, zip: URL) {
        let d = try makeTempDir()
        try write(d, "src/a.txt", "A"); try write(d, "src/sub/b.txt", "B")
        #expect(Shell.run("cd src && zip -qr ../x.zip .", in: d).status == 0)
        try FileManager.default.removeItem(at: d.appendingPathComponent("src"))
        return (d, d.appendingPathComponent("x.zip"))
    }

    @Test func enterNavigateAndLeaveArchive() throws {
        let (d, zip) = try zipFixture(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        t.moveCursor(to: t.entries.firstIndex { $0.name == "x.zip" }!)
        #expect(t.activateCursor() == nil && t.insideArchive && t.archiveFile == zip)
        #expect(t.entries.map(\.name) == ["..", "sub", "a.txt"])
        #expect(t.displayPath.hasSuffix("x.zip ▸ /") && t.persistentPath == d.standardizedFileURL)
        t.moveCursor(to: 1); #expect(t.activateCursor() == nil && t.path.path == "/sub")
        #expect(t.entries.map(\.name) == ["..", "b.txt"])
        t.goUp(); #expect(t.path.path == "/" && t.insideArchive)
        t.goUp()                                                  // z kořene archivu zpět na disk
        #expect(!t.insideArchive && t.path == d.standardizedFileURL && t.cursorEntry?.name == "x.zip")
        #expect(t.recent.allSatisfy { !$0.path.hasPrefix("/sub") })
    }

    @Test func fileInArchiveIsReturnedForOpening() throws {
        let (d, _) = try zipFixture(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        t.moveCursor(to: t.entries.firstIndex { $0.name == "x.zip" }!); _ = t.activateCursor()
        t.moveCursor(to: t.entries.firstIndex { $0.name == "a.txt" }!)
        let u = try #require(t.activateCursor())
        let tmp = try #require(t.archiveFS).extractToTemporary(u.path)
        #expect(try String(contentsOf: tmp, encoding: .utf8) == "A")
        ArchiveFileSystem.cleanTemporary()
        #expect(!FileManager.default.fileExists(atPath: tmp.path))
    }

    @Test func brokenArchiveReportsErrorAndStaysOnDisk() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        try write(d, "bad.zip", "nope")
        let t = PanelTab(path: d)
        t.moveCursor(to: t.entries.firstIndex { $0.name == "bad.zip" }!)
        #expect(t.activateCursor()?.lastPathComponent == "bad.zip")       // vrátí soubor k otevření systémem
        #expect(!t.insideArchive && t.error != nil)
    }

    @Test func archiveIntegrityTest() throws {
        let (d, zip) = try zipFixture(); defer { try? FileManager.default.removeItem(at: d) }
        let r = try ArchiveFileSystem(archiveURL: zip).test()
        #expect(r.failures.isEmpty && r.succeeded == 2)
    }
}
