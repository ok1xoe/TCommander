import Testing
import Foundation
@testable import TCCore

@Suite struct ArchiveWriterTests {
    func sources() throws -> (d: URL, items: [URL]) {
        let d = try makeTempDir()
        try write(d, "in/hello.txt", "hello", mtime: Date(timeIntervalSince1970: 1_600_000_000))
        try write(d, "in/folder/inner.txt", "inner")
        try write(d, "in/folder/deep/big.bin", String(repeating: "y", count: 200_000))
        try write(d, "in/příliš.txt", "unicode")
        try FileManager.default.createSymbolicLink(atPath: d.appendingPathComponent("in/folder/ln").path, withDestinationPath: "inner.txt")
        let in_ = d.appendingPathComponent("in")
        return (d, [in_.appendingPathComponent("hello.txt"), in_.appendingPathComponent("folder"), in_.appendingPathComponent("příliš.txt")])
    }

    func names(_ fs: ArchiveFileSystem) -> Set<String> { Set(fs.entries.map(\.path)) }

    @Test(arguments: ArchiveFormat.allCases) func createsReadableArchiveInEveryFormat(_ format: ArchiveFormat) throws {
        let (d, items) = try sources(); defer { try? FileManager.default.removeItem(at: d) }
        let out = d.appendingPathComponent("test.\(format.fileExtension)")
        final class Box: @unchecked Sendable { var last = TransferProgress() }
        let box = Box()
        let r = ArchiveWriter.create(out, format: format, sources: items, progress: { box.last = $0 })
        #expect(r.failures.isEmpty && r.succeeded == 1, "\(format)")
        let fs = try ArchiveFileSystem(archiveURL: out)
        #expect(names(fs) == ["hello.txt", "folder", "folder/inner.txt", "folder/deep", "folder/deep/big.bin", "folder/ln", "příliš.txt"])
        #expect(fs.isWritable && ArchiveFormat.detect(fileName: out.lastPathComponent) == format)
        #expect(box.last.bytesDone == box.last.bytesTotal && box.last.bytesTotal == 5 + 5 + 200_000 + 7)
        let x = d.appendingPathComponent("x"); try FileManager.default.createDirectory(at: x, withIntermediateDirectories: true)
        #expect(fs.extractAll(to: x).failures.isEmpty)
        #expect(try String(contentsOf: x.appendingPathComponent("folder/inner.txt"), encoding: .utf8) == "inner")
        #expect(try Data(contentsOf: x.appendingPathComponent("folder/deep/big.bin")).count == 200_000)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: x.appendingPathComponent("folder/ln").path) == "inner.txt")
        let m = try LocalFileSystem().stat(x.appendingPathComponent("hello.txt")).modified
        #expect(abs((m ?? .distantPast).timeIntervalSince1970 - 1_600_000_000) < 3)
    }

    @Test func systemTarAgreesWithOurTarGz() throws {
        let (d, items) = try sources(); defer { try? FileManager.default.removeItem(at: d) }
        let out = d.appendingPathComponent("o.tar.gz")
        #expect(ArchiveWriter.create(out, format: .tarGz, sources: items).failures.isEmpty)
        let listing = Shell.run("tar -tzf o.tar.gz", in: d)
        #expect(listing.status == 0 && listing.output.contains("folder/deep/big.bin"))
    }

