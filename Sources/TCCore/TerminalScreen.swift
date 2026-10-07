import Foundation

/// Obrazovka s mřížkou buněk pro celoobrazovkové programy (vim, top, htop, less, mc…) – „alternativní obrazovka“ terminálu.
struct TerminalScreen {
    struct Cell: Equatable { var ch: Character = " "; var style = TerminalStyle() }

    private(set) var rows: Int, cols: Int
    private(set) var cells: [[Cell]]
    private(set) var row = 0, col = 0
    private var top = 0, bottom: Int
    private var saved = (row: 0, col: 0, style: TerminalStyle())
    private var wrapPending = false
    var style = TerminalStyle()
    var cursorVisible = true

    init(rows: Int, cols: Int) {
        self.rows = max(1, rows); self.cols = max(1, cols)
        bottom = self.rows - 1
        cells = Array(repeating: Array(repeating: Cell(), count: self.cols), count: self.rows)
    }

    var cursor: (row: Int, col: Int) { (row, col) }

    private func blank() -> Cell { Cell(ch: " ", style: TerminalStyle(background: style.background)) }
    private func blankLine() -> [Cell] { Array(repeating: blank(), count: cols) }

    /// Změna velikosti: obsah se ořízne nebo doplní prázdnými buňkami, kurzor zůstane v mezích.
    mutating func resize(rows newRows: Int, cols newCols: Int) {
        let r = max(1, newRows), c = max(1, newCols)
        guard r != rows || c != cols else { return }
        var out = cells.map { line -> [Cell] in
            line.count >= c ? Array(line.prefix(c)) : line + Array(repeating: Cell(), count: c - line.count)
        }
        if out.count > r { out = Array(out.suffix(r)) }
        while out.count < r { out.append(Array(repeating: Cell(), count: c)) }
        cells = out; rows = r; cols = c
        top = 0; bottom = r - 1
        row = min(row, r - 1); col = min(col, c - 1); wrapPending = false
    }

    // MARK: Znaky a řídicí znaky

    mutating func put(_ ch: Character) {
        if wrapPending { col = 0; lineFeed(); wrapPending = false }
        cells[row][col] = Cell(ch: ch, style: style)
        if col == cols - 1 { wrapPending = true } else { col += 1 }
    }

    mutating func carriageReturn() { col = 0; wrapPending = false }
    mutating func backspace() { col = max(0, col - 1); wrapPending = false }
    mutating func tab() { col = min(cols - 1, (col / 8 + 1) * 8); wrapPending = false }

    mutating func lineFeed() {
        if row == bottom { scrollUp(1) } else if row < rows - 1 { row += 1 }
        wrapPending = false
    }

    mutating func reverseIndex() {
        if row == top { scrollDown(1) } else if row > 0 { row -= 1 }
        wrapPending = false
    }

    mutating func scrollUp(_ n: Int) {
        for _ in 0..<min(max(1, n), bottom - top + 1) { cells.remove(at: top); cells.insert(blankLine(), at: bottom) }
    }

    mutating func scrollDown(_ n: Int) {
        for _ in 0..<min(max(1, n), bottom - top + 1) { cells.remove(at: bottom); cells.insert(blankLine(), at: top) }
    }

    mutating func saveCursor() { saved = (row, col, style) }
    mutating func restoreCursor() { row = min(saved.row, rows - 1); col = min(saved.col, cols - 1); style = saved.style; wrapPending = false }

    mutating func fullReset() {
        self = TerminalScreen(rows: rows, cols: cols)
    }

    // MARK: CSI

    private mutating func move(toRow r: Int, col c: Int) { row = min(max(0, r), rows - 1); col = min(max(0, c), cols - 1); wrapPending = false }

    private mutating func eraseCells(row r: Int, from: Int, to: Int) {
        guard from <= to, r >= 0, r < rows else { return }
        for c in max(0, from)...min(cols - 1, to) { cells[r][c] = blank() }
    }

