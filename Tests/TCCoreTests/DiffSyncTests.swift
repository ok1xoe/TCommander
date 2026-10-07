import Testing
import Foundation
@testable import TCCore

@Suite struct LineDiffTests {
    /// Přehraje operace a ověří, že z `a` vznikne `b`.
    func replay(_ a: [String], _ b: [String], _ ops: [DiffOp]) -> [String] {
        ops.compactMap { op in
            switch op { case .equal(let x, _): return a[x]; case .insert(let y): return b[y]; case .delete: return nil }
        }
    }

    @Test func basicCases() throws {
        let a = ["a", "b", "c", "d"], b = ["a", "x", "c", "d", "e"]
        let ops = try #require(LineDiff.diff(a, b))
        #expect(replay(a, b, ops) == b)
        #expect(ops.filter { if case .equal = $0 { return false }; return true }.count == 3)   // -b +x +e
        #expect(try #require(LineDiff.diff(a, a)).allSatisfy { if case .equal = $0 { return true }; return false })
        #expect(LineDiff.diff([], ["x"]) == [.insert(b: 0)])
        #expect(LineDiff.diff(["x"], []) == [.delete(a: 0)])
        #expect(LineDiff.diff([], []) == [])
    }

    @Test func randomizedRoundTrip() throws {
        var seed: UInt64 = 42
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) % n }
        for _ in 0..<200 {
            let a = (0..<rnd(30)).map { _ in String(rnd(5)) }, b = (0..<rnd(30)).map { _ in String(rnd(5)) }
            let ops = try #require(LineDiff.diff(a, b))
            #expect(replay(a, b, ops) == b)
            let dels = ops.filter { if case .delete = $0 { return true }; return false }.count
            #expect(ops.filter { if case .equal = $0 { return true }; return false }.count == a.count - dels)
        }
    }

    @Test func givesUpOnHugeDifferences() {
        let a = (0..<300).map { "a\($0)" }, b = (0..<300).map { "b\($0)" }
        #expect(LineDiff.diff(a, b, maxEdits: 50) == nil)
        #expect(LineDiff.diff(a, b) != nil)
    }

    @Test func sideBySidePairsChanges() throws {
        let a = ["a", "b", "c"], b = ["a", "B", "c", "d"]
        let rows = LineDiff.sideBySide(a, b, try #require(LineDiff.diff(a, b)))
        #expect(rows == [.init(left: "a", right: "a", kind: .same), .init(left: "b", right: "B", kind: .changed),
                         .init(left: "c", right: "c", kind: .same), .init(left: nil, right: "d", kind: .onlyRight)])
    }
}

@Suite struct DirectorySyncTests {
    func setup() throws -> (root: URL, l: URL, r: URL) {
        let d = try makeTempDir()
        let old = Date(timeIntervalSince1970: 1_000_000), new = Date(timeIntervalSince1970: 2_000_000)
        try write(d, "L/same.txt", "s", mtime: old); try write(d, "R/same.txt", "s", mtime: old)
        try write(d, "L/onlyleft.txt", "l", mtime: old); try write(d, "R/onlyright.txt", "r", mtime: old)
        try write(d, "L/newer.txt", "new!", mtime: new); try write(d, "R/newer.txt", "old", mtime: old)
        try write(d, "L/sub/deep.txt", "d", mtime: old); try write(d, "R/sub/deep.txt", "D!", mtime: new)
        try write(d, "L/samecontent.txt", "abc", mtime: new); try write(d, "R/samecontent.txt", "abc", mtime: old)
        return (d, d.appendingPathComponent("L"), d.appendingPathComponent("R"))
    }

    func states(_ items: [SyncItem]) -> [String: SyncItem.State] { Dictionary(uniqueKeysWithValues: items.map { ($0.relativePath, $0.state) }) }

    @Test func classifiesFiles() throws {
        let (d, l, r) = try setup(); defer { try? FileManager.default.removeItem(at: d) }
        let s = states(DirectoryComparer.compare(left: l, right: r))
        #expect(s["same.txt"] == .same && s["onlyleft.txt"] == .onlyLeft && s["onlyright.txt"] == .onlyRight)
        #expect(s["newer.txt"] == .leftNewer && s["sub/deep.txt"] == .rightNewer && s["samecontent.txt"] == .leftNewer)
        var o = SyncOptions(); o.compareContent = true
        #expect(states(DirectoryComparer.compare(left: l, right: r, options: o))["samecontent.txt"] == .same)
        o = SyncOptions(); o.recursive = false
        #expect(states(DirectoryComparer.compare(left: l, right: r, options: o))["sub/deep.txt"] == nil)
        o = SyncOptions(); o.ignoreMasks = "*.txt"
        #expect(DirectoryComparer.compare(left: l, right: r, options: o).isEmpty)
    }

    @Test func planDirections() throws {
        let (d, l, r) = try setup(); defer { try? FileManager.default.removeItem(at: d) }
        let items = DirectoryComparer.compare(left: l, right: r)
        func acts(_ dir: SyncDirection) -> [String: SyncAction] { Dictionary(uniqueKeysWithValues: SyncPlanner.plan(items, direction: dir).map { ($0.item.relativePath, $0.action) }) }
        let both = acts(.bothNewer)
        #expect(both["onlyleft.txt"] == .copyToRight && both["onlyright.txt"] == .copyToLeft && both["newer.txt"] == .copyToRight
                && both["sub/deep.txt"] == .copyToLeft && both["same.txt"] == SyncAction.none)
        let mirror = acts(.mirrorLeftToRight)
        #expect(mirror["onlyright.txt"] == .deleteRight && mirror["sub/deep.txt"] == SyncAction.none)
        #expect(acts(.leftToRight)["onlyright.txt"] == SyncAction.none)
    }

    @Test func executeMakesDirectoriesEqual() throws {
        let (d, l, r) = try setup(); defer { try? FileManager.default.removeItem(at: d) }
        try write(d, "L/newdir/inside/file.txt", "n", mtime: Date(timeIntervalSince1970: 1_500_000))
        let plan = SyncPlanner.plan(DirectoryComparer.compare(left: l, right: r), direction: .bothNewer)
        let rep = SyncPlanner.execute(plan, left: l, right: r)
        #expect(rep.failures.isEmpty && rep.succeeded >= 5)
        var o = SyncOptions(); o.compareContent = true
        #expect(DirectoryComparer.compare(left: l, right: r, options: o).allSatisfy { $0.state == .same || $0.relativePath == "samecontent.txt" })
        #expect(FileManager.default.fileExists(atPath: r.appendingPathComponent("newdir/inside/file.txt").path))
        #expect(try String(contentsOf: l.appendingPathComponent("sub/deep.txt"), encoding: .utf8) == "D!")
    }

    @Test func mirrorDeletesExtras() throws {
        let (d, l, r) = try setup(); defer { try? FileManager.default.removeItem(at: d) }
        let plan = SyncPlanner.plan(DirectoryComparer.compare(left: l, right: r), direction: .mirrorLeftToRight)
        let rep = SyncPlanner.execute(plan, left: l, right: r, toTrash: false)
        #expect(rep.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: r.appendingPathComponent("onlyright.txt").path))
        #expect(FileManager.default.fileExists(atPath: r.appendingPathComponent("onlyleft.txt").path))
    }
}
