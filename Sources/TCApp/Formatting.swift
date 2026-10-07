import Foundation
import TCCore

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
}
