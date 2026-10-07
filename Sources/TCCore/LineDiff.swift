import Foundation

public enum DiffOp: Equatable, Sendable {
    case equal(a: Int, b: Int)
    case delete(a: Int)
    case insert(b: Int)
}

/// Řádkový diff (Myers, O(ND)) se zkrácením společného začátku a konce.
public enum LineDiff {
    /// Vrací nil, pokud je počet rozdílů větší než `maxEdits` (soubory jsou příliš odlišné).
    public static func diff(_ a: [String], _ b: [String], maxEdits: Int = 20_000) -> [DiffOp]? {
        var pre = 0
        while pre < a.count, pre < b.count, a[pre] == b[pre] { pre += 1 }
        var suf = 0
        while suf < a.count - pre, suf < b.count - pre, a[a.count - 1 - suf] == b[b.count - 1 - suf] { suf += 1 }
        let A = Array(a[pre..<(a.count - suf)]), B = Array(b[pre..<(b.count - suf)])
        guard let mid = myers(A, B, maxEdits: maxEdits) else { return nil }
        var ops: [DiffOp] = (0..<pre).map { .equal(a: $0, b: $0) }
        ops += mid.map { op in
            switch op {
            case .equal(let x, let y): return .equal(a: x + pre, b: y + pre)
            case .delete(let x): return .delete(a: x + pre)
            case .insert(let y): return .insert(b: y + pre)
            }
        }
        for i in 0..<suf { ops.append(.equal(a: a.count - suf + i, b: b.count - suf + i)) }
        return ops
    }

    private static func myers(_ A: [String], _ B: [String], maxEdits: Int) -> [DiffOp]? {
        let n = A.count, m = B.count
        if n == 0 { return (0..<m).map { .insert(b: $0) } }
        if m == 0 { return (0..<n).map { .delete(a: $0) } }
        let maxD = min(n + m, maxEdits)
        let off = maxD + 1
        var v = [Int](repeating: 0, count: 2 * maxD + 3)
        var trace: [[Int]] = []
        var found = false
        outer: for d in 0...maxD {
            for k in stride(from: -d, through: d, by: 2) {
                var x: Int
                if k == -d || (k != d && v[off + k - 1] < v[off + k + 1]) { x = v[off + k + 1] } else { x = v[off + k - 1] + 1 }
                var y = x - k
                while x < n, y < m, A[x] == B[y] { x += 1; y += 1 }
                v[off + k] = x
                if x >= n && y >= m { trace.append(Array(v[(off - d)...(off + d)])); found = true; break outer }
            }
            trace.append(Array(v[(off - d)...(off + d)]))
        }
        guard found else { return nil }
        var ops: [DiffOp] = []
        var x = n, y = m
        for d in stride(from: trace.count - 1, through: 1, by: -1) {
            let prev = trace[d - 1], po = d - 1
            let k = x - y
            let prevK = (k == -d || (k != d && prev[k - 1 + po] < prev[k + 1 + po])) ? k + 1 : k - 1
            let prevX = prev[prevK + po], prevY = prevX - prevK
            while x > prevX && y > prevY { ops.append(.equal(a: x - 1, b: y - 1)); x -= 1; y -= 1 }
            if x == prevX { ops.append(.insert(b: y - 1)); y -= 1 } else { ops.append(.delete(a: x - 1)); x -= 1 }
        }
        while x > 0 && y > 0 { ops.append(.equal(a: x - 1, b: y - 1)); x -= 1; y -= 1 }
        return ops.reversed()
    }

    /// Zarovnané řádky pro zobrazení vedle sebe; sousední smazání+vložení se spárují jako změna.
    public struct Row: Equatable, Sendable {
        public enum Kind: Sendable { case same, changed, onlyLeft, onlyRight }
        public let left: String?
        public let right: String?
        public let kind: Kind
    }

    public static func sideBySide(_ a: [String], _ b: [String], _ ops: [DiffOp]) -> [Row] {
        var rows: [Row] = []
        var i = 0
        while i < ops.count {
            if case .equal(let x, _) = ops[i] { rows.append(Row(left: a[x], right: a[x], kind: .same)); i += 1; continue }
            var dels: [String] = [], ins: [String] = []
            while i < ops.count {
                if case .delete(let x) = ops[i] { dels.append(a[x]) }
                else if case .insert(let y) = ops[i] { ins.append(b[y]) }
                else { break }
                i += 1
            }
            for j in 0..<max(dels.count, ins.count) {
                let l = j < dels.count ? dels[j] : nil, r = j < ins.count ? ins[j] : nil
                rows.append(Row(left: l, right: r, kind: l != nil && r != nil ? .changed : (l != nil ? .onlyLeft : .onlyRight)))
            }
        }
        return rows
    }
}
