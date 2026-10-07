import Foundation

/// Zpracování výstupu terminálu typu „dumb“: odstraní escape sekvence, správně zpracuje návrat vozíku (přepis řádku)
/// a zpětný posun a složí UTF-8 znaky rozdělené mezi bloky dat.
public struct TerminalTextBuffer {
    private var done = ""
    private var current: [Character] = []
    private var column = 0
    private var pending = Data()
    private var inEscape = false, csi = false, osc = false
    public let maxCharacters: Int

    public init(maxCharacters: Int = 400_000) { self.maxCharacters = maxCharacters }

    public var text: String { done + String(current) }

    public mutating func append(_ data: Data) {
        pending.append(data)
        // ponechat nedokončený znak UTF-8 na konci pro další blok
        var keep = 0
        var i = pending.count - 1
        while i >= 0, keep < 4 {
            let b = pending[pending.startIndex + i]
            if b & 0xC0 == 0x80 { keep += 1; i -= 1; continue }
            if b >= 0xC0 {
                let need = b >= 0xF0 ? 4 : (b >= 0xE0 ? 3 : 2)
                keep = (keep + 1 < need) ? keep + 1 : 0
            }
            break
        }
        let cut = pending.count - keep
        let s = String(decoding: pending.prefix(cut), as: UTF8.self)
        pending = Data(pending.suffix(keep))
        for c in s.unicodeScalars { feed(c) }
        if done.count > maxCharacters { done = String(done.suffix(maxCharacters * 3 / 4)) }
    }

    private mutating func feed(_ c: Unicode.Scalar) {
        if osc { if c == "\u{07}" { osc = false; inEscape = false } else if c == "\u{1B}" { inEscape = true }; return }
        if inEscape {
            if csi { if (0x40...0x7E).contains(c.value) { csi = false; inEscape = false }; return }
            if c == "[" { csi = true; return }
            if c == "]" { osc = true; return }
            inEscape = false; return
        }
        switch c {
        case "\u{1B}": inEscape = true
        case "\r": column = 0
        case "\n": done += String(current) + "\n"; current = []; column = 0
        case "\u{08}": column = max(0, column - 1)
        case "\u{07}": break
        case "\t":
            let target = (column / 8 + 1) * 8
            while column < target { put(" ") }
        default: if c.value >= 32 { put(Character(c)) }
        }
    }

    private mutating func put(_ ch: Character) {
        if column < current.count { current[column] = ch } else { while current.count < column { current.append(" ") }; current.append(ch) }
        column += 1
    }
}
