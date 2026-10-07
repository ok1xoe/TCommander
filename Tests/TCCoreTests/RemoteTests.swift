import Testing
import Foundation
@testable import TCCore

@Suite struct FTPListParserTests {
    @Test func parsesUnixListing() {
        let now = ISO8601DateFormatter().date(from: "2026-10-07T12:00:00Z")!
        let text = """
        total 12
        drwxr-xr-x   2 ftp      ftp          4096 Oct  3 08:15 pub
        -rw-r--r--   1 ftp      ftp       1234567 Jan 15  2024 report final.pdf
        lrwxrwxrwx   1 ftp      ftp             7 Oct  1 10:00 latest -> pub/new
        -rwx------   1 user group 5 Dec 31 23:59 future.sh
        """
        let e = FTPListParser.parse(text, mlsd: false, now: now)
        #expect(e.map(\.name) == ["pub", "report final.pdf", "latest", "future.sh"])
        #expect(e[0].isDirectory && e[0].permissions == 0o755)
        #expect(e[1].size == 1_234_567 && !e[1].isDirectory)
        let y = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: e[1].modified!)
        #expect(y.year == 2024 && y.month == 1 && y.day == 15)
        #expect(e[2].isSymlink && e[2].name == "latest")
        #expect(e[3].permissions == 0o700)
        let fy = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: e[3].modified!)
        #expect(fy.year == 2025)     // prosinec bez roku v říjnu 2026 = loni
    }

    @Test func parsesDosAndMlsd() {
        let dos = FTPListParser.parse("""
        10-07-26  01:30PM       <DIR>          Documents
        01-02-2025  09:05AM            4096 My File.txt
        """, mlsd: false)
        #expect(dos.map(\.name) == ["Documents", "My File.txt"] && dos[0].isDirectory && dos[1].size == 4096)
        let h = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: dos[0].modified!)
        #expect(h.hour == 13 && h.year == 2026)

        let ml = FTPListParser.parse("""
        type=cdir;modify=20260101000000; .
        type=pdir;modify=20260101000000; ..
        type=dir;modify=20260102030405; folder one
        type=file;size=42;modify=20260102030405.123;unix.mode=0640; a b.txt
        type=OS.unix=symlink;size=3; ln
        """, mlsd: true)
        #expect(ml.map(\.name) == ["folder one", "a b.txt", "ln"])
        #expect(ml[0].isDirectory && ml[1].size == 42 && ml[1].permissions == 0o640 && ml[2].isSymlink)
    }

    @Test func ignoresGarbage() {
        #expect(FTPListParser.parse("total 0\n\nrandom text\n", mlsd: false).isEmpty)
    }
}

