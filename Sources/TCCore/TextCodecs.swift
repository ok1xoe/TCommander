import Foundation

public enum FileEncoding: String, Sendable, CaseIterable {
    case mime = "MIME (Base64)", uue = "UUE", xxe = "XXE"
    public var fileExtension: String { switch self { case .mime: "b64"; case .uue: "uue"; case .xxe: "xxe" } }
    public static func from(fileName: String) -> FileEncoding? {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "b64", "mim", "mime": .mime
        case "uue", "uu": .uue
        case "xxe", "xx": .xxe
        default: nil
        }
    }
}

public enum TextCodecs {
    private static let uuAlphabet = Array("`!\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_")
    private static let xxAlphabet = Array("+-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    public static func encode(_ data: Data, as kind: FileEncoding, fileName: String, mode: UInt16 = 0o644) -> String {
        switch kind {
        case .mime:
            return data.base64EncodedString(options: [.lineLength76Characters, .endLineWithLineFeed]) + "\n"
        case .uue: return uuLike(data, fileName, mode, uuAlphabet, "begin", "end")
        case .xxe: return uuLike(data, fileName, mode, xxAlphabet, "begin", "end")
        }
    }

    /// Vrací obsah a (u UUE/XXE) původní název souboru.
    public static func decode(_ text: String, as kind: FileEncoding) -> (data: Data, name: String?)? {
        switch kind {
        case .mime:
            let clean = text.filter { !$0.isWhitespace }
            return Data(base64Encoded: clean).map { ($0, nil) }
        case .uue: return uuLikeDecode(text, uuAlphabet, uuAlphabet.firstIndex(of: "`")!, spaceAsZero: true)
        case .xxe: return uuLikeDecode(text, xxAlphabet, 0, spaceAsZero: false)
        }
    }

    private static func uuLike(_ data: Data, _ name: String, _ mode: UInt16, _ alpha: [Character], _ begin: String, _ end: String) -> String {
        var out = "\(begin) \(String(mode, radix: 8)) \(name)\n"
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            let chunk = Array(bytes[i..<min(i + 45, bytes.count)])
            out.append(alpha[chunk.count])
            var j = 0
            while j < chunk.count {
                let b0 = chunk[j], b1 = j + 1 < chunk.count ? chunk[j + 1] : 0, b2 = j + 2 < chunk.count ? chunk[j + 2] : 0
                out.append(alpha[Int(b0 >> 2)])
                out.append(alpha[Int(((b0 & 0x3) << 4) | (b1 >> 4))])
                out.append(alpha[Int(((b1 & 0xF) << 2) | (b2 >> 6))])
                out.append(alpha[Int(b2 & 0x3F)])
                j += 3
            }
            out.append("\n"); i += 45
        }
        out += "\(alpha[0])\n\(end)\n"
        return out
    }

    private static func uuLikeDecode(_ text: String, _ alpha: [Character], _ zero: Int, spaceAsZero: Bool) -> (data: Data, name: String?)? {
        var lookup: [Character: Int] = [:]
        for (i, c) in alpha.enumerated() { lookup[c] = i }
        if spaceAsZero { lookup[" "] = 0 }
        var name: String?
        var out = [UInt8]()
        var started = false
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(raw)
            if !started {
                if line.hasPrefix("begin ") {
                    let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                    if parts.count == 3 { name = String(parts[2]) }
                    started = true
                }
                continue
            }
            if line == "end" { return (Data(out), name) }
            guard let first = line.first, let len = lookup[first] else { return nil }
            if len == 0 { continue }
            let chars = Array(line.dropFirst())
            var vals = chars.compactMap { lookup[$0] }
            if vals.count != chars.count { return nil }
            while vals.count % 4 != 0 { vals.append(0) }       // zkrácené řádky (odstraněné koncové mezery)
            var decoded = [UInt8]()
            var k = 0
            while k + 3 < vals.count {
                decoded.append(UInt8(truncatingIfNeeded: (vals[k] << 2) | (vals[k + 1] >> 4)))
                decoded.append(UInt8(truncatingIfNeeded: ((vals[k + 1] & 0xF) << 4) | (vals[k + 2] >> 2)))
                decoded.append(UInt8(truncatingIfNeeded: ((vals[k + 2] & 0x3) << 6) | vals[k + 3]))
                k += 4
            }
            guard decoded.count >= len else { return nil }
            out += decoded.prefix(len)
        }
        return started ? (Data(out), name) : nil
    }
}
