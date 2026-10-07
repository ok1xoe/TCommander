import Foundation
import Observation

public struct HotlistEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: String { path }
    public var name: String
    public var path: String
    public init(name: String, path: String) { self.name = name; self.path = path }
}

/// Oblíbené adresáře (Directory hotlist), uložené jako JSON.
@MainActor @Observable
public final class Hotlist {
    public private(set) var entries: [HotlistEntry] = []
    @ObservationIgnored private let file: URL?

    public init(file: URL? = nil) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file), let e = try? JSONDecoder().decode([HotlistEntry].self, from: data) { entries = e }
    }

    public static func defaultFile() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("macTC")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hotlist.json")
    }

    public func contains(_ url: URL) -> Bool { entries.contains { $0.path == url.standardizedFileURL.path } }

    public func add(_ url: URL, name: String? = nil) {
        let path = url.standardizedFileURL.path
        guard !contains(url) else { return }
        entries.append(HotlistEntry(name: name ?? (path == "/" ? "/" : url.lastPathComponent), path: path))
        save()
    }

    public func remove(_ entry: HotlistEntry) { entries.removeAll { $0 == entry }; save() }

    public func move(from: Int, to: Int) {
        guard entries.indices.contains(from), entries.indices.contains(to) else { return }
        entries.insert(entries.remove(at: from), at: to); save()
    }

    private func save() {
        guard let file, let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
