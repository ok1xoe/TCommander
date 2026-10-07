import Testing
import Foundation
@testable import TCCore

@Suite struct DuplicatesTests {
    @Test func findsGroupsByContent() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        try write(d, "a.txt", "same content"); try write(d, "sub/b.txt", "same content"); try write(d, "sub/deep/c.dat", "same content")
        try write(d, "diff.txt", "other content"); try write(d, "x/size.txt", "same_content")      // stejná délka, jiný obsah
        try write(d, "unique.txt", "u"); try write(d, ".hidden", "same content")
        let g = DuplicateFinder.find(in: d)
        #expect(g.count == 1 && g[0].files.map(\.lastPathComponent).sorted() == ["a.txt", "b.txt", "c.dat"])
        #expect(DuplicateFinder.find(in: d, includeHidden: true)[0].files.count == 4)
        #expect(DuplicateFinder.find(in: d, minSize: 100).isEmpty)
        #expect(DuplicateFinder.find(in: d, isCancelled: { true }).isEmpty)
    }

    @Test func differsOnlyAfterFirst64K() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let prefix = String(repeating: "x", count: 70_000)
        try write(d, "a", prefix + "A"); try write(d, "b", prefix + "B"); try write(d, "c", prefix + "A")
        let g = DuplicateFinder.find(in: d)
        #expect(g.count == 1 && g[0].files.map(\.lastPathComponent) == ["a", "c"])
    }
}

@Suite struct CodecTests {
    let sample = Data((0..<300).map { UInt8($0 % 251) })

    @Test func uueKnownVector() throws {
        let text = TextCodecs.encode(Data("Cat".utf8), as: .uue, fileName: "cat.txt")
        #expect(text == "begin 644 cat.txt\n#0V%T\n`\nend\n")
        let back = try #require(TextCodecs.decode(text, as: .uue))
        #expect(back.data == Data("Cat".utf8) && back.name == "cat.txt")
    }

    @Test func roundTripsAllFormats() throws {
        for kind in FileEncoding.allCases {
            for data in [Data(), Data([0]), Data("ab".utf8), sample] {
                let text = TextCodecs.encode(data, as: kind, fileName: "f.bin")
                let back = try #require(TextCodecs.decode(text, as: kind), "\(kind) \(data.count)")
                #expect(back.data == data)
            }
        }
    }

    @Test func mimeWrapsAndToleratesWhitespace() throws {
        let text = TextCodecs.encode(sample, as: .mime, fileName: "x")
        #expect(text.split(separator: "\n").allSatisfy { $0.count <= 76 })
        #expect(TextCodecs.decode("  " + text.replacingOccurrences(of: "\n", with: "\r\n"), as: .mime)?.data == sample)
        #expect(TextCodecs.decode("***", as: .mime) == nil)
        #expect(TextCodecs.decode("not uue", as: .uue) == nil)
    }

    @Test func detectsByExtension() {
        #expect(FileEncoding.from(fileName: "a.UUE") == .uue && FileEncoding.from(fileName: "a.b64") == .mime && FileEncoding.from(fileName: "a.txt") == nil)
    }
}