@Suite(.serialized) struct RemoteFileSystemTests {
    func server(noMLSD: Bool = false) throws -> (root: URL, srv: MockFTP, fs: RemoteFileSystem) {
        let d = try makeTempDir()
        let root = d.appendingPathComponent("server"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let srv = try MockFTP(root: root, noMLSD: noMLSD)
        return (d, srv, RemoteFileSystem(connection: srv.connection()))
    }

    @Test(arguments: [false, true]) func listsWithMLSDAndWithLISTFallback(_ noMLSD: Bool) throws {
        let (d, srv, fs) = try server(noMLSD: noMLSD); defer { srv.stop(); try? FileManager.default.removeItem(at: d) }
        try write(srv.root, "a.txt", "hello"); try write(srv.root, "dir/inner.bin", "12345678"); try write(srv.root, ".hidden", "x")
        let list = try fs.list(URL(fileURLWithPath: "/"), includeHidden: false)
        #expect(Set(list.map(\.name)) == ["a.txt", "dir"], "noMLSD=\(noMLSD)")
        #expect(list.first { $0.name == "a.txt" }?.size == 5 && list.first { $0.name == "dir" }?.isDirectory == true)
        #expect(try fs.list(URL(fileURLWithPath: "/"), includeHidden: true).count == 3)
        #expect(try fs.list(URL(fileURLWithPath: "/dir"), includeHidden: true).map(\.name) == ["inner.bin"])
        #expect(try fs.stat(URL(fileURLWithPath: "/dir/inner.bin")).size == 8)
        #expect(fs.exists(URL(fileURLWithPath: "/dir")) && !fs.exists(URL(fileURLWithPath: "/nope")))
        #expect(throws: Error.self) { try fs.list(URL(fileURLWithPath: "/nope"), includeHidden: true) }
        // datum se přenáší (UTC) – tolerance minuty kvůli formátu LIST bez sekund
        let m = try fs.stat(URL(fileURLWithPath: "/a.txt")).modified
        #expect(abs((m ?? .distantPast).timeIntervalSinceNow) < 120)
    }

    @Test func createsDeletesAndRenames() throws {
        let (d, srv, fs) = try server(); defer { srv.stop(); try? FileManager.default.removeItem(at: d) }
        try fs.createDirectory(URL(fileURLWithPath: "/x/y/z"))
        #expect(FileManager.default.fileExists(atPath: srv.root.appendingPathComponent("x/y/z").path))
        try fs.createFile(URL(fileURLWithPath: "/x/empty.txt"))
        #expect(try Data(contentsOf: srv.root.appendingPathComponent("x/empty.txt")).isEmpty)
        try fs.move(URL(fileURLWithPath: "/x/empty.txt"), to: URL(fileURLWithPath: "/x/y/renamed.txt"))
        #expect(FileManager.default.fileExists(atPath: srv.root.appendingPathComponent("x/y/renamed.txt").path))
        try fs.remove(URL(fileURLWithPath: "/x"))                                        // rekurzivně
        #expect(!FileManager.default.fileExists(atPath: srv.root.appendingPathComponent("x").path))
        #expect(throws: Error.self) { try fs.remove(URL(fileURLWithPath: "/missing")) }
        #expect(throws: Error.self) { try fs.copy(URL(fileURLWithPath: "/a"), to: URL(fileURLWithPath: "/b")) }
    }

    @Test func rejectsWrongPasswordAndDeadPort() throws {
        let (d, srv, _) = try server(); defer { srv.stop(); try? FileManager.default.removeItem(at: d) }
        let bad = RemoteFileSystem(connection: srv.connection(password: "wrong"))
        do { _ = try bad.list(URL(fileURLWithPath: "/"), includeHidden: true); Issue.record("měla selhat") }
        catch let e as RemoteError { #expect(e.code == 67, "kód \(e.code): \(e.message)") }
        let dead = RemoteFileSystem(connection: RemoteConnection(host: "127.0.0.1", port: 1, user: "x", password: "y"))
        #expect(throws: Error.self) { try dead.list(URL(fileURLWithPath: "/"), includeHidden: true) }
    }

    @Test func downloadsFilesAndFoldersWithProgress() throws {
        let (d, srv, fs) = try server(); defer { srv.stop(); try? FileManager.default.removeItem(at: d) }
        try write(srv.root, "top.txt", "TOP", mtime: Date(timeIntervalSince1970: 1_700_000_000))
        try write(srv.root, "tree/sub/big.bin", String(repeating: "z", count: 300_000))
        try write(srv.root, "tree/příliš žluťoučký.txt", "unicode")
        let out = d.appendingPathComponent("out"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        final class Box: @unchecked Sendable { var last = TransferProgress(); var calls = 0 }
        let box = Box()
        let r = RemoteTransfer.download(fs, ["/top.txt", "/tree"], to: out, progress: { box.last = $0; box.calls += 1 })
        #expect(r.failures.isEmpty && r.succeeded == 2, "\(r.failures.map(\.message))")
        #expect(try String(contentsOf: out.appendingPathComponent("top.txt"), encoding: .utf8) == "TOP")
        #expect(try Data(contentsOf: out.appendingPathComponent("tree/sub/big.bin")).count == 300_000)
        #expect(try String(contentsOf: out.appendingPathComponent("tree/příliš žluťoučký.txt"), encoding: .utf8) == "unicode")
        #expect(box.last.bytesDone == box.last.bytesTotal && box.last.bytesTotal == 3 + 300_000 + 7 && box.last.filesDone == 3)
        let m = try LocalFileSystem().stat(out.appendingPathComponent("top.txt")).modified
        #expect(abs((m ?? .distantPast).timeIntervalSince1970 - 1_700_000_000) < 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path).allSatisfy { !$0.hasSuffix(".macTCpart") })
    }

    @Test func downloadConflictPoliciesAndResume() throws {
        let (d, srv, fs) = try server(); defer { srv.stop(); try? FileManager.default.removeItem(at: d) }
        let content = String((0..<100_000).map { Character(UnicodeScalar(UInt8(97 + $0 % 26))) })
        try write(srv.root, "f.txt", content)
        let out = d.appendingPathComponent("out"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let mine = try write(out, "f.txt", "mine")
        #expect(RemoteTransfer.download(fs, ["/f.txt"], to: out, policy: .skip).skipped == 1)
        #expect(try String(contentsOf: mine, encoding: .utf8) == "mine")
        #expect(RemoteTransfer.download(fs, ["/f.txt"], to: out, policy: .keepBoth).succeeded == 1)
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("f copy.txt").path))
        // obnovení: část souboru už je stažena
        try FileManager.default.removeItem(at: mine)
        try String(content.prefix(40_000)).write(to: out.appendingPathComponent("f.txt.macTCpart"), atomically: true, encoding: .utf8)
        let r = RemoteTransfer.download(fs, ["/f.txt"], to: out, policy: .overwrite)
        let got = try String(contentsOf: mine, encoding: .utf8)
        #expect(r.failures.isEmpty && got == content)
    }

    @Test func cancelledDownloadKeepsPartialFileForResume() throws {
        let (d, srv, fs) = try server(); defer { srv.stop(); try? FileManager.default.removeItem(at: d) }
        try write(srv.root, "huge.bin", String(repeating: "q", count: 8_000_000))
        let out = d.appendingPathComponent("out"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let control = OperationControl()
        let r = RemoteTransfer.download(fs, ["/huge.bin"], to: out, control: control, progress: { if $0.bytesDone > 500_000 { control.cancel() } })
        #expect(r.cancelled && r.succeeded == 0)
        #expect(!FileManager.default.fileExists(atPath: out.appendingPathComponent("huge.bin").path))
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("huge.bin.macTCpart").path))
        let r2 = RemoteTransfer.download(fs, ["/huge.bin"], to: out)           // dokončení z rozpracovaného
        let size = try Data(contentsOf: out.appendingPathComponent("huge.bin")).count
        #expect(r2.failures.isEmpty && size == 8_000_000)
    }

    @Test func uploadsFilesFoldersAndHonorsPolicies() throws {
        let (d, srv, fs) = try server(); defer { srv.stop(); try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "local/a.txt", "AAA"), folder = try write(d, "local/dir/b.txt", "BBB").deletingLastPathComponent()
        try write(d, "local/dir/sub/c.txt", String(repeating: "c", count: 200_000))
        final class Box: @unchecked Sendable { var last = TransferProgress() }
        let box = Box()
        let r = RemoteTransfer.upload(fs, [a, folder], into: "/", progress: { box.last = $0 })
        #expect(r.failures.isEmpty && r.succeeded == 2, "\(r.failures.map(\.message))")
        #expect(try String(contentsOf: srv.root.appendingPathComponent("a.txt"), encoding: .utf8) == "AAA")
        #expect(try Data(contentsOf: srv.root.appendingPathComponent("dir/sub/c.txt")).count == 200_000)
        #expect(box.last.bytesDone == box.last.bytesTotal && box.last.bytesTotal == 3 + 3 + 200_000)
        try "NEW".write(to: a, atomically: true, encoding: .utf8)
        #expect(RemoteTransfer.upload(fs, [a], into: "/", policy: .skip).skipped == 1)
        #expect(try String(contentsOf: srv.root.appendingPathComponent("a.txt"), encoding: .utf8) == "AAA")
        #expect(RemoteTransfer.upload(fs, [a], into: "/", policy: .keepBoth).succeeded == 1)
        #expect(try String(contentsOf: srv.root.appendingPathComponent("a copy.txt"), encoding: .utf8) == "NEW")
        #expect(RemoteTransfer.upload(fs, [a], into: "/", policy: .overwrite).succeeded == 1)
        #expect(try String(contentsOf: srv.root.appendingPathComponent("a.txt"), encoding: .utf8) == "NEW")
        // do podadresáře
        #expect(RemoteTransfer.upload(fs, [a], into: "/dir/sub").failures.isEmpty)
        #expect(FileManager.default.fileExists(atPath: srv.root.appendingPathComponent("dir/sub/a.txt").path))
    }
}

@MainActor @Suite(.serialized) struct RemotePanelTests {
    func waitUntil(_ cond: () -> Bool) async throws {
        for _ in 0..<100 { if cond() { return }; try await Task.sleep(nanoseconds: 50_000_000) }
    }

