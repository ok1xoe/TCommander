import Testing
import Foundation
@testable import TCCore

@Suite struct MultiRenameTests {
    func urls(_ names: [String], in d: URL) throws -> [URL] { try names.map { try write(d, $0) } }
    func names(_ p: [RenamePreview]) -> [String] { p.map(\.newName) }

    @Test func defaultMaskKeepsNames() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let p = RenameEngine.preview(try urls(["a.txt", "b.tar.gz", "noext"], in: d), RenameOptions())
        #expect(names(p) == ["a.txt", "b.tar.gz", "noext"] && p.allSatisfy { !$0.changed && $0.problem == nil })
    }

    @Test func rangesAndCounter() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let f = try urls(["holiday.jpg", "party.jpg"], in: d)
        var o = RenameOptions(); o.nameMask = "[N1-3]_[C]"
        o.counterStart = 5; o.counterDigits = 3
        #expect(names(RenameEngine.preview(f, o)) == ["hol_005.jpg", "par_006.jpg"])
        o.nameMask = "[N2,2]-[C10+5:2]-[N4-]"
        #expect(names(RenameEngine.preview(f, o)) == ["ol-10-iday.jpg", "ar-15-ty.jpg"])
        o.nameMask = "x[N9]y[Q]"
        #expect(RenameEngine.preview(f, o)[0].newName == "xy[Q].jpg")     // neznámý token zůstane doslovně
    }

    @Test func extensionMaskCaseAndSearchReplace() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let f = try urls(["My File.JPEG"], in: d)
        var o = RenameOptions(); o.extMask = "jpg"; o.search = "file"; o.replace = "photo"; o.caseMode = .eachWord
        #expect(names(RenameEngine.preview(f, o)) == ["My Photo.Jpg"])
        o.caseMode = .upper; o.extMask = "[E]"
        #expect(names(RenameEngine.preview(f, o)) == ["MY PHOTO.JPEG"])
        o.caseMode = .unchanged; o.useRegex = true; o.search = "(\\w+) (\\w+)"; o.replace = "$2-$1"; o.extMask = "[E]"
        #expect(names(RenameEngine.preview(f, o)) == ["File-My.JPEG"])
        #expect(RenameEngine.validateRegex({ var x = o; x.search = "("; return x }()) != nil)
    }

    @Test func dateAndParentTokens() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let f = try write(d, "x.txt", mtime: Date(timeIntervalSince1970: 1_700_000_000))   // 2023-11-14 22:13:20 UTC
        var o = RenameOptions(); o.nameMask = "[P]-[Y][M][D]"
        let n = RenameEngine.preview([f], o)[0].newName
        #expect(n.hasPrefix(d.lastPathComponent + "-2023") && n.hasSuffix(".txt"))
    }

    @Test func detectsProblems() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let f = try urls(["a.txt", "b.txt", "keep.txt"], in: d)
        var o = RenameOptions(); o.nameMask = "same"
        #expect(RenameEngine.preview(Array(f.prefix(2)), o).allSatisfy { $0.problem == .duplicate })
        o.nameMask = "keep"
        #expect(RenameEngine.preview([f[0]], o)[0].problem == .existsOnDisk)
        o.nameMask = ""; o.extMask = ""
        #expect(RenameEngine.preview([f[0]], o)[0].problem == .empty)
        o.nameMask = "a/b"; o.extMask = "[E]"
        #expect(RenameEngine.preview([f[0]], o)[0].problem == .invalidCharacter)
    }

    @Test func swapAndUndo() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "a.txt", "A"), b = try write(d, "b.txt", "B")
        let swap = [RenamePreview(source: a, newName: "b.txt", problem: nil), RenamePreview(source: b, newName: "a.txt", problem: nil)]
        let applied = try RenameEngine.apply(swap)
        #expect(applied.count == 2)
        #expect(try String(contentsOf: a, encoding: .utf8) == "B" && String(contentsOf: b, encoding: .utf8) == "A")
        try RenameEngine.undo(applied)
        #expect(try String(contentsOf: a, encoding: .utf8) == "A" && String(contentsOf: b, encoding: .utf8) == "B")
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path).sorted() == ["a.txt", "b.txt"])   // žádné dočasné soubory
    }

    @Test func applyRollsBackOnConflict() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "a.txt", "A"); try write(d, "x.txt", "X")
        let bad = [RenamePreview(source: a, newName: "x.txt", problem: nil)]   // obejití kontroly: cíl existuje
        #expect(throws: Error.self) { try RenameEngine.apply(bad) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path).sorted() == ["a.txt", "x.txt"])
        #expect(try String(contentsOf: a, encoding: .utf8) == "A")
    }
}
