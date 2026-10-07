import CryptoKit
import Foundation

public enum ChecksumAlgorithm: String, Sendable, CaseIterable {
    case crc32 = "CRC32", md5 = "MD5", sha1 = "SHA-1", sha256 = "SHA-256", sha512 = "SHA-512"
    public var fileExtension: String {
        switch self { case .crc32: "crc"; case .md5: "md5"; case .sha1: "sha1"; case .sha256: "sha256"; case .sha512: "sha512" }
    }
}

public enum Checksum {
    /// Streamovaný hash souboru. `onBytes` hlásí přečtené bajty; vrácení `false` hledání zruší (výsledek nil).
    public static func hash(_ url: URL, _ algorithm: ChecksumAlgorithm, onBytes: (Int) -> Bool = { _ in true }) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let chunk = 1 << 20
        switch algorithm {
        case .crc32:
            var crc = CRC32()
            while let d = try? h.read(upToCount: chunk), !d.isEmpty { crc.update(d); if !onBytes(d.count) { return nil } }
            return String(format: "%08x", crc.value)
        case .md5: return run(h, Insecure.MD5(), chunk, onBytes)
        case .sha1: return run(h, Insecure.SHA1(), chunk, onBytes)
        case .sha256: return run(h, SHA256(), chunk, onBytes)
        case .sha512: return run(h, SHA512(), chunk, onBytes)
        }
    }

    public static func hash(of data: Data, _ algorithm: ChecksumAlgorithm) -> String {
        switch algorithm {
        case .crc32: var c = CRC32(); c.update(data); return String(format: "%08x", c.value)
        case .md5: return hex(Insecure.MD5.hash(data: data))
        case .sha1: return hex(Insecure.SHA1.hash(data: data))
        case .sha256: return hex(SHA256.hash(data: data))
        case .sha512: return hex(SHA512.hash(data: data))
        }
    }

    private static func run<H: HashFunction>(_ h: FileHandle, _ start: H, _ chunk: Int, _ onBytes: (Int) -> Bool) -> String? {
        var hasher = start
        while let d = try? h.read(upToCount: chunk), !d.isEmpty { hasher.update(data: d); if !onBytes(d.count) { return nil } }
        return hex(hasher.finalize())
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

public struct CRC32: Sendable {
    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    private var state: UInt32 = 0xFFFFFFFF
    public init() {}
    public mutating func update(_ data: Data) {
        for b in data { state = Self.table[Int((state ^ UInt32(b)) & 0xFF)] ^ (state >> 8) }
    }
    public var value: UInt32 { ~state }
}
