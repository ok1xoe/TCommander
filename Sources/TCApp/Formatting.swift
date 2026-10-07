import Foundation
import TCCore
import UniformTypeIdentifiers

enum Fmt {
    static let number: NumberFormatter = {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = " "; f.usesGroupingSeparator = true; return f
    }()
    static let date: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy HH:mm"; return f
    }()

    static func bytes(_ n: Int64) -> String { number.string(from: NSNumber(value: n)) ?? "\(n)" }

    static func human(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func size(of e: FileEntry, dirSize: Int64?) -> String {
        if e.isParentLink { return "" }
        if e.isDirectory { return dirSize.map(bytes) ?? "<DIR>" }
        return bytes(e.size)
    }

    static func date(_ d: Date?) -> String { d.map { date.string(from: $0) } ?? "" }

    nonisolated(unsafe) private static var kindCache: [String: String] = [:]
    nonisolated(unsafe) private static var ownerCache: [UInt32: String] = [:]

    /// Druh souboru podle přípony (např. "Dokument PDF").
    static func kind(of e: FileEntry) -> String {
        if e.isDirectory { return e.url.pathExtension == "app" ? "Aplikace" : "Složka" }
        if e.isSymlink { return "Alias" }
        let ext = e.ext.lowercased()
        if let k = kindCache[ext] { return k }
        let k = (ext.isEmpty ? nil : UTType(filenameExtension: ext)?.localizedDescription) ?? (ext.isEmpty ? "Soubor" : "Soubor \(ext.uppercased())")
        kindCache[ext] = k
        return k
    }

    static func owner(_ uid: UInt32?) -> String {
        guard let uid else { return "" }
        if let n = ownerCache[uid] { return n }
        let n = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? String(uid)
        ownerCache[uid] = n
        return n
    }
}
