import Foundation

/// Uložené nastavení hledání (šablona).
public struct SearchTemplate: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var masks: String
    public var excludeMasks: String
    public var text: String
    public var subdirectories: Bool
    public var hidden: Bool
    public var archives: Bool
    public var caseSensitive: Bool
    public var regex: Bool
    public var minKB: String
    public var maxKB: String
    public var days: String
    public var attributes: AttributeFilter

    public init(name: String, masks: String = "*", excludeMasks: String = "", text: String = "", subdirectories: Bool = true, hidden: Bool = false,
                archives: Bool = false, caseSensitive: Bool = false, regex: Bool = false, minKB: String = "", maxKB: String = "", days: String = "",
                attributes: AttributeFilter = .any) {
        self.name = name; self.masks = masks; self.excludeMasks = excludeMasks; self.text = text; self.subdirectories = subdirectories
        self.hidden = hidden; self.archives = archives; self.caseSensitive = caseSensitive; self.regex = regex
        self.minKB = minKB; self.maxKB = maxKB; self.days = days; self.attributes = attributes
    }

    /// Převod na kritéria hledání v daném adresáři.
    public func criteria(root: URL, now: Date = Date()) -> SearchCriteria {
        var c = SearchCriteria(root: root)
        c.masks = masks.isEmpty ? "*" : masks
        c.excludeMasks = excludeMasks
        c.text = text
        c.includeSubdirectories = subdirectories; c.includeHidden = hidden; c.searchInArchives = archives
        c.caseSensitive = caseSensitive; c.useRegex = regex; c.attributes = attributes
        if let v = Int64(minKB) { c.minSize = v * 1024 }
        if let v = Int64(maxKB) { c.maxSize = v * 1024 }
        if let d = Double(days) { c.modifiedAfter = now.addingTimeInterval(-d * 86_400) }
        return c
    }
}

// MARK: Lister: hledání v hex režimu a stránkování velkých textů

public enum HexSearch {
    /// Dotaz: "4D 5A", "0x4D5A" nebo "4d5a" (jen hex číslice sudé délky s mezerami/0x) = bajty; jinak text v UTF-8.
    public static func pattern(from query: String) -> Data? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        let compact = q.lowercased().replacingOccurrences(of: "0x", with: "").replacingOccurrences(of: " ", with: "")
        let looksHex = (q.lowercased().hasPrefix("0x") || q.contains(" ") || q.range(of: "^[0-9a-fA-F]+$", options: .regularExpression) != nil)
            && compact.count % 2 == 0 && compact.range(of: "^[0-9a-f]+$", options: .regularExpression) != nil
        if looksHex {
            var out = Data(), i = compact.startIndex
            while i < compact.endIndex { let j = compact.index(i, offsetBy: 2); out.append(UInt8(compact[i..<j], radix: 16)!); i = j }
            return out
        }
        return Data(q.utf8)
    }

    /// Posun prvního výskytu od `from` (cyklicky se vrací na začátek); nil, pokud vzor v datech není.
    public static func find(_ pattern: Data, in data: Data, from: Int) -> Int? {
        guard !pattern.isEmpty, data.count >= pattern.count else { return nil }
        let start = min(max(0, from), data.count)
        if let r = data.range(of: pattern, in: (data.startIndex + start)..<data.endIndex) { return r.lowerBound - data.startIndex }
        if let r = data.range(of: pattern, in: data.startIndex..<min(data.endIndex, data.startIndex + start + pattern.count - 1)) { return r.lowerBound - data.startIndex }
        return nil
    }
}

public enum TextPager {
    /// Rozsah části `index` o velikosti ~`size` bajtů; konec se posune na konec řádku a nerozděluje znak UTF-8.
    public static func range(in data: Data, index: Int, size: Int) -> Range<Int> {
        func boundary(_ target: Int) -> Int {
            if target >= data.count { return data.count }
            var p = target
            // nejdřív nejbližší konec řádku do 64 kB, jinak začátek znaku
            let limit = min(data.count, target + 65_536)
            var q = target
            while q < limit, data[data.startIndex + q] != 10 { q += 1 }
            if q < limit { return q + 1 }
            while p > 0, (data[data.startIndex + p] & 0xC0) == 0x80 { p -= 1 }
            return p
        }
        let start = index == 0 ? 0 : boundary(index * size)
        let end = boundary((index + 1) * size)
        return start..<max(start, end)
    }

    public static func count(of length: Int, size: Int) -> Int { max(1, (length + size - 1) / size) }
}
