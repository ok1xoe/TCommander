import Foundation

public struct FileEntry: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let isHidden: Bool
    public let size: Int64
    public let modified: Date?
    public let permissions: UInt16
    public let isParentLink: Bool
    public let created: Date?
    public let accessed: Date?
    /// Číslo uživatele (uid) vlastníka; jméno se zjišťuje až při zobrazení.
    public let ownerID: UInt32?
    public let groupID: UInt32?

    public init(url: URL, name: String, isDirectory: Bool, isSymlink: Bool = false, isHidden: Bool = false,
                size: Int64 = 0, modified: Date? = nil, permissions: UInt16 = 0, isParentLink: Bool = false,
                created: Date? = nil, accessed: Date? = nil, ownerID: UInt32? = nil, groupID: UInt32? = nil) {
        self.created = created; self.accessed = accessed; self.ownerID = ownerID; self.groupID = groupID
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.isHidden = isHidden
        self.size = size
        self.modified = modified
        self.permissions = permissions
        self.isParentLink = isParentLink
    }

    /// Přípona bez tečky; adresáře a ".." ji nemají.
    public var ext: String {
        guard !isDirectory, !isParentLink else { return "" }
        return (name as NSString).pathExtension
    }

    /// Název bez přípony (u adresářů celý název).
    public var baseName: String {
        guard !isDirectory, !isParentLink, !ext.isEmpty else { return name }
        return (name as NSString).deletingPathExtension
    }

    public static func parent(of dir: URL) -> FileEntry {
        FileEntry(url: dir.deletingLastPathComponent(), name: "..", isDirectory: true, isParentLink: true)
    }

    /// "rwxr-xr-x"
    public var permissionString: String {
        let p = permissions
        let chars = Array("rwxrwxrwx")
        var out = ""
        for i in 0..<9 { out.append(p & (1 << UInt16(8 - i)) != 0 ? chars[i] : "-") }
        return out
    }
}
