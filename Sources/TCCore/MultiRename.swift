import Foundation

public enum CaseMode: String, Sendable, CaseIterable, Codable {
    case unchanged, lower, upper, firstUpper, eachWord
}

public struct RenameOptions: Sendable, Equatable, Codable {
    public var nameMask = "[N]"
    public var extMask = "[E]"
    public var search = ""
    public var replace = ""
    public var useRegex = false
    public var caseSensitive = false
    public var caseMode = CaseMode.unchanged
    public var counterStart = 1
    public var counterStep = 1
    public var counterDigits = 1
    public init() {}
}

public struct RenamePreview: Sendable, Equatable {
    public enum Problem: Sendable, Equatable { case empty, invalidCharacter, duplicate, existsOnDisk }
    public let source: URL
    public let newName: String
    public var problem: Problem?
    public init(source: URL, newName: String, problem: Problem? = nil) { self.source = source; self.newName = newName; self.problem = problem }
    public var changed: Bool { newName != source.lastPathComponent }
}

public enum RenameEngine {
    // MARK: Náhled

    /// Vypočítá nové názvy; pořadí vstupu určuje číslování `[C]`.
    public static func preview(_ files: [URL], _ o: RenameOptions, fs: any VirtualFileSystem = LocalFileSystem()) -> [RenamePreview] {
        var result: [RenamePreview] = files.enumerated().map { i, url in
            let full = url.lastPathComponent
            let ext = (full as NSString).pathExtension
            let base = ext.isEmpty ? full : (full as NSString).deletingPathExtension
            let date = (try? fs.stat(url))?.modified ?? Date()
            let ctx = Context(base: base, ext: ext, index: i, parent: url.deletingLastPathComponent().lastPathComponent, date: date, o: o)
            var name = expand(o.nameMask, ctx)
            var newExt = expand(o.extMask, ctx)
            name = replace(name, o); newExt = replace(newExt, o)
            name = apply(o.caseMode, name); newExt = apply(o.caseMode, newExt)
            let combined = newExt.isEmpty ? name : name + "." + newExt
            return RenamePreview(source: url, newName: combined, problem: nil)
        }
        // kontrola problémů
        let sources = Set(files.map { $0.standardizedFileURL.path })
        var counts: [String: Int] = [:]
        for r in result { counts[r.source.deletingLastPathComponent().appendingPathComponent(r.newName).path, default: 0] += 1 }
        for i in result.indices {
            let r = result[i]
            let target = r.source.deletingLastPathComponent().appendingPathComponent(r.newName)
            if r.newName.isEmpty || r.newName == "." || r.newName == ".." { result[i].problem = .empty }
            else if r.newName.contains("/") || r.newName.contains(":") { result[i].problem = .invalidCharacter }
            else if counts[target.path, default: 0] > 1 { result[i].problem = .duplicate }
            else if r.changed, fs.exists(target), !sources.contains(target.standardizedFileURL.path) { result[i].problem = .existsOnDisk }
        }
        return result
    }

    private struct Context {
        let base: String, ext: String, index: Int, parent: String, date: Date, o: RenameOptions
    }

    private static func expand(_ mask: String, _ c: Context) -> String {
        var out = ""
        var i = mask.startIndex
        while i < mask.endIndex {
            let ch = mask[i]
            if ch == "[", let close = mask[i...].firstIndex(of: "]") {
                let token = String(mask[mask.index(after: i)..<close])
                if let v = value(for: token, c) { out += v; i = mask.index(after: close); continue }
            }
            out.append(ch); i = mask.index(after: i)
        }
        return out
    }

    private static func value(for token: String, _ c: Context) -> String? {
        guard let first = token.first else { return nil }
        let rest = String(token.dropFirst())
        switch first {
        case "N": return range(c.base, rest)
        case "E": return range(c.ext, rest)
        case "P": return range(c.parent, rest)
        case "C": return counter(rest, c)
        case "Y": return rest.isEmpty ? date(c.date, "yyyy") : nil
        case "y": return rest.isEmpty ? date(c.date, "yy") : nil
        case "M": return rest.isEmpty ? date(c.date, "MM") : nil
        case "D": return rest.isEmpty ? date(c.date, "dd") : nil
        case "h": return rest.isEmpty ? date(c.date, "HH") : nil
        case "m": return rest.isEmpty ? date(c.date, "mm") : nil
        case "s": return rest.isEmpty ? date(c.date, "ss") : nil
        case "d": return rest.isEmpty ? date(c.date, "yyyy-MM-dd") : nil
        case "t": return rest.isEmpty ? date(c.date, "HH.mm.ss") : nil
        default: return nil
        }
    }

    private static func date(_ d: Date, _ f: String) -> String {
        let df = DateFormatter(); df.dateFormat = f; df.locale = Locale(identifier: "en_US_POSIX"); return df.string(from: d)
    }

