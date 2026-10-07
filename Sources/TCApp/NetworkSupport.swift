import Foundation
import NetFS
import Security
import TCCore

/// Hesla uložených připojení v Klíčence (podle UUID připojení).
enum Keychain {
    private static let service = "cz.ok1xoe.macTC"

    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString]
    }

    static func password(for id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func set(_ password: String, for id: UUID) {
        delete(id)
        var q = query(id)
        q[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}

/// SMB a WebDAV se připojují jako systémové svazky (NetFS); panel pak pracuje s bodem připojení jako s lokálním adresářem.
enum NetworkMounts {
    struct MountError: LocalizedError { let code: Int32; var errorDescription: String? {
        "Připojení selhalo: \(String(cString: strerror(code))) (kód \(code))"
    } }

    static func mount(_ url: URL, user: String?, password: String?) async throws -> URL {
        try await Task.detached {
            var mountpoints: Unmanaged<CFArray>?
            let rc = NetFSMountURLSync(url as CFURL, nil, (user?.isEmpty == false ? user : nil) as CFString?,
                                       (password?.isEmpty == false ? password : nil) as CFString?, nil, nil, &mountpoints)
            let points = (mountpoints?.takeRetainedValue() as? [String]) ?? []
            if (rc == 0 || rc == EEXIST), let first = points.first { return URL(fileURLWithPath: first) }
            throw MountError(code: rc == 0 ? ENOENT : rc)
        }.value
    }
}
