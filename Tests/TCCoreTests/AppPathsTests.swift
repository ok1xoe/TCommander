import Testing
import Foundation
@testable import TCCore

@Suite struct AppPathsTests {
    func tempBase() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("tcommander-paths-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    @Test func movesTheOldSettingsFolderOnce() throws {
        let base = try tempBase(); defer { try? FileManager.default.removeItem(at: base) }
        let old = base.appendingPathComponent("macTC")
        try FileManager.default.createDirectory(at: old.appendingPathComponent("PlugIns"), withIntermediateDirectories: true)
        try "{}".write(to: old.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        let new = AppPaths.migrate(base: base)
        #expect(new.lastPathComponent == "TCommander")
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("settings.json").path))
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("PlugIns").path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        _ = AppPaths.migrate(base: base)                                                  // opakované volání nic nerozbije
        #expect(FileManager.default.fileExists(atPath: new.appendingPathComponent("settings.json").path))
    }

    @Test func neverOverwritesAnExistingNewFolder() throws {
        let base = try tempBase(); defer { try? FileManager.default.removeItem(at: base) }
        let old = base.appendingPathComponent("macTC"), new = base.appendingPathComponent("TCommander")
        for d in [old, new] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        try "stará".write(to: old.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        try "nová".write(to: new.appendingPathComponent("settings.json"), atomically: true, encoding: .utf8)
        _ = AppPaths.migrate(base: base)
        #expect(try String(contentsOf: new.appendingPathComponent("settings.json"), encoding: .utf8) == "nová")
        #expect(FileManager.default.fileExists(atPath: old.appendingPathComponent("settings.json").path))
    }

    @Test func worksWithoutAnyOldFolderAndBuildsCachePaths() throws {
        let base = try tempBase(); defer { try? FileManager.default.removeItem(at: base) }
        #expect(AppPaths.migrate(base: base) == base.appendingPathComponent("TCommander"))
        #expect(AppPaths.caches("ssh").path.hasSuffix("Caches/TCommander/ssh"))
        #expect(AppPaths.plugins.lastPathComponent == "PlugIns")
    }
}
