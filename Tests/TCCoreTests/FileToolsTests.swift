import Testing
import Foundation
@testable import TCCore

@Suite struct FileToolsTests {
    @Test func checksumFileRoundTripAndVerify() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = try write(d, "a.txt", "alpha"), b = try write(d, "b.txt", "beta")
        let lines = [a, b].map { ChecksumFile.Line(hash: Checksum.hash($0, .sha256)!, name: $0.lastPathComponent) }
        let text = ChecksumFile.format(lines)
        #expect(ChecksumFile.parse(text) == lines)
        #expect(ChecksumFile.parse("# komentář\nABC  file one.txt\n\n").first == .init(hash: "abc", name: "file one.txt"))
        let sums = try write(d, "SUMS.sha256", text)
        #expect(ChecksumFile.verify(sumFile: sums)?.allSatisfy { $0.status == .ok } == true)
        try "changed".write(to: b, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: a)
        let r = ChecksumFile.verify(sumFile: sums)
        #expect(r == [.init(name: "a.txt", status: .missing), .init(name: "b.txt", status: .mismatch)])
    }

    @Test func detectsAlgorithm() {
        #expect(ChecksumFile.algorithm(forFileName: "x.md5") == .md5)
        #expect(ChecksumFile.algorithm(forFileName: "sums.txt", firstHash: String(repeating: "a", count: 64)) == .sha256)
        #expect(ChecksumFile.algorithm(forFileName: "sums.txt") == nil)
    }

    @Test func attributes() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let f = try write(d, "f")
        try FileAttributes.apply(f, permissions: 0o600, modified: Date(timeIntervalSince1970: 1_000_000))
        let e = try LocalFileSystem().stat(f)
        #expect(e.permissions == 0o600 && e.modified == Date(timeIntervalSince1970: 1_000_000))
        #expect(FileAttributes.parseOctal("0755") == 0o755 && FileAttributes.parseOctal("755") == 0o755)
        #expect(FileAttributes.parseOctal("999") == nil && FileAttributes.parseOctal("12") == nil)
    }

    @Test func links() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let f = try write(d, "f", "data")
        let ops = FileOperations()
        try ops.makeSymlink(to: "f", at: d.appendingPathComponent("sym"))
        try ops.makeHardlink(to: f, at: d.appendingPathComponent("hard"))
        #expect(try String(contentsOf: d.appendingPathComponent("sym"), encoding: .utf8) == "data")
        #expect(try String(contentsOf: d.appendingPathComponent("hard"), encoding: .utf8) == "data")
        #expect(try LocalFileSystem().stat(d.appendingPathComponent("sym")).isSymlink)
        #expect(throws: Error.self) { try ops.makeSymlink(to: "f", at: d.appendingPathComponent("sym")) }
    }

    @Test func splitAndCombineRoundTrip() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let content = String((0..<2500).map { Character(UnicodeScalar(UInt8(65 + $0 % 26))) })
        let f = try write(d, "big.dat", content)
        let parts = d.appendingPathComponent("parts"); try FileManager.default.createDirectory(at: parts, withIntermediateDirectories: true)
        let r = FileSplitter.split(f, partSize: 1000, into: parts)
        #expect(r.failures.isEmpty && r.succeeded == 3)
        #expect(try FileManager.default.contentsOfDirectory(atPath: parts.path).sorted() == ["big.dat.001", "big.dat.002", "big.dat.003"])
        #expect(try Data(contentsOf: parts.appendingPathComponent("big.dat.003")).count == 500)
        let out = d.appendingPathComponent("out"); try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let c = FileSplitter.combine(first: parts.appendingPathComponent("big.dat.001"), into: out)
        #expect(c.failures.isEmpty)
        #expect(try String(contentsOf: out.appendingPathComponent("big.dat"), encoding: .utf8) == content)
        #expect(FileSplitter.combine(first: parts.appendingPathComponent("big.dat.002"), into: out).failures.count == 1)
        #expect(FileSplitter.combine(first: parts.appendingPathComponent("big.dat.001"), into: out).failures.count == 1)   // už existuje
    }

    @Test func exactMultipleAndCancelLeaveNoStrayParts() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let f = try write(d, "x", String(repeating: "z", count: 2000))
        let p1 = d.appendingPathComponent("p1"); try FileManager.default.createDirectory(at: p1, withIntermediateDirectories: true)
        #expect(FileSplitter.split(f, partSize: 1000, into: p1).succeeded == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: p1.path).count == 2)
        let p2 = d.appendingPathComponent("p2"); try FileManager.default.createDirectory(at: p2, withIntermediateDirectories: true)
        let c = OperationControl(); c.cancel()
        #expect(FileSplitter.split(f, partSize: 1000, into: p2, control: c).cancelled)
        #expect(try FileManager.default.contentsOfDirectory(atPath: p2.path).isEmpty)
    }
}