    func setup() throws -> (d: URL, srv: MockFTP, fs: RemoteFileSystem, tab: PanelTab, local: URL) {
        let d = try makeTempDir()
        let root = d.appendingPathComponent("server"); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try write(root, "a.txt", "AAA"); try write(root, "dir/b.txt", "BB"); try write(root, "dir/sub/c.txt", "C")
        let local = d.appendingPathComponent("local"); try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        let srv = try MockFTP(root: root)
        let fs = RemoteFileSystem(connection: srv.connection())
        let tab = PanelTab(path: local)
        tab.attachRemote(fs, path: "/", items: try fs.list(URL(fileURLWithPath: "/"), includeHidden: false))
        return (d, srv, fs, tab, local)
    }

    @Test func attachNavigateAsyncAndLeave() async throws {
        let (d, srv, _, tab, local) = try setup(); defer { srv.stop(); try? FileManager.default.removeItem(at: d) }
        #expect(tab.remote != nil && tab.isVirtual && !tab.insideArchive)
        #expect(tab.entries.map(\.name) == ["..", "dir", "a.txt"])
        #expect(tab.displayPath == "ftp://tester@127.0.0.1:\(srv.port)/" && tab.persistentPath == local.standardizedFileURL)
        tab.moveCursor(to: 1)
        #expect(tab.activateCursor() == nil)                              // vstup do adresáře probíhá na pozadí
        try await waitUntil { tab.path.path == "/dir" && !tab.isLoading }
        #expect(tab.entries.map(\.name) == ["..", "sub", "b.txt"])
        tab.goUp()
        try await waitUntil { tab.path.path == "/" && tab.entries.count == 3 }
        #expect(tab.cursorEntry?.name == "dir")
        tab.moveCursor(to: 2)                                             // soubor na serveru se vrací k otevření
        #expect(tab.activateCursor()?.lastPathComponent == "a.txt")
        tab.moveCursor(to: 0); #expect(tab.activateCursor() == nil)       // ".." v kořeni = odpojení
        try await waitUntil { tab.remote == nil && tab.path == local.standardizedFileURL }
        #expect(!tab.isVirtual && tab.remote == nil && tab.entries.contains { $0.name == ".." })
    }

