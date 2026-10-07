import Testing
import Foundation
@testable import TCCore

@Suite(.serialized, .enabled(if: MockSSHD.available, "sshd nelze na tomto stroji spustit")) struct SFTPTests {
    func setup(multiplex: Bool = false) throws -> (d: URL, srv: MockSSHD, fs: SFTPFileSystem, root: URL) {
        let d = try makeTempDir()
        let root = d.appendingPathComponent("server"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let srv = try MockSSHD()
        return (d, srv, SFTPFileSystem(connection: srv.connection(multiplex: multiplex)), root)
    }
    func end(_ t: (d: URL, srv: MockSSHD, fs: SFTPFileSystem, root: URL)) { t.fs.close(); t.srv.stop(); try? FileManager.default.removeItem(at: t.d) }
    func u(_ root: URL, _ p: String = "") -> URL { p.isEmpty ? root : root.appendingPathComponent(p) }

    @Test func listsStatsAndFindsHomeDirectory() throws {
        let t = try setup(); defer { end(t) }
        try write(t.root, "a b.txt", "hello"); try write(t.root, "dir/inner.bin", "12345678"); try write(t.root, ".hidden", "x")
        let list = try t.fs.list(t.root, includeHidden: false)
        #expect(Set(list.map(\.name)) == ["a b.txt", "dir"])
        #expect(list.first { $0.name == "a b.txt" }?.size == 5 && list.first { $0.name == "dir" }?.isDirectory == true)
        #expect(try t.fs.list(t.root, includeHidden: true).count == 3)
        #expect(try t.fs.stat(u(t.root, "dir/inner.bin")).size == 8)
        #expect(t.fs.exists(u(t.root, "dir")) && !t.fs.exists(u(t.root, "nope")))
        #expect(throws: Error.self) { try t.fs.list(u(t.root, "nope"), includeHidden: true) }
        #expect(try t.fs.homeDirectory() == NSHomeDirectory())
        let m = try t.fs.stat(u(t.root, "a b.txt")).modified
        #expect(abs((m ?? .distantPast).timeIntervalSinceNow) < 120)         // časové pásmo se zpracuje správně
    }

    @Test func createsRenamesAndDeletes() throws {
        let t = try setup(); defer { end(t) }
        try t.fs.createDirectory(u(t.root, "x/y/z"))
        #expect(FileManager.default.fileExists(atPath: u(t.root, "x/y/z").path))
        try t.fs.createFile(u(t.root, "x/empty.txt"))
        try t.fs.move(u(t.root, "x/empty.txt"), to: u(t.root, "x/y/přejmenováno \"q\".txt"))
        #expect(FileManager.default.fileExists(atPath: u(t.root, "x/y/přejmenováno \"q\".txt").path))
        try t.fs.remove(u(t.root, "x"))
        #expect(!FileManager.default.fileExists(atPath: u(t.root, "x").path))
        #expect(throws: Error.self) { try t.fs.remove(u(t.root, "missing")) }
    }

    @Test func downloadsTreeKeepingTimesAndSupportsResume() throws {
        let t = try setup(); defer { end(t) }
        try write(t.root, "top.txt", "TOP", mtime: Date(timeIntervalSince1970: 1_700_000_000))
        let content = String((0..<120_000).map { Character(UnicodeScalar(UInt8(97 + $0 % 26))) })
        try write(t.root, "tree/sub/big.txt", content); try write(t.root, "tree/příliš žluťoučký.txt", "unicode")
        let out = t.d.appendingPathComponent("out"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        final class Box: @unchecked Sendable { var last = TransferProgress() }
        let box = Box()
        let r = RemoteTransfer.download(t.fs, [u(t.root, "top.txt").path, u(t.root, "tree").path], to: out, progress: { box.last = $0 })
        #expect(r.failures.isEmpty && r.succeeded == 2, "\(r.failures.map(\.message))")
        #expect(try String(contentsOf: out.appendingPathComponent("tree/sub/big.txt"), encoding: .utf8) == content)
        #expect(try String(contentsOf: out.appendingPathComponent("tree/příliš žluťoučký.txt"), encoding: .utf8) == "unicode")
        let m = try LocalFileSystem().stat(out.appendingPathComponent("top.txt")).modified
        #expect(abs((m ?? .distantPast).timeIntervalSince1970 - 1_700_000_000) < 2)
        #expect(box.last.filesDone == 3 && box.last.bytesDone == box.last.bytesTotal)
        // obnovení rozpracovaného souboru (reget)
        try FileManager.default.removeItem(at: out.appendingPathComponent("tree/sub/big.txt"))
        let part = out.appendingPathComponent("tree/sub/big.txt.macTCpart")
        try String(content.prefix(50_000)).write(to: part, atomically: true, encoding: .utf8)
        let r2 = RemoteTransfer.download(t.fs, [u(t.root, "tree/sub/big.txt").path], to: out.appendingPathComponent("tree/sub"), policy: .overwrite)
        let got = try String(contentsOf: out.appendingPathComponent("tree/sub/big.txt"), encoding: .utf8)
        #expect(r2.failures.isEmpty && got == content)
    }

    @Test func uploadsTreeAndHonorsPolicies() throws {
        let t = try setup(multiplex: true); defer { end(t) }       // se sdíleným spojením (ControlMaster)
        let a = try write(t.d, "local/a.txt", "AAA"), folder = try write(t.d, "local/dir/b.txt", "BBB").deletingLastPathComponent()
        try write(t.d, "local/dir/sub/c.txt", String(repeating: "c", count: 300_000))
        let r = RemoteTransfer.upload(t.fs, [a, folder], into: t.root.path)
        #expect(r.failures.isEmpty && r.succeeded == 2, "\(r.failures.map(\.message))")
        #expect(try String(contentsOf: u(t.root, "a.txt"), encoding: .utf8) == "AAA")
        #expect(try Data(contentsOf: u(t.root, "dir/sub/c.txt")).count == 300_000)
        try "NEW".write(to: a, atomically: true, encoding: .utf8)
        #expect(RemoteTransfer.upload(t.fs, [a], into: t.root.path, policy: .skip).skipped == 1)
        #expect(try String(contentsOf: u(t.root, "a.txt"), encoding: .utf8) == "AAA")
        #expect(RemoteTransfer.upload(t.fs, [a], into: t.root.path, policy: .keepBoth).succeeded == 1)
        #expect(try String(contentsOf: u(t.root, "a copy.txt"), encoding: .utf8) == "NEW")
        #expect(RemoteTransfer.upload(t.fs, [a], into: t.root.path, policy: .overwrite).succeeded == 1)
        #expect(try String(contentsOf: u(t.root, "a.txt"), encoding: .utf8) == "NEW")
    }

    @Test func abortedUploadThrowsAbortCode() throws {
        let t = try setup(); defer { end(t) }
        let a = try write(t.d, "local/a.txt", "AAA")
        do { try t.fs.uploadFile(local: a, remotePath: u(t.root, "a.txt").path, progress: { _, _ in false }); Issue.record("měl skončit přerušením") }
        catch let e as RemoteError { #expect(e.code == RemoteAbort.code) }
        #expect(!FileManager.default.fileExists(atPath: u(t.root, "a.txt").path))
    }

    @Test func rejectsWrongKeyAndDeadPort() throws {
        let t = try setup(); defer { end(t) }
        _ = Shell.run("ssh-keygen -q -t ed25519 -N '' -f otherkey", in: t.srv.dir)
        let bad = SFTPFileSystem(connection: t.srv.connection(identity: t.srv.dir.appendingPathComponent("otherkey").path))
        do { _ = try bad.list(t.root, includeHidden: true); Issue.record("měla selhat") }
        catch let e as RemoteError { #expect(e.message.contains("Permission denied"), "\(e.message)") }
        var dead = t.srv.connection(); dead.port = 1
        #expect(throws: Error.self) { try SFTPFileSystem(connection: dead).list(t.root, includeHidden: true) }
    }
}

@MainActor @Suite(.serialized, .enabled(if: MockSSHD.available, "sshd nelze na tomto stroji spustit")) struct SFTPPanelTests {
    @Test func panelNavigatesSFTPServer() async throws {
        let d = try makeTempDir()
        let root = d.appendingPathComponent("server"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let srv = try MockSSHD()
        let fs = SFTPFileSystem(connection: srv.connection())
        defer { fs.close(); srv.stop(); try? FileManager.default.removeItem(at: d) }
        try write(root, "a.txt", "A"); try write(root, "dir/b.txt", "B")
        let tab = PanelTab(path: d)
        tab.attachRemote(fs, path: root.path, items: try fs.list(root, includeHidden: false))
        #expect(tab.remote != nil && tab.entries.map(\.name) == ["..", "dir", "a.txt"] && tab.displayPath.hasPrefix("sftp://"))
        tab.moveCursor(to: 1); #expect(tab.activateCursor() == nil)
        for _ in 0..<100 { if tab.path.lastPathComponent == "dir" && !tab.isLoading { break }; try await Task.sleep(nanoseconds: 100_000_000) }
        #expect(tab.entries.map(\.name) == ["..", "b.txt"])
        tab.leaveRemote()
        #expect(tab.remote == nil && tab.path == d.standardizedFileURL)
    }
}
