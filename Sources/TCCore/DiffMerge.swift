import Foundation

/// Úpravy výsledku porovnání: přenos bloku rozdílů z jedné strany na druhou.
public enum DiffMerge {
    /// Bloky rozdílů: souvislé řádky, které nejsou shodné (rozsahy indexů řádků).
    public static func blocks(_ rows: [LineDiff.Row]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        var start: Int?
        for (i, r) in rows.enumerated() {
            if r.kind != .same { if start == nil { start = i } }
            else if let s = start { out.append(s..<i); start = nil }
        }
        if let s = start { out.append(s..<rows.count) }
        return out
    }

    /// Blok, do kterého patří řádek `index` (nebo nejbližší následující).
    public static func block(containing index: Int, in rows: [LineDiff.Row]) -> Range<Int>? {
        let b = blocks(rows)
        return b.first { $0.contains(index) } ?? b.first { $0.lowerBound > index }
    }

    /// Přenese blok: `toRight` zkopíruje levou stranu na pravou (řádky jen vlevo se doplní vpravo, řádky jen vpravo se vpravo odstraní).
    public static func apply(_ rows: [LineDiff.Row], block: Range<Int>, toRight: Bool) -> [LineDiff.Row] {
        var out: [LineDiff.Row] = []
        for (i, r) in rows.enumerated() {
            guard block.contains(i) else { out.append(r); continue }
            let source = toRight ? r.left : r.right
            guard let line = source else { continue }            // zdroj nemá řádek -> řádek se na cíli zruší
            out.append(LineDiff.Row(left: line, right: line, kind: .same))
        }
        return out
    }

    public static func lines(_ rows: [LineDiff.Row], right: Bool) -> [String] { rows.compactMap { right ? $0.right : $0.left } }
}

/// Porovnání binárních souborů po bajtech.
public enum BinaryDiff {
    public struct Result: Equatable, Sendable {
        public var sameSize: Bool
        public var differingBytes: Int
        /// Čísla 16bajtových řádků, ve kterých se soubory liší (omezený počet).
        public var rows: [Int]
        public var truncated: Bool
        public var identical: Bool { sameSize && differingBytes == 0 }
    }

    public static func compare(_ a: Data, _ b: Data, maxRows: Int = 2000) -> Result {
        let common = min(a.count, b.count)
        var differing = 0
        var rows: [Int] = []
        var lastRow = -1
        var truncated = false
        a.withUnsafeBytes { (pa: UnsafeRawBufferPointer) in
            b.withUnsafeBytes { (pb: UnsafeRawBufferPointer) in
                for i in 0..<common where pa[i] != pb[i] {
                    differing += 1
                    let row = i / HexDump.width
                    if row != lastRow { lastRow = row; if rows.count < maxRows { rows.append(row) } else { truncated = true } }
                }
            }
        }
        differing += abs(a.count - b.count)
        if a.count != b.count {
            let first = common / HexDump.width
            if !rows.contains(first) && rows.count < maxRows { rows.append(first) }
            let lastRowOfLonger = (max(a.count, b.count) - 1) / HexDump.width
            if lastRowOfLonger - first > 0 { truncated = truncated || lastRowOfLonger - first + rows.count > maxRows }
            var r = first + 1
            while r <= lastRowOfLonger, rows.count < maxRows { rows.append(r); r += 1 }
        }
        return Result(sameSize: a.count == b.count, differingBytes: differing, rows: rows, truncated: truncated)
    }
}
