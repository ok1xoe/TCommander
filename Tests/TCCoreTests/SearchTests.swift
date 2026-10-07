import Testing
import Foundation
@testable import TCCore

@Suite struct SearchTests {
    func run(_ c: SearchCriteria) -> [String] {
        nonisolated(unsafe) var names: [String] = []
        FileSearch().run(c) { names.append($0.url.lastPathComponent) }
        return names.sorted()
    }

    func tree() throws -> URL {
        let d = try makeTempDir()
        try write(d, "a.txt", "Hello World\nsecond line")
        try write(d, "b.log", "nothing here")
        try write(d, "sub/c.txt", "příliš ŽLUŤOUČKÝ kůň")
        try write(d, "sub/deep/d.txt", "hello again", mtime: Date(timeIntervalSince1970: 1_000))
        try write(d, ".hidden.txt", "hello")
        return d
    }

    @Test func masksAndSubdirectories() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        var c = SearchCriteria(root: d)
        c.masks = "*.txt"
        #expect(run(c) == ["a.txt", "c.txt", "d.txt"])
        c.includeSubdirectories = false
        #expect(run(c) == ["a.txt"])
        c.includeSubdirectories = true; c.includeHidden = true
        #expect(run(c).contains(".hidden.txt"))
    }

    @Test func sizeAndDateFilters() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        var c = SearchCriteria(root: d)
        c.minSize = 20
        #expect(run(c) == ["a.txt", "c.txt"])
        c = SearchCriteria(root: d); c.modifiedBefore = Date(timeIntervalSince1970: 2_000)
        #expect(run(c) == ["d.txt"])
        c = SearchCriteria(root: d); c.modifiedAfter = Date(timeIntervalSince1970: 2_000); c.masks = "d.*"
        #expect(run(c).isEmpty)
    }

    @Test func contentSearch() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        var c = SearchCriteria(root: d); c.text = "hello"
        #expect(run(c) == ["a.txt", "d.txt"])
        c.caseSensitive = true
        #expect(run(c) == ["d.txt"])
        c = SearchCriteria(root: d); c.text = "zlutoucky kun"        // bez diakritiky a velikosti písmen
        #expect(run(c) == ["c.txt"])
        c = SearchCriteria(root: d); c.text = "^second\\s+LINE$"; c.useRegex = true
        #expect(run(c) == ["a.txt"])
    }

    @Test func reportsLineAndSnippet() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        var c = SearchCriteria(root: d); c.text = "second"
        nonisolated(unsafe) var hit: SearchHit?
        FileSearch().run(c) { hit = $0 }
        #expect(hit?.line == 2 && hit?.snippet == "second line")
    }

    @Test func validatesRegexAndCancels() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        var c = SearchCriteria(root: d); c.text = "("; c.useRegex = true
        #expect(FileSearch.validate(c) != nil)
        c = SearchCriteria(root: d)
        nonisolated(unsafe) var n = 0
        FileSearch().run(c, isCancelled: { true }) { _ in n += 1 }
        #expect(n == 0)
    }
}

@Suite struct ArchiveSearchTests {
    @Test func findsFilesAndTextInsideArchives() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "src/notes.txt", "alpha\nsecret word here\nomega"), b = try write(d, "src/data/readme.md", "nothing")
        let zip = d.appendingPathComponent("pack/a.zip"); try FileManager.default.createDirectory(at: zip.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(ArchiveWriter.create(zip, format: .zip, sources: [a, b.deletingLastPathComponent()]).failures.isEmpty)
        func run(_ c: SearchCriteria) -> [SearchHit] {
            nonisolated(unsafe) var hits: [SearchHit] = []
            FileSearch().run(c) { hits.append($0) }
            return hits
        }
        var c = SearchCriteria(root: d.appendingPathComponent("pack")); c.masks = "*.txt"
        #expect(run(c).isEmpty)                                       // bez volby se archivy neprohledávají
        c.searchInArchives = true
        let byName = run(c)
        #expect(byName.count == 1 && byName[0].inner == "notes.txt" && byName[0].url == zip)
        c.masks = "*"; c.text = "SECRET"
        let byText = run(c)
        #expect(byText.count == 1 && byText[0].inner == "notes.txt" && byText[0].line == 2 && byText[0].snippet == "secret word here")
        c.text = ""; c.masks = "readme.*"
        #expect(run(c).first?.inner == "data/readme.md")
    }
}
