import Foundation

public struct SearchCriteria: Sendable {
    public var root: URL
    public var masks = "*"
    public var includeSubdirectories = true
    public var includeHidden = false
    public var text: String = ""
    public var caseSensitive = false
    public var useRegex = false
    public var minSize: Int64?
    public var maxSize: Int64?
    public var modifiedAfter: Date?
    public var modifiedBefore: Date?
    /// Soubory větší než tento limit se při hledání textu přeskakují.
    public var maxTextFileSize: Int64 = 512 * 1024 * 1024

    public init(root: URL) { self.root = root }
}

public struct SearchHit: Sendable, Hashable {
    public let url: URL
    public let size: Int64
    public let modified: Date?
    /// Číslo řádku a výřez prvního nalezeného textu (jen při hledání v obsahu).
    public let line: Int?
    public let snippet: String?
}

public struct FileSearch: Sendable {
    public init() {}

    /// Prochází strom synchronně; volat z pozadí. Vrací počet prohledaných souborů.
    @discardableResult
    public func run(_ c: SearchCriteria, isCancelled: @Sendable () -> Bool = { false },
                    onHit: @Sendable (SearchHit) -> Void) -> Int {
        let fs = LocalFileSystem()
        var scanned = 0
        let regex = makeRegex(c)
        var stack = [c.root]
        while let dir = stack.popLast() {
            if isCancelled() { break }
            guard let entries = try? fs.list(dir, includeHidden: c.includeHidden) else { continue }
            for e in entries {
                if isCancelled() { return scanned }
                if e.isDirectory {
                    if c.includeSubdirectories && !e.isSymlink { stack.append(e.url) }
                    continue
                }
                scanned += 1
                guard matchesAttributes(e, c) else { continue }
                if c.text.isEmpty {
                    onHit(SearchHit(url: e.url, size: e.size, modified: e.modified, line: nil, snippet: nil))
                } else if let m = findText(in: e, c, regex) {
                    onHit(SearchHit(url: e.url, size: e.size, modified: e.modified, line: m.line, snippet: m.snippet))
                }
            }
        }
        return scanned
    }

    func matchesAttributes(_ e: FileEntry, _ c: SearchCriteria) -> Bool {
        if !GlobMatcher.matches(e.name, masks: c.masks) { return false }
        if let m = c.minSize, e.size < m { return false }
        if let m = c.maxSize, e.size > m { return false }
        if let a = c.modifiedAfter, (e.modified ?? .distantPast) < a { return false }
        if let b = c.modifiedBefore, (e.modified ?? .distantFuture) > b { return false }
        return true
    }

    private func makeRegex(_ c: SearchCriteria) -> NSRegularExpression? {
        guard c.useRegex, !c.text.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: c.text, options: c.caseSensitive ? [] : [.caseInsensitive])
    }

    /// Ověří regulární výraz před spuštěním; vrátí chybovou zprávu nebo nil.
    public static func validate(_ c: SearchCriteria) -> String? {
        guard c.useRegex, !c.text.isEmpty else { return nil }
        do { _ = try NSRegularExpression(pattern: c.text); return nil } catch { return error.localizedDescription }
    }

    private func findText(in e: FileEntry, _ c: SearchCriteria, _ regex: NSRegularExpression?) -> (line: Int, snippet: String)? {
        guard e.size > 0, e.size <= c.maxTextFileSize,
              let data = try? Data(contentsOf: e.url, options: .alwaysMapped) else { return nil }
        if ListerSupport.looksBinary(data) && regex == nil {
            // binární soubor: hledání bajtů UTF-8 řetězce
            let needle = Data(c.text.utf8)
            guard !c.caseSensitive || true, data.range(of: needle) != nil else { return nil }
            return (0, "(binární shoda)")
        }
        let text = TextDecoding.decode(data).text
        var lineNo = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNo += 1
            let line = String(raw)
            let hit: Bool
            if let regex { hit = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil }
            else { hit = line.range(of: c.text, options: c.caseSensitive ? [] : [.caseInsensitive, .diacriticInsensitive]) != nil }
            if hit { return (lineNo, String(line.trimmingCharacters(in: .whitespaces).prefix(160))) }
        }
        return nil
    }
}