    /// Zpracuje řídicí sekvenci CSI (bez soukromých režimů „?“, ty řeší volající). Vrací odpověď pro program (např. pozice kurzoru).
    mutating func csi(final f: Unicode.Scalar, params: String) -> String? {
        let nums = params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) }
        func p(_ i: Int, _ def: Int) -> Int { i < nums.count ? (nums[i].flatMap { $0 == 0 ? def : $0 } ?? def) : def }
        let n = p(0, 1)
        switch f {
        case "A": move(toRow: row - n, col: col)
        case "B", "e": move(toRow: row + n, col: col)
        case "C", "a": move(toRow: row, col: col + n)
        case "D": move(toRow: row, col: col - n)
        case "E": move(toRow: row + n, col: 0)
        case "F": move(toRow: row - n, col: 0)
        case "G", "`": move(toRow: row, col: n - 1)
        case "d": move(toRow: n - 1, col: col)
        case "H", "f": move(toRow: p(0, 1) - 1, col: p(1, 1) - 1)
        case "J":
            switch nums.first.flatMap({ $0 }) ?? 0 {
            case 0: eraseCells(row: row, from: col, to: cols - 1); if row + 1 < rows { for r in (row + 1)..<rows { eraseCells(row: r, from: 0, to: cols - 1) } }
            case 1: for r in 0..<row { eraseCells(row: r, from: 0, to: cols - 1) }; eraseCells(row: row, from: 0, to: col)
            default: for r in 0..<rows { eraseCells(row: r, from: 0, to: cols - 1) }
            }
        case "K":
            switch nums.first.flatMap({ $0 }) ?? 0 {
            case 0: eraseCells(row: row, from: col, to: cols - 1)
            case 1: eraseCells(row: row, from: 0, to: col)
            default: eraseCells(row: row, from: 0, to: cols - 1)
            }
        case "L":
            guard row >= top, row <= bottom else { break }
            for _ in 0..<min(n, bottom - row + 1) { cells.remove(at: bottom); cells.insert(blankLine(), at: row) }
        case "M":
            guard row >= top, row <= bottom else { break }
            for _ in 0..<min(n, bottom - row + 1) { cells.remove(at: row); cells.insert(blankLine(), at: bottom) }
        case "P":
            let k = min(n, cols - col)
            cells[row].removeSubrange(col..<(col + k)); cells[row].append(contentsOf: Array(repeating: blank(), count: k))
        case "@":
            let k = min(n, cols - col)
            cells[row].insert(contentsOf: Array(repeating: blank(), count: k), at: col); cells[row].removeLast(k)
        case "X": eraseCells(row: row, from: col, to: col + n - 1)
        case "S": scrollUp(n)
        case "T": scrollDown(n)
        case "r":
            let t = p(0, 1) - 1, b = p(1, rows) - 1
            if t < b, b < rows { top = t; bottom = b } else { top = 0; bottom = rows - 1 }
            move(toRow: 0, col: 0)
        case "s": saveCursor()
        case "u": restoreCursor()
        case "m": style.apply(sgr: params)
        case "n": if p(0, 0) == 6 { return "\u{1B}[\(row + 1);\(col + 1)R" } else if p(0, 0) == 5 { return "\u{1B}[0n" }
        case "c": return params.hasPrefix(">") ? "\u{1B}[>0;95;0c" : "\u{1B}[?1;2c"
        default: break
        }
        return nil
    }

    // MARK: Výstup

    var plainLines: [String] {
        cells.map { String($0.map(\.ch)).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
    }

    /// Obsah jako souvislé úseky stejného stylu; řádky jsou oddělené „\n“. Kurzor (je-li viditelný) je vyznačen inverzně.
    func runs() -> [TerminalTextBuffer.Run] {
        var out: [TerminalTextBuffer.Run] = []
        func add(_ ch: Character, _ st: TerminalStyle) {
            if var last = out.last, last.style == st { last.text.append(ch); out[out.count - 1] = last } else { out.append(.init(text: String(ch), style: st)) }
        }
        for (r, line) in cells.enumerated() {
            for (c, cell) in line.enumerated() {
                var st = cell.style
                if cursorVisible, r == row, c == col { st.inverse.toggle() }
                add(cell.ch, st)
            }
            if r < rows - 1 { add("\n", TerminalStyle()) }
        }
        return out
    }
}