    @Test func failedLoadKeepsPanelAndShowsError() async throws {
        let (d, srv, _, tab, _) = try setup(); defer { srv.stop(); try? FileManager.default.removeItem(at: d) }
        tab.navigate(to: URL(fileURLWithPath: "/missing"))
        try await waitUntil { tab.error != nil }
        #expect(tab.error?.contains("/missing") == true && tab.path.path == "/" && tab.remote != nil)
    }

    @Test func reloadClimbsWhenDirectoryDisappears() async throws {
        let (d, srv, _, tab, _) = try setup(); defer { srv.stop(); try? FileManager.default.removeItem(at: d) }
        tab.navigate(to: URL(fileURLWithPath: "/dir/sub"))
        try await waitUntil { tab.path.path == "/dir/sub" }
        try FileManager.default.removeItem(at: srv.root.appendingPathComponent("dir/sub"))
        tab.reload()
        try await waitUntil { tab.path.path == "/dir" && tab.error == nil }
        #expect(tab.path.path == "/dir" && tab.entries.map(\.name) == ["..", "b.txt"])
    }

    @Test func remoteDirectorySizeAndNavigateLocal() async throws {
        let (d, srv, _, tab, local) = try setup(); defer { srv.stop(); try? FileManager.default.removeItem(at: d) }
        let dir = tab.entries.first { $0.name == "dir" }!
        tab.computeDirSize(dir)
        try await waitUntil { tab.dirSizes[dir.url] != nil }
        #expect(tab.dirSizes[dir.url] == 3)
        tab.navigateLocal(local)
        #expect(tab.remote == nil && tab.path == local.standardizedFileURL)
    }
}

@MainActor @Suite struct SavedConnectionsTests {
    @Test func persistsAndBuildsConnections() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let file = d.appendingPathComponent("c.json")
        let store = SavedConnections(file: file)
        let ftp = SavedConnection(name: "Server", kind: .ftpExplicitTLS, host: "ftp.example.com", port: 2121, user: "me", path: "/pub")
        store.upsert(ftp)
        store.upsert(SavedConnection(id: ftp.id, name: "Přejmenováno", kind: .ftpExplicitTLS, host: "ftp.example.com", user: "me"))
        store.upsert(SavedConnection(name: "Sdílená", kind: .smb, host: "nas.local", user: "tom", path: "/data"))
        #expect(store.items.count == 2 && store.items[0].name == "Přejmenováno")
        #expect(SavedConnections(file: file).items == store.items)
        let c = store.items[0].ftpConnection(password: "pw")
        #expect(c.security == .explicitTLS && c.user == "me" && c.password == "pw" && c.host == "ftp.example.com")
        #expect(SavedConnection(name: "a", kind: .ftp, host: "h").ftpConnection(password: "x").user == "anonymous")
        #expect(store.items[1].mountURL()?.absoluteString == "smb://tom@nas.local/data")
        #expect(SavedConnection(name: "w", kind: .webdavs, host: "dav.example.com", port: 8443, path: "/remote.php/dav").mountURL()?.absoluteString == "https://dav.example.com:8443/remote.php/dav")
        #expect(SavedConnection(name: "w", kind: .ftp, host: "h").mountURL() == nil)
        store.remove(store.items[0]); #expect(SavedConnections(file: file).items.count == 1)
    }
}

