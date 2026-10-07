import Foundation

/// Styl textu v terminálu (barva písma z SGR sekvencí a tučné písmo).
public struct TerminalStyle: Equatable, Sendable {
    /// 0–15 základní barvy; 0x1000000 | RGB pro 256 barev a TrueColor; nil = výchozí.
    public var foreground: Int?
    public var bold = false
    public init(foreground: Int? = nil, bold: Bool = false) { self.foreground = foreground; self.bold = bold }

    /// Barva jako RGB (0xRRGGBB) pro základní paletu, nebo přímo zadané RGB.
    public func rgb() -> UInt32? {
        guard let f = foreground else { return nil }
        if f & 0x1000000 != 0 { return UInt32(f & 0xFFFFFF) }
        let basic: [UInt32] = [0x2E3436, 0xCC0000, 0x4E9A06, 0xC4A000, 0x3465A4, 0x75507B, 0x06989A, 0xD3D7CF,
                               0x555753, 0xEF2929, 0x8AE234, 0xFCE94F, 0x729FCF, 0xAD7FA8, 0x34E2E2, 0xEEEEEC]
        return f >= 0 && f < 16 ? basic[f] : nil
    }

    /// Barva z indexu 0–255 palety xterm.
    public static func palette256(_ n: Int) -> Int {
        if n < 16 { return n }
        if n >= 232 { let g = 8 + (n - 232) * 10; return 0x1000000 | (g << 16) | (g << 8) | g }
        let i = n - 16
        func level(_ v: Int) -> Int { v == 0 ? 0 : 55 + v * 40 }
        return 0x1000000 | (level(i / 36) << 16) | (level(i / 6 % 6) << 8) | level(i % 6)
    }
}

/// Zpracování výstupu terminálu typu „dumb“: odstraní escape sekvence (barvy písma z SGR si zapamatuje), správně zpracuje návrat vozíku
/// (přepis řádku) a zpětný posun a složí UTF-8 znaky rozdělené mezi bloky dat.
public struct TerminalTextBuffer {
    public struct Run: Equatable, Sendable { public var text: String; public var style: TerminalStyle }

    private var doneLines: [[Run]] = []
    private var doneLength = 0
    private var current: [(ch: Character, style: TerminalStyle)] = []
    private var column = 0
    private var pending = Data()
    private var inEscape = false, csi = false, osc = false
    private var csiParams = ""
    private var style = TerminalStyle()
    public let maxCharacters: Int

    public init(maxCharacters: Int = 400_000) { self.maxCharacters = maxCharacters }

    public var text: String { doneLines.map { $0.map(\.text).joined() }.joined() + String(current.map(\.ch)) }

    /// Text jako souvislé úseky se stejným stylem (pro obarvené zobrazení).
    public var runs: [Run] {
        var out: [Run] = []
        for r in doneLines.joined() {
            if var last = out.last, last.style == r.style { last.text += r.text; out[out.count - 1] = last } else { out.append(r) }
        }
        for (ch, st) in current {
            if var last = out.last, last.style == st { last.text.append(ch); out[out.count - 1] = last } else { out.append(Run(text: String(ch), style: st)) }
        }
        return out
    }

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
        trim()
    }

    private mutating func trim() {
        guard doneLength > maxCharacters else { return }
        while doneLength > maxCharacters * 3 / 4, !doneLines.isEmpty { doneLength -= doneLines.removeFirst().reduce(0) { $0 + $1.text.count } }
    }

    private mutating func finishLine() {
        var line: [Run] = []
        for (ch, st) in current {
            if var last = line.last, last.style == st { last.text.append(ch); line[line.count - 1] = last } else { line.append(Run(text: String(ch), style: st)) }
        }
        line.append(Run(text: "\n", style: TerminalStyle()))
        doneLength += current.count + 1
        doneLines.append(line)
        current = []; column = 0
    }

    private mutating func feed(_ c: Unicode.Scalar) {
        if osc { if c == "\u{07}" { osc = false; inEscape = false } else if c == "\u{1B}" { inEscape = true }; return }
        if inEscape {
            if csi {
                if (0x40...0x7E).contains(c.value) {
                    if c == "m" { applySGR(csiParams) } else { applyCursor(final: c, params: csiParams) }
                    csi = false; inEscape = false; csiParams = ""
                } else { csiParams.unicodeScalars.append(c) }
                return
            }
            if c == "[" { csi = true; csiParams = ""; return }
            if c == "]" { osc = true; return }
            inEscape = false; return
        }
        switch c {
        case "\u{1B}": inEscape = true
        case "\r": column = 0
        case "\n": finishLine()
        case "\u{08}": column = max(0, column - 1)
        case "\u{07}": break
        case "\t":
            let target = (column / 8 + 1) * 8
            while column < target { put(" ") }
        default: if c.value >= 32 { put(Character(c)) }
        }
    }

    private mutating func put(_ ch: Character) {
        if column < current.count { current[column] = (ch, style) }
        else { while current.count < column { current.append((" ", style)) }; current.append((ch, style)) }
        column += 1
    }

    /// Řídicí sekvence používané při editaci řádku (zsh/bash): posun kurzoru, mazání do konce řádku a mazání znaků.
    private mutating func applyCursor(final c: Unicode.Scalar, params: String) {
        guard !params.hasPrefix("?"), !params.hasPrefix(">") else { return }            // soukromé režimy (bracketed paste, kurzor) ignorujeme
        let n = Int(params.split(separator: ";").first ?? "") ?? 0
        switch c {
        case "C": column += max(1, n)
        case "D": column = max(0, column - max(1, n))
        case "G": column = max(0, (n == 0 ? 1 : n) - 1)
        case "K":
            switch n {
            case 0: if column < current.count { current.removeSubrange(column...) }
            case 1: for i in 0..<min(column + 1, current.count) { current[i].ch = " " }
            default: current.removeAll()
            }
        case "P": if column < current.count { current.removeSubrange(column..<min(current.count, column + max(1, n))) }
        default: break                                                                  // A, B, H, J … se zatím nepodporují
        }
    }

    private mutating func applySGR(_ params: String) {
        let codes = params.isEmpty ? [0] : params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var i = 0
        while i < codes.count {
            let c = codes[i]
            switch c {
            case 0: style = TerminalStyle()
            case 1: style.bold = true
            case 22: style.bold = false
            case 30...37: style.foreground = c - 30
            case 90...97: style.foreground = c - 90 + 8
            case 39: style.foreground = nil
            case 38:
                if i + 2 < codes.count, codes[i + 1] == 5 { style.foreground = TerminalStyle.palette256(codes[i + 2]); i += 2 }
                else if i + 4 < codes.count, codes[i + 1] == 2 { style.foreground = 0x1000000 | ((codes[i + 2] & 255) << 16) | ((codes[i + 3] & 255) << 8) | (codes[i + 4] & 255); i += 4 }
            default: break
            }
            i += 1
        }
    }
}