    @Test func addRemoveRenameReplaceInPlace() throws {
        let (d, items) = try sources(); defer { try? FileManager.default.removeItem(at: d) }
        let zip = d.appendingPathComponent("a.zip")
        #expect(ArchiveWriter.create(zip, format: .zip, sources: items).failures.isEmpty)
        let extra = try write(d, "extra/new.txt", "NEW"), replacement = try write(d, "extra/hello.txt", "REPLACED")

        var c = ArchiveFileSystem.Changes()
        c.add = [.init(local: extra, innerDirectory: "folder"), .init(local: replacement, innerDirectory: "")]
        c.remove = ["folder/deep"]
        c.rename = ["příliš.txt": "renamed.txt", "folder/inner.txt": "folder/moved.txt"]
        c.makeDirectories = ["empty/sub"]
        let r = try ArchiveFileSystem(archiveURL: zip).apply(c)
        #expect(r.failures.isEmpty && r.succeeded == 1)

        let fs = try ArchiveFileSystem(archiveURL: zip)
        #expect(names(fs) == ["hello.txt", "folder", "folder/moved.txt", "folder/ln", "folder/new.txt", "renamed.txt", "empty", "empty/sub"])
        let x = d.appendingPathComponent("x"); try FileManager.default.createDirectory(at: x, withIntermediateDirectories: true)
        #expect(fs.extractAll(to: x).failures.isEmpty)
        #expect(try String(contentsOf: x.appendingPathComponent("hello.txt"), encoding: .utf8) == "REPLACED")
        #expect(try String(contentsOf: x.appendingPathComponent("folder/moved.txt"), encoding: .utf8) == "inner")
        #expect(try String(contentsOf: x.appendingPathComponent("folder/new.txt"), encoding: .utf8) == "NEW")
        #expect(try String(contentsOf: x.appendingPathComponent("renamed.txt"), encoding: .utf8) == "unicode")
        // žádné dočasné soubory vedle archivu
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path).filter { $0.hasPrefix(".macTC-") }.isEmpty)
    }

    @Test func modifyKeepsFormatForTarGzAnd7z() throws {
        let (d, items) = try sources(); defer { try? FileManager.default.removeItem(at: d) }
        let add = try write(d, "extra/more.txt", "more")
        for ext in ["tar.gz", "7z"] {
            let out = d.appendingPathComponent("m.\(ext)")
            #expect(ArchiveWriter.create(out, format: ArchiveFormat.detect(fileName: out.lastPathComponent)!, sources: items).failures.isEmpty)
            var c = ArchiveFileSystem.Changes(); c.add = [.init(local: add, innerDirectory: "")]; c.remove = ["hello.txt"]
            #expect(try ArchiveFileSystem(archiveURL: out).apply(c).failures.isEmpty, "\(ext)")
            let n = names(try ArchiveFileSystem(archiveURL: out))
            #expect(n.contains("more.txt") && !n.contains("hello.txt") && n.contains("folder/inner.txt"), "\(ext)")
        }
    }

    @Test func readOnlyFormatsAndBadInputAreRejectedSafely() throws {
        let (d, items) = try sources(); defer { try? FileManager.default.removeItem(at: d) }
        let zip = d.appendingPathComponent("a.zip")
        _ = ArchiveWriter.create(zip, format: .zip, sources: items)
        let renamedISO = d.appendingPathComponent("a.iso"); try FileManager.default.copyItem(at: zip, to: renamedISO)
        let iso = try ArchiveFileSystem(archiveURL: renamedISO)
        #expect(!iso.isWritable && iso.apply(ArchiveFileSystem.Changes()).failures.count == 1)

        let before = try Data(contentsOf: zip)
        var bad = ArchiveFileSystem.Changes(); bad.rename = ["hello.txt": "../escape.txt"]
        #expect(try ArchiveFileSystem(archiveURL: zip).apply(bad).failures.count == 1)
        var bad2 = ArchiveFileSystem.Changes(); bad2.makeDirectories = ["../x"]
        #expect(try ArchiveFileSystem(archiveURL: zip).apply(bad2).failures.count == 1)
        #expect(try Data(contentsOf: zip) == before)       // původní archiv zůstal nedotčený
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path).filter { $0.hasPrefix(".macTC-") }.isEmpty)
    }

    @Test func cancelLeavesOriginalAndNoTempFile() throws {
        let (d, items) = try sources(); defer { try? FileManager.default.removeItem(at: d) }
        let zip = d.appendingPathComponent("a.zip")
        _ = ArchiveWriter.create(zip, format: .zip, sources: items)
        let before = try Data(contentsOf: zip)
        let c = OperationControl(); c.cancel()
        var ch = ArchiveFileSystem.Changes(); ch.add = [.init(local: items[0], innerDirectory: "sub")]
        #expect(try ArchiveFileSystem(archiveURL: zip).apply(ch, control: c).cancelled)
        #expect(try Data(contentsOf: zip) == before)
        let newOne = d.appendingPathComponent("new.zip")
        #expect(ArchiveWriter.create(newOne, format: .zip, sources: items, control: c).cancelled)
        #expect(!FileManager.default.fileExists(atPath: newOne.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path).filter { $0.hasPrefix(".macTC-") }.isEmpty)
    }
}

@MainActor @Suite struct ArchivePanelWriteTests {
    @Test func panelShowsModifiedArchiveAfterRefresh() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "in/a.txt", "A")
        let zip = d.appendingPathComponent("p.zip")
        #expect(ArchiveWriter.create(zip, format: .zip, sources: [a]).failures.isEmpty)
        let t = PanelTab(path: d)
        t.moveCursor(to: t.entries.firstIndex { $0.name == "p.zip" }!); _ = t.activateCursor()
        #expect(t.entries.map(\.name) == ["..", "a.txt"])
        let b = try write(d, "in/b.txt", "B")
        var c = ArchiveFileSystem.Changes(); c.add = [.init(local: b, innerDirectory: "")]; c.remove = ["a.txt"]
        #expect(try #require(t.archiveFS).apply(c).failures.isEmpty)
        t.refreshArchive()
        #expect(t.insideArchive && t.entries.map(\.name) == ["..", "b.txt"] && t.error == nil)
    }
}
