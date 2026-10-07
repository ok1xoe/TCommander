import Foundation

/// Abstrakce souborového systému. Lokální disk, archivy i síť ji budou implementovat.
public protocol VirtualFileSystem: Sendable {
    func list(_ dir: URL, includeHidden: Bool) throws -> [FileEntry]
    func stat(_ url: URL) throws -> FileEntry
    func exists(_ url: URL) -> Bool
    func createDirectory(_ url: URL) throws
    func createFile(_ url: URL) throws
    func copy(_ src: URL, to dst: URL) throws
    func move(_ src: URL, to dst: URL) throws
    func trash(_ url: URL) throws
    func remove(_ url: URL) throws
}

public struct LocalFileSystem: VirtualFileSystem {
    public init() {}

    public func list(_ dir: URL, includeHidden: Bool) throws -> [FileEntry] {
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        var result: [FileEntry] = []
        result.reserveCapacity(names.count)
        for name in names {
            let url = dir.appendingPathComponent(name)
            guard let entry = try? stat(url) else { continue }
            if !includeHidden && entry.isHidden { continue }
            result.append(entry)
        }
        return result
    }

    public func stat(_ url: URL) throws -> FileEntry {
        guard let st = sysLstat(url.path) else { throw posixError(url) }
        let isLink = (st.st_mode & S_IFMT) == S_IFLNK
        var isDir = (st.st_mode & S_IFMT) == S_IFDIR
        var size = Int64(st.st_size)
        var mtime = st.st_mtimespec
        if isLink {
            if let target = sysStat(url.path) {
                isDir = (target.st_mode & S_IFMT) == S_IFDIR
                size = Int64(target.st_size)
                mtime = target.st_mtimespec
            }
        }
        let name = url.lastPathComponent
        let hidden = name.hasPrefix(".") || (st.st_flags & UInt32(UF_HIDDEN)) != 0
        let date = Date(timeIntervalSince1970: TimeInterval(mtime.tv_sec) + TimeInterval(mtime.tv_nsec) / 1e9)
        func time(_ t: timespec) -> Date? { t.tv_sec > 0 ? Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_nsec) / 1e9) : nil }
        return FileEntry(url: url, name: name, isDirectory: isDir, isSymlink: isLink, isHidden: hidden,
                         size: isDir ? 0 : size, modified: date, permissions: UInt16(st.st_mode & 0o777),
                         created: time(st.st_birthtimespec), accessed: time(st.st_atimespec), ownerID: UInt32(st.st_uid), groupID: UInt32(st.st_gid))
    }

    public func exists(_ url: URL) -> Bool {
        sysLstat(url.path) != nil
    }

    public func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func createFile(_ url: URL) throws {
        guard !exists(url) else { throw CocoaError(.fileWriteFileExists) }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
    }

    public func copy(_ src: URL, to dst: URL) throws { try FileManager.default.copyItem(at: src, to: dst) }
    public func move(_ src: URL, to dst: URL) throws { try FileManager.default.moveItem(at: src, to: dst) }
    public func trash(_ url: URL) throws { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    public func remove(_ url: URL) throws { try FileManager.default.removeItem(at: url) }

    private func posixError(_ url: URL) -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno)), NSFilePathErrorKey: url.path])
    }
}

private func sysLstat(_ path: String) -> stat? {
    var st = stat()
    return lstat(path, &st) == 0 ? st : nil
}

private func sysStat(_ path: String) -> stat? {
    var st = stat()
    return stat(path, &st) == 0 ? st : nil
}

public enum DirectorySize {
    /// Součet velikostí všech souborů pod adresářem (symlinky se nenásledují).
    public static func compute(_ url: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                                     options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let u as URL in e {
            if let v = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), v.isRegularFile == true {
                total += Int64(v.fileSize ?? 0)
            }
        }
        return total
    }
}
