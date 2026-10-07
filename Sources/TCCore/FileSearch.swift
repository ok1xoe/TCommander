import CArchive
import Foundation

public struct SearchCriteria: Sendable {
    public var root: URL
    public var masks = "*"
    public var includeSubdirectories = true
    public var includeHidden = false
    /// Prohledávat i uvnitř archivů (zip, tar.*, 7z, rar …).
    public var searchInArchives = false
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
    /// Cesta uvnitř archivu (`url` je pak soubor archivu).
    public let inner: String?

    public init(url: URL, size: Int64, modified: Date?, line: Int?, snippet: String?, inner: String? = nil) {
        self.url = url; self.size = size; self.modified = modified; self.line = line; self.snippet = snippet; self.inner = inner
    }
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
                if c.searchInArchives && ArchiveSupport.isArchive(e.name) { scanned += searchArchive(e.url, c, regex, isCancelled, onHit) }
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

    /// Prohledá záznamy archivu; vrací počet prohledaných souborů v něm.
    private func searchArchive(_ url: URL, _ c: SearchCriteria, _ regex: NSRegularExpression?,
                               _ isCancelled: () -> Bool, _ onHit: (SearchHit) -> Void) -> Int {
        var count = 0
        try? ArchiveFileSystem.read(url) { a, entry in
            if isCancelled() { return false }
            guard let cp = archive_entry_pathname(entry) else { return true }
            let path = ArchiveSupport.normalize(String(cString: cp))
            guard !path.isEmpty, Int32(archive_entry_filetype(entry)) != CARCHIVE_IFDIR, Int32(archive_entry_filetype(entry)) != CARCHIVE_IFLNK else { return true }
            let name = (path as NSString).lastPathComponent
            if !c.includeHidden && path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { return true }
            count += 1
            let size = archive_entry_size_is_set(entry) != 0 ? archive_entry_size(entry) : 0
            let mt = archive_entry_mtime(entry)
            let date = mt > 0 ? Date(timeIntervalSince1970: TimeInterval(mt)) : nil
            let fake = FileEntry(url: url, name: name, isDirectory: false, size: size, modified: date)
            guard matchesAttributes(fake, c) else { return true }
            if c.text.isEmpty { onHit(SearchHit(url: url, size: size, modified: date, line: nil, snippet: nil, inner: path)); return true }
            guard size > 0, size <= min(c.maxTextFileSize, 64 * 1024 * 1024) else { return true }
            var data = Data(capacity: Int(size))
            let bufSize = 1 << 16
            let buf = UnsafeMutableRawPointer.allocate(byteCount: bufSize, alignment: 16)
            defer { buf.deallocate() }
            while true {
                let n = archive_read_data(a, buf, bufSize)
                if n <= 0 { break }
                data.append(Data(bytes: buf, count: n))
            }
            if let m = matchText(in: data, c, regex) {
                onHit(SearchHit(url: url, size: size, modified: date, line: m.line, snippet: m.snippet, inner: path))
            }
            return true
        }
        return count
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
        return matchText(in: data, c, regex)
    }

    private func matchText(in data: Data, _ c: SearchCriteria, _ regex: NSRegularExpression?) -> (line: Int, snippet: String)? {
        if ListerSupport.looksBinary(data) && regex == nil {
            // binární data: hledání bajtů UTF-8 řetězce
            guard data.range(of: Data(c.text.utf8)) != nil else { return nil }
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