    /// "", "3-5", "3-", "3,2" (od znaku 3 délka 2); indexy od 1.
    private static func range(_ s: String, _ spec: String) -> String? {
        if spec.isEmpty { return s }
        let chars = Array(s)
        func int(_ x: Substring) -> Int? { Int(x) }
        if let comma = spec.firstIndex(of: ",") {
            guard let a = int(spec[..<comma]), let len = int(spec[spec.index(after: comma)...]), a >= 1 else { return nil }
            guard a <= chars.count else { return "" }
            return String(chars[(a - 1)..<min(chars.count, a - 1 + len)])
        }
        if let dash = spec.firstIndex(of: "-") {
            let a = int(spec[..<dash]) ?? 1
            let bs = spec[spec.index(after: dash)...]
            guard a >= 1, bs.isEmpty || int(bs) != nil else { return nil }
            let b = bs.isEmpty ? chars.count : min(chars.count, int(bs)!)
            guard a <= b else { return "" }
            return String(chars[(a - 1)..<b])
        }
        guard let n = int(Substring(spec)), n >= 1 else { return nil }
        return n <= chars.count ? String(chars[n - 1]) : ""
    }

    /// `[C]` podle nastavení, nebo `[C10+5:3]` (začátek 10, krok 5, 3 číslice).
    private static func counter(_ spec: String, _ c: Context) -> String? {
        var start = c.o.counterStart, step = c.o.counterStep, digits = c.o.counterDigits
        if !spec.isEmpty {
            let digitPart = spec.split(separator: ":", omittingEmptySubsequences: false)
            if digitPart.count == 2 { guard let d = Int(digitPart[1]) else { return nil }; digits = d }
            let main = digitPart[0]
            let sp = main.split(separator: "+", omittingEmptySubsequences: false)
            if sp.count == 2 { guard let st = Int(sp[1]) else { return nil }; step = st }
            if !sp[0].isEmpty { guard let s = Int(sp[0]) else { return nil }; start = s }
        }
        return String(format: "%0\(max(1, digits))d", start + c.index * step)
    }

    private static func replace(_ s: String, _ o: RenameOptions) -> String {
        guard !o.search.isEmpty else { return s }
        if o.useRegex {
            guard let re = try? NSRegularExpression(pattern: o.search, options: o.caseSensitive ? [] : [.caseInsensitive]) else { return s }
            return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: o.replace)
        }
        return s.replacingOccurrences(of: o.search, with: o.replace, options: o.caseSensitive ? [] : [.caseInsensitive])
    }

    private static func apply(_ mode: CaseMode, _ s: String) -> String {
        switch mode {
        case .unchanged: return s
        case .lower: return s.lowercased()
        case .upper: return s.uppercased()
        case .firstUpper: return s.prefix(1).uppercased() + s.dropFirst().lowercased()
        case .eachWord:
            var out = "", startOfWord = true
            for ch in s {
                out += startOfWord ? ch.uppercased() : ch.lowercased()
                startOfWord = !(ch.isLetter || ch.isNumber)
            }
            return out
        }
    }

    public static func validateRegex(_ o: RenameOptions) -> String? {
        guard o.useRegex, !o.search.isEmpty else { return nil }
        do { _ = try NSRegularExpression(pattern: o.search); return nil } catch { return error.localizedDescription }
    }

    // MARK: Provedení a vrácení zpět

    public struct Applied: Sendable { public let from: URL; public let to: URL }

    /// Přejmenuje přes dočasné názvy (kvůli záměnám a řetězům); při chybě vrátí vše zpět.
    public static func apply(_ previews: [RenamePreview], fs: any VirtualFileSystem = LocalFileSystem()) throws -> [Applied] {
        let work = previews.filter { $0.changed && $0.problem == nil }
        var stage1: [(from: URL, tmp: URL, to: URL)] = []
        var done: [(from: URL, tmp: URL, to: URL)] = []
        do {
            for w in work {
                let dir = w.source.deletingLastPathComponent()
                let tmp = dir.appendingPathComponent(".macTC-rename-\(UUID().uuidString)")
                try fs.move(w.source, to: tmp)
                stage1.append((w.source, tmp, dir.appendingPathComponent(w.newName)))
            }
            for s in stage1 {
                if fs.exists(s.to) { throw CocoaError(.fileWriteFileExists) }
                try fs.move(s.tmp, to: s.to)
                done.append(s)
            }
        } catch {
            for s in done.reversed() { try? fs.move(s.to, to: s.tmp) }
            for s in stage1.reversed() { try? fs.move(s.tmp, to: s.from) }
            throw error
        }
        return done.map { Applied(from: $0.from, to: $0.to) }
    }

    public static func undo(_ applied: [Applied], fs: any VirtualFileSystem = LocalFileSystem()) throws {
        let previews = applied.map { RenamePreview(source: $0.to, newName: $0.from.lastPathComponent, problem: nil) }
        _ = try apply(previews, fs: fs)
    }
}
