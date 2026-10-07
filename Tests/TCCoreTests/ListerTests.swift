import Testing
import Foundation
@testable import TCCore

@Suite struct ListerTests {
    @Test func hexRows() {
        let d = Data((0..<20).map { UInt8($0 + 0x40) })
        #expect(HexDump.rowCount(length: d.count) == 2 && HexDump.rowCount(length: 0) == 0)
        let r0 = HexDump.row(d, index: 0)
        #expect(r0.offset == "00000000" && r0.ascii == "@ABCDEFGHIJKLMNO" && r0.hex.hasPrefix("40 41 42"))
        let r1 = HexDump.row(d, index: 1)
        #expect(r1.offset == "00000010" && r1.ascii == "PQRS")
        #expect(HexDump.row(d, index: 5).offset.isEmpty)
        #expect(HexDump.row(Data([0x00, 0x7F]), index: 0).ascii == "..")
    }

    @Test func detectsEncodings() {
        #expect(TextDecoding.decode(Data("Příliš žluťoučký".utf8)).encoding == "UTF-8")
        #expect(TextDecoding.decode(Data([0xEF, 0xBB, 0xBF] + Array("ahoj".utf8))) == ("ahoj", "UTF-8 (BOM)"))
        let cp = TextDecoding.decode(Data([0x50, 0xF8, 0xED, 0x6C, 0x69, 0x9A]))   // "Příliš" ve Windows-1250
        #expect(cp.text == "Příliš" && cp.encoding == "Windows-1250")
        let u16 = Data([0xFF, 0xFE] + Array("ab".utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        #expect(TextDecoding.decode(u16) == ("ab", "UTF-16 LE"))
    }

    @Test func chooseModes() {
        let text = Data("hello".utf8), bin = Data([1, 0, 2])
        #expect(ListerSupport.modes(for: URL(fileURLWithPath: "/a.txt"), sample: text) == [.text, .hex])
        #expect(ListerSupport.modes(for: URL(fileURLWithPath: "/a.bin"), sample: bin) == [.hex, .text])
        #expect(ListerSupport.modes(for: URL(fileURLWithPath: "/a.png"), sample: bin).first == .image)
        #expect(ListerSupport.modes(for: URL(fileURLWithPath: "/a.pdf"), sample: bin).first == .pdf)
        #expect(ListerSupport.modes(for: URL(fileURLWithPath: "/a.mp4"), sample: bin).first == .media)
        #expect(ListerSupport.modes(for: URL(fileURLWithPath: "/a.html"), sample: text).first == .web)
    }
}

@Suite struct ChecksumTests {
    @Test func knownVectors() {
        let abc = Data("abc".utf8)
        #expect(Checksum.hash(of: abc, .md5) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(Checksum.hash(of: abc, .sha1) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(Checksum.hash(of: abc, .sha256) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(Checksum.hash(of: Data("123456789".utf8), .crc32) == "cbf43926")
    }

    @Test func fileHashMatchesDataHash() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let big = String(repeating: "TCommander", count: 500_000)
        let f = try write(d, "big.txt", big)
        for a in ChecksumAlgorithm.allCases {
            #expect(Checksum.hash(f, a) == Checksum.hash(of: Data(big.utf8), a))
        }
        #expect(Checksum.hash(f, .sha256, onBytes: { _ in false }) == nil)
        #expect(Checksum.hash(d.appendingPathComponent("missing"), .md5) == nil)
    }
}

@Suite struct TextEncodingRoundTripTests {
    @Test func savesInTheOriginalEncoding() {
        let cases: [(Data, String)] = [
            (Data("Příliš žluťoučký kůň".utf8), "UTF-8"),
            (Data([0xEF, 0xBB, 0xBF]) + Data("ahoj".utf8), "UTF-8 (BOM)"),
            (Data([0xFF, 0xFE]) + "ab".data(using: .utf16LittleEndian)!, "UTF-16 LE"),
            (Data([0xFE, 0xFF]) + "ab".data(using: .utf16BigEndian)!, "UTF-16 BE"),
            (Data([0x50, 0xF8, 0xED, 0x6C, 0x69, 0x9A]), "Windows-1250"),
        ]
        for (data, name) in cases {
            let d = TextDecoding.decode(data)
            #expect(d.encoding == name)
            #expect(TextDecoding.encode(d.text, as: d.encoding) == data, "\(name)")      // beze změny = bajt po bajtu stejné
        }
    }

    @Test func refusesToLoseCharacters() {
        #expect(TextDecoding.encode("čeština 🐎", as: "Windows-1250") == nil)              // emoji v Windows-1250 nelze
        #expect(TextDecoding.encode("čeština 🐎", as: "UTF-8") != nil)
    }
}
