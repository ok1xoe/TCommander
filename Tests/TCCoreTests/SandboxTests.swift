import Testing
import Foundation
@testable import TCCore

/// Příznak sandboxu se přepisuje jen uvnitř daného testu (task-local), proto může sada běžet souběžně s ostatními.
@Suite struct SandboxTests {
    func withSandbox<T>(_ on: Bool, _ body: () throws -> T) rethrows -> T {
        try Sandbox.$override.withValue(on) { try body() }
    }

    @Test func recognizesPermissionErrors() {
        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        let eperm = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        let cocoa = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError, userInfo: [NSUnderlyingErrorKey: eperm])
        for e in [posix, eperm, cocoa, wrapped] { #expect(Sandbox.isPermissionDenied(e)) }
        #expect(!Sandbox.isPermissionDenied(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)))
        #expect(!Sandbox.isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))))
    }

    @Test func realHomeIsNotTheContainer() {
        #expect(Sandbox.home.path.hasPrefix("/Users/") || Sandbox.home.path.hasPrefix("/var/root") || Sandbox.home.path == NSHomeDirectory())
        #expect(!Sandbox.home.path.contains("/Library/Containers/"))
    }

    @Test func accessManagerRemembersAndRestoresFolders() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = d.appendingPathComponent("a"), b = d.appendingPathComponent("b"), sub = a.appendingPathComponent("sub")
        for u in [a, b, sub] { try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true) }
        let storeDir = d.appendingPathComponent("store")
        let m = AccessManager(store: JSONStore<[Data]>(name: "access", directory: storeDir))
        #expect(!m.covers(a))
        #expect(m.grant(sub) && m.covers(sub) && m.covers(sub.appendingPathComponent("x/y.txt")) && !m.covers(a) && !m.covers(b))
        #expect(m.grant(a) && m.covers(a) && m.covers(sub) && m.covers(a.appendingPathComponent("zzz")) && !m.covers(b))
        #expect(m.roots.map(\.path) == [a.resolvingSymlinksInPath().path], "povolení nadřazené složky nahradí podsložku")
        #expect(!m.covers(URL(fileURLWithPath: a.path + "-sibling")), "stejný prefix není podsložka")
        let again = AccessManager(store: JSONStore<[Data]>(name: "access", directory: storeDir))
        again.restore()
        #expect(again.covers(sub) && !again.covers(b))
        again.revoke(a)
        #expect(!again.covers(a))
        let third = AccessManager(store: JSONStore<[Data]>(name: "access", directory: storeDir)); third.restore()
        #expect(third.roots.isEmpty)
    }

    @Test func rootGrantCoversEverything() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let m = AccessManager(store: JSONStore<[Data]>(name: "access", directory: d))
        #expect(m.grant(URL(fileURLWithPath: "/")) && m.covers(URL(fileURLWithPath: "/Users/someone/file")) && m.covers(URL(fileURLWithPath: "/")))
    }

    @Test func sandboxEditionHidesFeaturesThatCannotWork() throws {
        #expect(SavedConnection.Kind.available == SavedConnection.Kind.allCases)
        withSandbox(true) {
            let kinds = SavedConnection.Kind.available
            #expect(!kinds.contains(.sftp) && !kinds.contains(.plugin) && kinds.contains(.ftp) && kinds.contains(.smb) && kinds.contains(.webdavs))
            #expect(PlantUML.locate(configured: "/bin/echo") == nil)
        }
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.copyItem(at: ExamplePlugins.sourceRoot.appendingPathComponent("csvview"), to: d.appendingPathComponent("csvview"))
        let h = PluginHost(directory: d)
        #expect(h.reload().count == 1)
        withSandbox(true) { #expect(h.reload().isEmpty && h.valid.isEmpty && h.viewerPlugin(for: "a.csv") == nil) }
        h.allowInSandbox = true
        withSandbox(true) { #expect(h.reload().count == 1) }
    }

    @MainActor @Test func panelAsksForAccessWhenAFolderIsDenied() throws {
        let d = try makeTempDir()
        let locked = d.appendingPathComponent("locked"); try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try "x".write(to: locked.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path); try? FileManager.default.removeItem(at: d) }
        let tab = PanelTab(path: d)
        var asked: [URL] = []
        withSandbox(true) {
            PanelTab.accessRequest = { url in asked.append(url); return false }                // uživatel odmítne
            defer { PanelTab.accessRequest = nil }
            #expect(!tab.navigate(to: locked) && tab.error != nil && asked.map(\.lastPathComponent) == ["locked"])
            PanelTab.accessRequest = { url in asked.append(url); try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path); return true }   // povolí
            #expect(tab.navigate(to: locked) && tab.error == nil && tab.entries.contains { $0.name == "f.txt" } && asked.count == 2)
        }
        // mimo sandbox se na nic neptá
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        asked = []
        PanelTab.accessRequest = { url in asked.append(url); return true }
        defer { PanelTab.accessRequest = nil }
        #expect(!tab.navigate(to: locked) && asked.isEmpty)
    }
}
