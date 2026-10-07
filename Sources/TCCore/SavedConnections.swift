import Foundation
import Observation

/// Uložené připojení k serveru (heslo se ukládá zvlášť, do Klíčenky podle `id`).
public struct SavedConnection: Codable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case ftp = "FTP", ftpExplicitTLS = "FTP + explicitní TLS", ftpsImplicit = "FTPS (implicitní TLS)",
             sftp = "SFTP", smb = "SMB (sdílená složka)", webdav = "WebDAV (http)", webdavs = "WebDAV (https)"

        public var defaultPort: Int? {
            switch self { case .ftp, .ftpExplicitTLS: 21; case .ftpsImplicit: 990; case .sftp: 22; case .smb: 445; case .webdav: 80; case .webdavs: 443 }
        }
        /// Připojení přes FTP klienta v aplikaci (ostatní typy se připojují jako svazek nebo přes SFTP).
        public var isFTP: Bool { self == .ftp || self == .ftpExplicitTLS || self == .ftpsImplicit }
        public var isMount: Bool { self == .smb || self == .webdav || self == .webdavs }
    }

    public var id: UUID
    public var name: String
    public var kind: Kind
    public var host: String
    public var port: Int?
    public var user: String
    public var path: String
    public var allowSelfSigned: Bool
    /// Soubor soukromého klíče pro SFTP (prázdné = výchozí klíče a ssh-agent).
    public var identityFile: String
    /// Proxy pro FTP, např. socks5h://127.0.0.1:1080.
    public var proxy: String

    public init(id: UUID = UUID(), name: String, kind: Kind, host: String, port: Int? = nil, user: String = "",
                path: String = "/", allowSelfSigned: Bool = false, identityFile: String = "", proxy: String = "") {
        self.id = id; self.name = name; self.kind = kind; self.host = host; self.port = port
        self.user = user; self.path = path; self.allowSelfSigned = allowSelfSigned
        self.identityFile = identityFile; self.proxy = proxy
    }

    // starší uložené soubory nová pole neobsahují
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(Kind.self, forKey: .kind); host = try c.decode(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port); user = try c.decode(String.self, forKey: .user)
        path = try c.decode(String.self, forKey: .path); allowSelfSigned = try c.decode(Bool.self, forKey: .allowSelfSigned)
        identityFile = try c.decodeIfPresent(String.self, forKey: .identityFile) ?? ""
        proxy = try c.decodeIfPresent(String.self, forKey: .proxy) ?? ""
    }

    public func ftpConnection(password: String) -> RemoteConnection {
        RemoteConnection(host: host, port: port, user: user.isEmpty ? "anonymous" : user,
                         password: user.isEmpty ? "anonymous@" : password,
                         security: kind == .ftpsImplicit ? .implicitTLS : (kind == .ftpExplicitTLS ? .explicitTLS : .none),
                         allowSelfSigned: allowSelfSigned, initialPath: path.isEmpty ? "/" : path, proxy: proxy)
    }

    public func sftpConnection(password: String) -> SFTPConnection {
        SFTPConnection(host: host, port: port, user: user.isEmpty ? NSUserName() : user, password: password,
                       identityFile: (identityFile as NSString).expandingTildeInPath, initialPath: path)
    }

    /// URL pro připojení svazku (SMB, WebDAV); heslo se nikdy nevkládá do URL.
    public func mountURL() -> URL? {
        var c = URLComponents()
        switch kind {
        case .smb: c.scheme = "smb"
        case .webdav: c.scheme = "http"
        case .webdavs: c.scheme = "https"
        default: return nil
        }
        c.host = host
        if let port, port != kind.defaultPort { c.port = port }
        if !user.isEmpty { c.user = user }
        let p = path.hasPrefix("/") ? path : "/" + path
        c.path = p == "/" ? "" : p
        return c.url
    }
}

@MainActor @Observable
public final class SavedConnections {
    public private(set) var items: [SavedConnection] = []
    @ObservationIgnored private let file: URL?

    public init(file: URL? = nil) {
        self.file = file
        if let file, let d = try? Data(contentsOf: file), let v = try? JSONDecoder().decode([SavedConnection].self, from: d) { items = v }
    }

    public static func defaultFile() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("macTC")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("connections.json")
    }

    public func upsert(_ c: SavedConnection) {
        if let i = items.firstIndex(where: { $0.id == c.id }) { items[i] = c } else { items.append(c) }
        save()
    }

    public func remove(_ c: SavedConnection) { items.removeAll { $0.id == c.id }; save() }

    private func save() {
        guard let file, let d = try? JSONEncoder().encode(items) else { return }
        try? d.write(to: file, options: .atomic)
    }
}
