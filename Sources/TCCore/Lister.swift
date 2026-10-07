import Foundation
import UniformTypeIdentifiers

public enum ListerMode: String, Sendable, CaseIterable {
    case text, hex, image, pdf, media, web
}

public enum ListerSupport {
    /// Režimy, které dává smysl pro soubor nabídnout; první je výchozí.
    public static func modes(for url: URL, sample: Data) -> [ListerMode] {
        let type = UTType(filenameExtension: url.pathExtension)
        if let t = type {
            if t.conforms(to: .image), !t.conforms(to: .svg) { return [.image, .hex] }
            if t.conforms(to: .pdf) { return [.pdf, .hex] }
            if t.conforms(to: .audiovisualContent) { return [.media, .hex] }
            if t.conforms(to: .html) { return [.web, .text, .hex] }
        }
        return looksBinary(sample) ? [.hex, .text] : [.text, .hex]
    }

    /// Binární data: nulový bajt v prvních 8 kB (kromě UTF-16 s BOM).
    public static func looksBinary(_ data: Data) -> Bool {
        let head = data.prefix(8192)
        if head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF]) { return false }
        return head.contains(0)
    }
}

public enum TextDecoding {
    public static func decode(_ data: Data) -> (text: String, encoding: String) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let s = String(data: data.dropFirst(3), encoding: .utf8) { return (s, "UTF-8 (BOM)") }
        if data.starts(with: [0xFF, 0xFE]), let s = String(data: data, encoding: .utf16LittleEndian) { return (String(s.dropFirst()), "UTF-16 LE") }
        if data.starts(with: [0xFE, 0xFF]), let s = String(data: data, encoding: .utf16BigEndian) { return (String(s.dropFirst()), "UTF-16 BE") }
        if let s = String(data: data, encoding: .utf8) { return (s, "UTF-8") }
        let cp1250 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsLatin2.rawValue)))
        if let s = String(data: data, encoding: cp1250) { return (s, "Windows-1250") }
        return (String(decoding: data, as: UTF8.self), "UTF-8 (s chybami)")
    }
}

public extension TextDecoding {
    /// Nabízená kódování pro ruční výběr v Listeru.
    static let selectableEncodings: [String] = ["Automaticky", "UTF-8", "Windows-1250", "ISO-8859-2", "ISO-8859-1", "MacRoman", "UTF-16 LE", "UTF-16 BE"]

    /// Dekódování ve vynuceném kódování (název z `selectableEncodings`); chybné bajty se nahradí.
    static func decode(_ data: Data, forced name: String) -> String {
        func make(_ cf: CFStringEncodings) -> String.Encoding { String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cf.rawValue))) }
        let enc: String.Encoding
        switch name {
        case "UTF-8": return String(decoding: data, as: UTF8.self)
        case "Windows-1250": enc = make(.windowsLatin2)
        case "ISO-8859-2": enc = make(.isoLatin2)
        case "ISO-8859-1": enc = .isoLatin1
        case "MacRoman": enc = .macOSRoman
        case "UTF-16 LE": return String(data: data.starts(with: [0xFF, 0xFE]) ? data.dropFirst(2) : data, encoding: .utf16LittleEndian) ?? ""
        case "UTF-16 BE": return String(data: data.starts(with: [0xFE, 0xFF]) ? data.dropFirst(2) : data, encoding: .utf16BigEndian) ?? ""
        default: return decode(data).text
        }
        return String(data: data, encoding: enc) ?? String(decoding: data, as: UTF8.self)
    }

    /// Offset z textu: "255", "0xFF", "ff" (bez předpony se bere desítkově, pokud jde, jinak šestnáctkově).
    static func parseOffset(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("0x") { return Int(t.dropFirst(2), radix: 16) }
        return Int(t) ?? Int(t, radix: 16)
    }

    /// Zakóduje text zpět do kódování, ve kterém byl načten (název z `decode`); nil, pokud některé znaky nelze v kódování vyjádřit.
    static func encode(_ text: String, as encoding: String) -> Data? {
        switch encoding {
        case "UTF-8", "UTF-8 (s chybami)": return Data(text.utf8)
        case "UTF-8 (BOM)": return Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)
        case "UTF-16 LE": return text.data(using: .utf16LittleEndian).map { Data([0xFF, 0xFE]) + $0 }
        case "UTF-16 BE": return text.data(using: .utf16BigEndian).map { Data([0xFE, 0xFF]) + $0 }
        case "Windows-1250":
            let cp1250 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsLatin2.rawValue)))
            return text.data(using: cp1250, allowLossyConversion: false)
        default: return Data(text.utf8)
        }
    }
}

public enum HexDump {
    public static let width = 16

    public static func rowCount(length: Int) -> Int { (length + width - 1) / width }

    public static func row(_ data: Data, index: Int) -> (offset: String, hex: String, ascii: String) {
        let start = data.startIndex + index * width
        guard start < data.endIndex else { return ("", "", "") }
        let bytes = data[start..<min(start + width, data.endIndex)]
        var hex = "", ascii = ""
        for (i, b) in bytes.enumerated() {
            hex += String(format: "%02X", b) + (i == 7 ? "  " : " ")
            ascii.append((0x20..<0x7F).contains(b) ? Character(UnicodeScalar(b)) : ".")
        }
        return (String(format: "%08X", index * width), hex, ascii)
    }
}
