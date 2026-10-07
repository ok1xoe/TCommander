import Foundation

public struct DuplicateGroup: Identifiable, Sendable, Equatable {
    public var id: String { hash }
    public let hash: String
    public let size: Int64
    public let files: [URL]
}

public enum DuplicateFinder {
    /// Duplicity podle velikosti a následně obsahu (rychlý hash prvních 64 kB, potom SHA-256 celého souboru).
    public static func find(in root: URL, includeHidden: Bool = false, minSize: Int64 = 1,
                            isCancelled: () -> Bool = { false }, fs: any VirtualFileSystem = LocalFileSystem()) -> [DuplicateGroup] {
        var bySize: [Int64: [URL]] = [:]
        var stack = [root]
        while let dir = stack.popLast() {
            if isCancelled() { return [] }
            for e in (try? fs.list(dir, includeHidden: includeHidden)) ?? [] {
                if e.isDirectory { if !e.isSymlink { stack.append(e.url) }; continue }
                if e.isSymlink || e.size < minSize { continue }
                bySize[e.size, default: []].append(e.url)
            }
        }
        var groups: [DuplicateGroup] = []
        for (size, urls) in bySize where urls.count > 1 {
            var quick: [String: [URL]] = [:]
            for u in urls {
                if isCancelled() { return [] }
                if let h = headHash(u) { quick[h, default: []].append(u) }
            }
            for (_, candidates) in quick where candidates.count > 1 {
                var full: [String: [URL]] = [:]
                for u in candidates {
                    if isCancelled() { return [] }
                    if let h = Checksum.hash(u, .sha256) { full[h, default: []].append(u) }
                }
                for (h, files) in full where files.count > 1 {
                    groups.append(DuplicateGroup(hash: h, size: size, files: files.sorted { $0.path < $1.path }))
                }
            }
        }
        return groups.sorted { $0.size != $1.size ? $0.size > $1.size : $0.files[0].path < $1.files[0].path }
    }

    private static func headHash(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: 65_536) else { return nil }
        return Checksum.hash(of: d, .md5)
    }
}
