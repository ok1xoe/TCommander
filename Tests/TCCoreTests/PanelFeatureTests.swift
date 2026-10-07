import Testing
import Foundation
@testable import TCCore

@MainActor @Suite struct PanelFeatureTests {
    func tree() throws -> URL {
        let d = try makeTempDir()
        try write(d, "a.txt"); try write(d, "b.TXT"); try write(d, "c.log"); try write(d, "sub/d.txt"); try write(d, "sub/deep/e.md")
        return d
    }

    @Test func markSameExtensionIgnoresCase() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        t.moveCursor(to: t.entries.firstIndex { $0.name == "a.txt" }!)
        t.markSameExtension()
        #expect(Set(t.targets.map(\.name)) == ["a.txt", "b.TXT"])
    }

    @Test func saveAndRestoreSelection() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        t.mark(matching: "*.txt", on: true); t.saveSelection()
        t.unmarkAll(); #expect(t.marked.isEmpty)
        t.restoreSelection(); #expect(t.marked.count == 2)
    }

    @Test func branchViewFlattensAndLeaves() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        t.enterBranchView()
        #expect(t.isBranch)
        #expect(Set(t.entries.filter { !$0.isParentLink }.map(\.name)) == ["a.txt", "b.TXT", "c.log", "sub/d.txt", "sub/deep/e.md"])
        t.exitBranchView()
        #expect(!t.isBranch && t.entries.contains { $0.name == "sub" })
    }

    @Test func recentDirectoriesAreMostRecentFirstAndUnique() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        t.navigate(to: d.appendingPathComponent("sub")); t.navigate(to: d); t.navigate(to: d.appendingPathComponent("sub/deep"))
        #expect(t.recent.map(\.lastPathComponent) == ["deep", d.lastPathComponent, "sub"])
    }

    @Test func autoRefreshPicksUpNewFiles() async throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let t = PanelTab(path: d)
        try write(d, "fresh.txt")
        for _ in 0..<40 {
            if t.entries.contains(where: { $0.name == "fresh.txt" }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(t.entries.contains { $0.name == "fresh.txt" })
    }

    @Test func hotlistPersistsAndDeduplicates() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let file = d.appendingPathComponent("h.json")
        let h = Hotlist(file: file)
        h.add(d); h.add(d); h.add(URL(fileURLWithPath: "/tmp"), name: "Temp")
        #expect(h.entries.count == 2 && h.contains(d))
        let again = Hotlist(file: file)
        #expect(again.entries.map(\.name) == [d.lastPathComponent, "Temp"])
        again.move(from: 1, to: 0); #expect(again.entries.first?.name == "Temp")
        again.remove(again.entries[0]); #expect(again.entries.count == 1)
    }
}
