import Foundation

public struct SyncOptions: Sendable, Equatable {
    public var recursive = true
    public var compareContent = false
    public var ignoreDate = false
    public var includeHidden = false
    public var ignoreMasks = ""
    public var timeTolerance: TimeInterval = 2
    public init() {}
}

public struct SyncItem: Identifiable, Sendable, Equatable {
    public enum State: Sendable { case same, onlyLeft, onlyRight, leftNewer, rightNewer, different }
    public var id: String { relativePath }
    public let relativePath: String
    public let left: FileEntry?
    public let right: FileEntry?
    public let state: State
}

public enum DirectoryComparer {
    public static func compare(left: URL, right: URL, options o: SyncOptions = SyncOptions(), fs: any VirtualFileSystem = LocalFileSystem(),
                               isCancelled: () -> Bool = { false }) -> [SyncItem] {
        var l: [String: FileEntry] = [:], r: [String: FileEntry] = [:]
        collect(left, base: left, o, fs, &l, isCancelled)
        collect(right, base: right, o, fs, &r, isCancelled)
        var items: [SyncItem] = []
        for rel in Set(l.keys).union(r.keys).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            if isCancelled() { break }
            switch (l[rel], r[rel]) {
            case let (a?, nil): items.append(SyncItem(relativePath: rel, left: a, right: nil, state: .onlyLeft))
            case let (nil, b?): items.append(SyncItem(relativePath: rel, left: nil, right: b, state: .onlyRight))
            case let (a?, b?): items.append(SyncItem(relativePath: rel, left: a, right: b, state: state(a, b, o)))
            default: break
            }
        }
        return items
    }

    private static func collect(_ dir: URL, base: URL, _ o: SyncOptions, _ fs: any VirtualFileSystem,
                                _ out: inout [String: FileEntry], _ isCancelled: () -> Bool) {
        guard !isCancelled(), let entries = try? fs.list(dir, includeHidden: o.includeHidden) else { return }
        for e in entries {
            if !o.ignoreMasks.isEmpty && GlobMatcher.matches(e.name, masks: o.ignoreMasks) { continue }
            if e.isDirectory && !e.isSymlink {
                if o.recursive { collect(e.url, base: base, o, fs, &out, isCancelled) }
                continue
            }
            let rel = String(e.url.path.dropFirst(base.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            out[rel] = e
        }
    }

    private static func state(_ a: FileEntry, _ b: FileEntry, _ o: SyncOptions) -> SyncItem.State {
        let dt = (a.modified ?? .distantPast).timeIntervalSince(b.modified ?? .distantPast)
        func byDate() -> SyncItem.State { abs(dt) <= o.timeTolerance ? .different : (dt > 0 ? .leftNewer : .rightNewer) }
        if a.size != b.size { return o.ignoreDate ? .different : byDate() }
        if o.compareContent { return sameContent(a.url, b.url) ? .same : byDate() }
        if o.ignoreDate || abs(dt) <= o.timeTolerance { return .same }
        return dt > 0 ? .leftNewer : .rightNewer
    }

    private static func sameContent(_ a: URL, _ b: URL) -> Bool {
        guard let fa = try? FileHandle(forReadingFrom: a), let fb = try? FileHandle(forReadingFrom: b) else { return false }
        defer { try? fa.close(); try? fb.close() }
        while true {
            let x = (try? fa.read(upToCount: 1 << 20)) ?? Data(), y = (try? fb.read(upToCount: 1 << 20)) ?? Data()
            if x != y { return false }
            if x.isEmpty { return true }
        }
    }
}

public enum SyncDirection: Sendable, CaseIterable {
    case leftToRight, rightToLeft, bothNewer, mirrorLeftToRight, mirrorRightToLeft
}

public enum SyncAction: Sendable, Equatable {
    case none, copyToRight, copyToLeft, deleteLeft, deleteRight
}

public struct PlannedSync: Identifiable, Sendable, Equatable {
    public var id: String { item.id }
    public let item: SyncItem
    public var action: SyncAction
}

public enum SyncPlanner {
    public static func plan(_ items: [SyncItem], direction: SyncDirection) -> [PlannedSync] {
        items.map { PlannedSync(item: $0, action: action(for: $0, direction)) }
    }

    static func action(for i: SyncItem, _ d: SyncDirection) -> SyncAction {
        switch i.state {
        case .same: return .none
        case .different: return .none      // stejný čas, různý obsah: nerozhoduje se automaticky
        case .onlyLeft:
            switch d { case .leftToRight, .bothNewer, .mirrorLeftToRight: return .copyToRight
                       case .mirrorRightToLeft: return .deleteLeft
                       case .rightToLeft: return .none }
        case .onlyRight:
            switch d { case .rightToLeft, .bothNewer, .mirrorRightToLeft: return .copyToLeft
                       case .mirrorLeftToRight: return .deleteRight
                       case .leftToRight: return .none }
        case .leftNewer:
            switch d { case .leftToRight, .bothNewer, .mirrorLeftToRight: return .copyToRight
                       case .rightToLeft, .mirrorRightToLeft: return .none }
        case .rightNewer:
            switch d { case .rightToLeft, .bothNewer, .mirrorRightToLeft: return .copyToLeft
                       case .leftToRight, .mirrorLeftToRight: return .none }
        }
    }

    /// Provede plán: kopie (se zachováním časů) a smazání (do koše). Chybějící nadřazené adresáře se vytvoří.
    public static func execute(_ plan: [PlannedSync], left: URL, right: URL, toTrash: Bool = true,
                               control: OperationControl = OperationControl(),
                               progress: (@Sendable (TransferProgress) -> Void)? = nil,
                               fs: any VirtualFileSystem = LocalFileSystem()) -> OperationReport {
        let ops = FileOperations(fs: fs)
        var report = OperationReport()
        var copies: [TransferItem] = [], deletes: [URL] = []
        for p in plan {
            let l = left.appendingPathComponent(p.item.relativePath), r = right.appendingPathComponent(p.item.relativePath)
            switch p.action {
            case .none: break
            case .copyToRight: copies.append(TransferItem(source: l, destination: r))
            case .copyToLeft: copies.append(TransferItem(source: r, destination: l))
            case .deleteLeft: deletes.append(l)
            case .deleteRight: deletes.append(r)
            }
        }
        for c in copies { try? fs.createDirectory(c.destination.deletingLastPathComponent()) }
        let cr = ops.perform(.copy, copies, policy: .overwrite, control: control, progress: progress)
        report.succeeded += cr.succeeded; report.failures += cr.failures; report.cancelled = cr.cancelled
        if !cr.cancelled {
            let dr = ops.delete(deletes, toTrash: toTrash, control: control)
            report.succeeded += dr.succeeded; report.failures += dr.failures; report.cancelled = dr.cancelled
        }
        return report
    }
}
