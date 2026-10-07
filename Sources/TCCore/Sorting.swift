import Foundation

public enum SortKey: String, Sendable, CaseIterable { case name, ext, size, date }

public struct SortDescriptor: Equatable, Sendable {
    public var key: SortKey
    public var ascending: Bool
    public init(key: SortKey = .name, ascending: Bool = true) { self.key = key; self.ascending = ascending }
}

/// Adresáře vždy první, uvnitř skupin dle klíče; shoda se rozhoduje názvem.
public func sortEntries(_ entries: [FileEntry], by d: SortDescriptor) -> [FileEntry] {
    func byName(_ a: FileEntry, _ b: FileEntry) -> ComparisonResult { a.name.localizedStandardCompare(b.name) }
    func compare(_ a: FileEntry, _ b: FileEntry) -> ComparisonResult {
        switch d.key {
        case .name: return byName(a, b)
        case .ext:
            let r = a.ext.localizedStandardCompare(b.ext)
            return r == .orderedSame ? byName(a, b) : r
        case .size:
            if a.size == b.size { return byName(a, b) }
            return a.size < b.size ? .orderedAscending : .orderedDescending
        case .date:
            let x = a.modified ?? .distantPast, y = b.modified ?? .distantPast
            if x == y { return byName(a, b) }
            return x < y ? .orderedAscending : .orderedDescending
        }
    }
    return entries.sorted { a, b in
        if a.isDirectory != b.isDirectory { return a.isDirectory }
        if a.isDirectory && d.key != .name && d.key != .date { return byName(a, b) == .orderedAscending }
        let r = compare(a, b)
        return d.ascending ? r == .orderedAscending : r == .orderedDescending
    }
}