@Suite struct SFTPListParsingTests {
    @Test func parsesOpenSSHLongListingWithQuestionMarkLinkCountAndFullPaths() {
        let text = """
        sftp> ls -la /srv/data
        drwxr-xr-x    ? hyman    wheel          96 Oct  7 13:23 /srv/data/.
        drwxr-xr-x    ? hyman    wheel         384 Oct  7 13:23 /srv/data/..
        -rw-r--r--    ? hyman    wheel           6 Oct  7 13:23 /srv/data/a b.txt
        drwx------    ? root     admin         128 Jan  5  2024 /srv/data/sub dir
        lrwxr-xr-x    ? hyman    wheel           5 Oct  7 13:23 /srv/data/ln -> /etc/hosts
        """
        let e = FTPListParser.parse(text.split(separator: "\n").filter { !$0.hasPrefix("sftp>") }.joined(separator: "\n"), mlsd: false)
        #expect(e.map(\.name) == ["a b.txt", "sub dir", "ln"])
        #expect(e[0].size == 6 && !e[0].isDirectory && e[1].isDirectory && e[1].permissions == 0o700 && e[2].isSymlink)
    }

    @Test func honorsTimeZone() {
        let tz = TimeZone(identifier: "Asia/Tokyo")!
        let d = FTPListParser.unixDate(month: "Jan", day: "15", yearOrTime: "2024", now: Date(), timeZone: tz)!
        #expect(d.timeIntervalSince1970 == 1_705_244_400)      // 2024-01-15 00:00 v Tokiu = 2024-01-14 15:00 UTC
    }
}
