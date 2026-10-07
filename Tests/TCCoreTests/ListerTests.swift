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
