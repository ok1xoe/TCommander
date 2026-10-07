import Testing
import Foundation
@testable import TCCore

@Suite struct FileSystemTests {
    @Test func listsAndStats() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        try write(d, "a.txt", "hello"); try write(d, ".hidden"); try write(d, "sub/b.txt")
        let fs = LocalFileSystem()
        #expect(try fs.list(d, includeHidden: false).map(\.name).sorted() == ["a.txt", "sub"])
        #expect(try fs.list(d, includeHidden: true).count == 3)
        let e = try fs.stat(d.appendingPathComponent("a.txt"))
        #expect(e.size == 5 && !e.isDirectory && e.ext == "txt" && e.baseName == "a")
        #expect(try fs.stat(d.appendingPathComponent("sub")).isDirectory)
        #expect(throws: Error.self) { try fs.stat(d.appendingPathComponent("nope")) }
    }

    @Test func directorySize() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        try write(d, "a", "12345"); try write(d, "s/b", "123")
        #expect(DirectorySize.compute(d) == 8)
    }

    @Test func permissionString() {
        let e = FileEntry(url: URL(fileURLWithPath: "/x"), name: "x", isDirectory: false, permissions: 0o754)
        #expect(e.permissionString == "rwxr-xr--")
    }
}

@Suite struct SortingAndGlobTests {
    func entry(_ n: String, dir: Bool = false, size: Int64 = 0) -> FileEntry {
        FileEntry(url: URL(fileURLWithPath: "/t/\(n)"), name: n, isDirectory: dir, size: size)
    }

    @Test func directoriesFirstNaturalOrder() {
        let s = sortEntries([entry("file10.txt"), entry("file2.txt"), entry("zdir", dir: true), entry("adir", dir: true)], by: SortDescriptor())
        #expect(s.map(\.name) == ["adir", "zdir", "file2.txt", "file10.txt"])
    }

    @Test func sortBySizeDescending() {
        let s = sortEntries([entry("a", size: 1), entry("b", size: 9), entry("d", dir: true)], by: SortDescriptor(key: .size, ascending: false))
        #expect(s.map(\.name) == ["d", "b", "a"])
    }

    @Test func sortByExtension() {
        let s = sortEntries([entry("b.txt"), entry("a.zip"), entry("c.doc")], by: SortDescriptor(key: .ext))
        #expect(s.map(\.name) == ["c.doc", "b.txt", "a.zip"])
    }

    @Test func globMasks() {
        #expect(GlobMatcher.matches("Report.TXT", masks: "*.txt"))
        #expect(GlobMatcher.matches("a.doc", masks: "*.txt;*.doc"))
        #expect(GlobMatcher.matches("noext", masks: "*.*"))
        #expect(GlobMatcher.matches("ab.c", masks: "a?.c"))
        #expect(!GlobMatcher.matches("a.png", masks: "*.txt *.doc"))
    }
}

@Suite struct OperationsTests {
    let ops = FileOperations()

