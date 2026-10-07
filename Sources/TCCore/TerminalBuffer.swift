import Foundation

/// Styl textu v terminálu (barva písma z SGR sekvencí a tučné písmo).
public struct TerminalStyle: Equatable, Sendable {
    /// 0–15 základní barvy; 0x1000000 | RGB pro 256 barev a TrueColor; nil = výchozí.
    public var foreground: Int?
    public var background: Int?
    public var bold = false
    public var inverse = false
    public var underline = false
    public init(foreground: Int? = nil, bold: Bool = false, background: Int? = nil, inverse: Bool = false, underline: Bool = false) {
        self.foreground = foreground; self.bold = bold; self.background = background; self.inverse = inverse; self.underline = underline
    }

    /// Barva písma jako RGB (0xRRGGBB) pro základní paletu, nebo přímo zadané RGB.
    public func rgb() -> UInt32? { Self.rgb(of: foreground) }
    /// Barva pozadí jako RGB.
    public func backgroundRGB() -> UInt32? { Self.rgb(of: background) }

    static func rgb(of value: Int?) -> UInt32? {
        guard let f = value else { return nil }
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
    private var screen: TerminalScreen?
    private var skipNext = false
    private var size = (rows: 24, cols: 80)
    /// Odpovědi pro program (např. pozice kurzoru na dotaz ESC[6n); okno je odešle do shellu a vyprázdní.
    public var replies = ""
    /// Program zapnul „aplikační“ režim šipek (ESC[?1h) – šipky se pak posílají jako ESC O A…
    public private(set) var applicationCursor = false
    /// Probíhá celoobrazovkový program (alternativní obrazovka).
    public var isFullScreen: Bool { screen != nil }

    /// Nastaví velikost obrazovky v buňkách (volá okno při změně velikosti).
    public mutating func resize(columns: Int, rows: Int) {
        size = (max(1, rows), max(1, columns))
        screen?.resize(rows: size.rows, cols: size.cols)
    }

    public init(maxCharacters: Int = 400_000) { self.maxCharacters = maxCharacters }

    public var text: String {
        if let screen { return screen.plainLines.joined(separator: "\n") }
        return doneLines.map { $0.map(\.text).joined() }.joined() + String(current.map(\.ch)) }

    /// Text jako souvislé úseky se stejným stylem (pro obarvené zobrazení).
    public var runs: [Run] {
        if let screen { return screen.runs() }
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
        if skipNext { skipNext = false; return }                                         // znak za ESC ( / ESC ) / ESC #
        if osc { if c == "\u{07}" { osc = false; inEscape = false } else if c == "\u{1B}" { inEscape = true }; return }
        if inEscape {
            if csi {
                if (0x40...0x7E).contains(c.value) {
                    handleCSI(final: c, params: csiParams)
                    csi = false; inEscape = false; csiParams = ""
                } else { csiParams.unicodeScalars.append(c) }
                return
            }
            if c == "[" { csi = true; csiParams = ""; return }
            if c == "]" { osc = true; return }
            inEscape = false
            if c == "(" || c == ")" || c == "#" { skipNext = true; return }
            if screen != nil {
                switch c {
                case "M": screen?.reverseIndex()
                case "D": screen?.lineFeed()
                case "E": screen?.carriageReturn(); screen?.lineFeed()
                case "7": screen?.saveCursor()
                case "8": screen?.restoreCursor()
                case "c": screen?.fullReset()
                default: break
                }
            }
            return
        }
        if screen != nil { feedScreen(c); return }
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

    private mutating func feedScreen(_ c: Unicode.Scalar) {
        switch c {
        case "\u{1B}": inEscape = true
        case "\r": screen?.carriageReturn()
        case "\n", "\u{0B}", "\u{0C}": screen?.lineFeed()
        case "\u{08}": screen?.backspace()
        case "\t": screen?.tab()
        default: if c.value >= 32 && c.value != 0x7F { screen?.put(Character(c)) }
        }
    }

    /// Soukromé režimy (ESC[?…h/l): alternativní obrazovka, aplikační šipky, viditelnost kurzoru; ostatní se ignorují.
    private mutating func handlePrivateMode(final: Unicode.Scalar, params: String) {
        guard final == "h" || final == "l" else { return }
        let on = final == "h"
        for code in params.dropFirst().split(separator: ";").compactMap({ Int($0) }) {
            switch code {
            case 1: applicationCursor = on
            case 25: screen?.cursorVisible = on
            case 47, 1047, 1049:
                if on, screen == nil { screen = TerminalScreen(rows: size.rows, cols: size.cols) }
                else if !on { screen = nil }
            default: break
            }
        }
    }

    private mutating func handleCSI(final c: Unicode.Scalar, params: String) {
        if params.hasPrefix("?") { handlePrivateMode(final: c, params: params); return }
        if screen != nil {
            if let reply = screen?.csi(final: c, params: params) { replies += reply }
            return
        }
        if c == "m" { style.apply(sgr: params) }
        else if c == "n" || c == "c" {                                                   // dotazy na pozici kurzoru a typ terminálu
            if c == "n", params == "6" { replies += "\u{1B}[\(1);\(column + 1)R" }
            else if c == "c" { replies += params.hasPrefix(">") ? "\u{1B}[>0;95;0c" : "\u{1B}[?1;2c" }
        } else { applyCursor(final: c, params: params) }
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
}

extension TerminalStyle {
    /// Použije SGR parametry (např. „1;31“, „38;5;208“, „7“, „48;2;10;20;30“).
    public mutating func apply(sgr params: String) {
        let codes = params.isEmpty ? [0] : params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var i = 0
        func extended() -> Int? {
            if i + 2 < codes.count, codes[i + 1] == 5 { defer { i += 2 }; return TerminalStyle.palette256(codes[i + 2]) }
            if i + 4 < codes.count, codes[i + 1] == 2 { defer { i += 4 }; return 0x1000000 | ((codes[i + 2] & 255) << 16) | ((codes[i + 3] & 255) << 8) | (codes[i + 4] & 255) }
            return nil
        }
        while i < codes.count {
            let c = codes[i]
            switch c {
            case 0: self = TerminalStyle()
            case 1: bold = true
            case 4: underline = true
            case 7: inverse = true
            case 22: bold = false
            case 24: underline = false
            case 27: inverse = false
            case 30...37: foreground = c - 30
            case 90...97: foreground = c - 90 + 8
            case 39: foreground = nil
            case 40...47: background = c - 40
            case 100...107: background = c - 100 + 8
            case 49: background = nil
            case 38: if let v = extended() { foreground = v }
            case 48: if let v = extended() { background = v }
            default: break
            }
            i += 1
        }
    }
}