    @Test func copyAndMoveWithConflicts() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "src/a.txt", "new"); try write(d, "dst/a.txt", "old")
        let dst = d.appendingPathComponent("dst")
        let items = ops.plan(sources: [a], into: dst)
        #expect(ops.conflicts(items).count == 1)

        var r = ops.perform(.copy, items, policy: .skip)
        #expect(r.skipped == 1 && r.succeeded == 0)
        #expect(try String(contentsOf: dst.appendingPathComponent("a.txt"), encoding: .utf8) == "old")

        r = ops.perform(.copy, items, policy: .keepBoth)
        #expect(r.succeeded == 1 && FileManager.default.fileExists(atPath: dst.appendingPathComponent("a copy.txt").path))

        r = ops.perform(.copy, items, policy: .overwrite)
        #expect(try String(contentsOf: dst.appendingPathComponent("a.txt"), encoding: .utf8) == "new")

        r = ops.perform(.move, items, policy: .overwrite)
        #expect(r.succeeded == 1 && !FileManager.default.fileExists(atPath: a.path))
    }

    @Test func overwriteOlderKeepsNewerTarget() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "s/a", "src", mtime: Date(timeIntervalSince1970: 1_000))
        try write(d, "t/a", "dst", mtime: Date(timeIntervalSince1970: 2_000))
        let r = ops.perform(.copy, ops.plan(sources: [a], into: d.appendingPathComponent("t")), policy: .overwriteOlder)
        #expect(r.skipped == 1)
        #expect(try String(contentsOf: d.appendingPathComponent("t/a"), encoding: .utf8) == "dst")
    }

    @Test func mergesDirectories() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let src = try write(d, "s/folder/new.txt").deletingLastPathComponent()
        try write(d, "t/folder/keep.txt")
        let r = ops.perform(.move, ops.plan(sources: [src], into: d.appendingPathComponent("t")), policy: .overwrite)
        #expect(r.failures.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: d.appendingPathComponent("t/folder").path).sorted()
        #expect(names == ["keep.txt", "new.txt"])
        #expect(!FileManager.default.fileExists(atPath: src.path))
    }

    @Test func refusesCopyIntoItself() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let dir = try write(d, "f/x").deletingLastPathComponent()
        let inner = dir.appendingPathComponent("inner"); try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let r = ops.perform(.copy, ops.plan(sources: [dir], into: inner), policy: .overwrite)
        #expect(r.failures.count == 1 && r.succeeded == 0)
    }

    @Test func sameFileOverwriteNeverDestroysSource() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "a.txt", "keep")
        let r = ops.perform(.copy, ops.plan(sources: [a], into: d), policy: .overwrite)
        #expect(r.failures.count == 1)
        #expect(try String(contentsOf: a, encoding: .utf8) == "keep")
    }

    @Test func renameMkdirDelete() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "a.txt")
        let b = try ops.rename(a, to: "b.txt")
        #expect(b.lastPathComponent == "b.txt" && !FileManager.default.fileExists(atPath: a.path))
        try write(d, "c.txt")
        #expect(throws: Error.self) { try ops.rename(b, to: "c.txt") }
        #expect(throws: Error.self) { try ops.rename(b, to: "x/y") }
        let top = try ops.makeDirectory("p/q/r", in: d)
        #expect(top.lastPathComponent == "p" && FileManager.default.fileExists(atPath: d.appendingPathComponent("p/q/r").path))
        let rep = ops.delete([b, top], toTrash: false)
        #expect(rep.succeeded == 2 && rep.failures.isEmpty)
    }

    @Test func shellRuns() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let r = Shell.run("pwd; echo err 1>&2; exit 3", in: d)
        #expect(r.status == 3 && r.output.contains(d.lastPathComponent) && r.output.contains("err"))
    }
}

@MainActor @Suite struct PanelTests {
    func tree() throws -> URL {
        let d = try makeTempDir()
        try write(d, "b.txt", "bb"); try write(d, "a.log", "a"); try write(d, "c.txt", "c")
        try write(d, "dir/in.txt"); try write(d, ".dot")
        return d
    }

    @Test func listsWithParentFirstAndHidesDotfiles() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        #expect(t.entries.map(\.name) == ["..", "dir", "a.log", "b.txt", "c.txt"])
        t.showHidden = true
        #expect(t.entries.map(\.name).contains(".dot"))
    }

    @Test func navigationHistoryAndGoUpSelectsOrigin() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        t.moveCursor(to: 1)
        #expect(t.activateCursor() == nil && t.path.lastPathComponent == "dir")
        t.goUp()
        #expect(t.path == d.standardizedFileURL && t.cursorEntry?.name == "dir")
        t.goBack(); #expect(t.path.lastPathComponent == "dir")
        t.goForward(); #expect(t.path == d.standardizedFileURL)
        #expect(!t.navigate(to: d.appendingPathComponent("missing")) && t.error != nil && t.path == d.standardizedFileURL)
    }

    @Test func activateFileReturnsURL() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        t.moveCursor(to: 3)
        #expect(t.activateCursor()?.lastPathComponent == "b.txt")
    }

    @Test func markingAndTargets() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        #expect(t.targets.isEmpty)                      // kurzor na ".."
        t.moveCursor(to: 3)
        #expect(t.targets.map(\.name) == ["b.txt"])
        t.toggleMarkAndAdvance()
        #expect(t.cursorEntry?.name == "c.txt" && t.targets.map(\.name) == ["b.txt"])
        t.mark(matching: "*.txt", on: true)
        #expect(t.targets.map(\.name) == ["b.txt", "c.txt"])
        t.mark(matching: "c*", on: false)
        #expect(t.summary.markedCount == 1 && t.summary.markedBytes == 2)
        t.invertMarks(); #expect(t.summary.markedCount == 3)   // dir, a.log, c.txt
        t.unmarkAll(); #expect(t.marked.isEmpty)
        t.markAll(); #expect(t.marked.count == 4)
    }

    @Test func sortAndQuickFilter() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        t.sort = SortDescriptor(key: .name, ascending: false)
        #expect(t.entries.map(\.name) == ["..", "dir", "c.txt", "b.txt", "a.log"])
        t.quickFilter = "TXT"
        #expect(t.entries.map(\.name) == ["..", "c.txt", "b.txt"])
    }

    @Test func reloadKeepsCursorAndSurvivesDeletedDirectory() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        t.moveCursor(to: 4)
        try write(d, "aa.txt")
        t.reload()
        #expect(t.cursorEntry?.name == "c.txt")
        t.navigate(to: d.appendingPathComponent("dir"))
        try FileManager.default.removeItem(at: d.appendingPathComponent("dir"))
        t.reload()
        #expect(t.path == d.standardizedFileURL && t.error == nil)
    }

    @Test func tabsKeepAtLeastOne() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let g = PanelGroup(paths: [d])
        g.newTab(); #expect(g.tabs.count == 2 && g.activeIndex == 1)
        g.nextTab(); #expect(g.activeIndex == 0)
        g.previousTab(); #expect(g.activeIndex == 1)
        g.closeActiveTab(); g.closeActiveTab()
        #expect(g.tabs.count == 1)
    }
}

@Suite struct TransferEngineTests {
    let ops = FileOperations()

    @Test func progressAndVerifyAcrossTree() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        try write(d, "s/tree/a.bin", String(repeating: "a", count: 3_000_000))
        try write(d, "s/tree/sub/b.txt", "bbb")
        try FileManager.default.createSymbolicLink(atPath: d.appendingPathComponent("s/tree/link").path, withDestinationPath: "a.bin")
        try FileManager.default.createDirectory(at: d.appendingPathComponent("t"), withIntermediateDirectories: true)
        final class Box: @unchecked Sendable { var last = TransferProgress(); var calls = 0 }
        let box = Box()
        let items = ops.plan(sources: [d.appendingPathComponent("s/tree")], into: d.appendingPathComponent("t"))
        let r = ops.perform(.copy, items, policy: .overwrite, verify: true, progress: { box.last = $0; box.calls += 1 })
        #expect(r.failures.isEmpty && r.succeeded == 1)
        #expect(box.last.bytesDone == box.last.bytesTotal && box.last.filesDone == box.last.filesTotal && box.calls > 1)
        let out = d.appendingPathComponent("t/tree")
        #expect(try String(contentsOf: out.appendingPathComponent("sub/b.txt"), encoding: .utf8) == "bbb")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: out.appendingPathComponent("link").path) == "a.bin")
        #expect(Checksum.hash(out.appendingPathComponent("a.bin"), .md5) == Checksum.hash(d.appendingPathComponent("s/tree/a.bin"), .md5))
    }

    @Test func cancelStopsAndLeavesNoPartialFile() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "a.bin", "x"), b = try write(d, "b.bin", "y")
        let c = OperationControl(); c.cancel()
        let t = d.appendingPathComponent("t"); try FileManager.default.createDirectory(at: t, withIntermediateDirectories: true)
        let r = ops.perform(.copy, ops.plan(sources: [a, b], into: t), policy: .overwrite, control: c)
        #expect(r.cancelled && r.succeeded == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: t.path).isEmpty)
    }

    @Test func pauseBlocksUntilResume() async throws {
        let c = OperationControl(); c.pause()
        final class Flag: @unchecked Sendable { var passed = false }
        let f = Flag()
        let t = Task.detached { _ = c.checkpoint(); f.passed = true }
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(!f.passed)
        c.resume(); await t.value
        #expect(f.passed)
    }

    @Test func moveWithinVolumeIsRenameAndReportsProgress() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "s/a.txt", "12345")
        let t = d.appendingPathComponent("t"); try FileManager.default.createDirectory(at: t, withIntermediateDirectories: true)
        final class Box: @unchecked Sendable { var last = TransferProgress() }
        let box = Box()
        let r = ops.perform(.move, ops.plan(sources: [a], into: t), policy: .overwrite, progress: { box.last = $0 })
        #expect(r.succeeded == 1 && !FileManager.default.fileExists(atPath: a.path))
        #expect(box.last.bytesDone == 5 && box.last.filesDone == 1)
    }

    @Test func deleteReportsProgressAndCancels() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "a"), b = try write(d, "b")
        let c = OperationControl(); c.cancel()
        #expect(ops.delete([a, b], toTrash: false, control: c).cancelled)
        #expect(FileManager.default.fileExists(atPath: a.path))
        #expect(ops.delete([a, b], toTrash: false).succeeded == 2)
    }
}
