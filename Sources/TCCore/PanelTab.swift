import Foundation
import Observation

public struct PanelSummary: Sendable, Equatable {
    public var markedCount = 0, markedBytes: Int64 = 0
    public var fileCount = 0, dirCount = 0, totalBytes: Int64 = 0
}

@MainActor @Observable
public final class PanelTab: Identifiable {
    public let id = UUID()
    public private(set) var path: URL
    public private(set) var entries: [FileEntry] = []
    public private(set) var marked: Set<URL> = []
    public private(set) var error: String?
    public private(set) var dirSizes: [URL: Int64] = [:]
    /// Zvyšuje se při každé změně viditelného stavu; UI podle něj překresluje tabulku.
    public private(set) var revision = 0
    public var cursor = 0
    public var sort = SortDescriptor() { didSet { if sort != oldValue { applyView(keeping: cursorURL) } } }
    public var showHidden = false { didSet { if showHidden != oldValue { reload() } } }
    public var quickFilter = "" { didSet { if quickFilter != oldValue { applyView(keeping: cursorURL) } } }

    @ObservationIgnored private var all: [FileEntry] = []
    @ObservationIgnored private var backStack: [URL] = []
    @ObservationIgnored private var forwardStack: [URL] = []
    @ObservationIgnored private let fs: any VirtualFileSystem

    public init(path: URL, fs: any VirtualFileSystem = LocalFileSystem(), showHidden: Bool = false) {
        self.fs = fs
        self.path = path.standardizedFileURL
        self.showHidden = showHidden
        reload()
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }
    public var cursorEntry: FileEntry? { entries.indices.contains(cursor) ? entries[cursor] : nil }
    public var cursorURL: URL? { cursorEntry?.url }

    /// Označené položky, nebo (když nic označeno není) položka pod kurzorem; ".." se nikdy nevrací.
    public var targets: [FileEntry] {
        if !marked.isEmpty { return entries.filter { marked.contains($0.url) } }
        if let e = cursorEntry, !e.isParentLink { return [e] }
        return []
    }

    public var summary: PanelSummary {
        var s = PanelSummary()
        for e in entries where !e.isParentLink {
            let size = e.isDirectory ? (dirSizes[e.url] ?? 0) : e.size
            if e.isDirectory { s.dirCount += 1 } else { s.fileCount += 1 }
            s.totalBytes += size
            if marked.contains(e.url) { s.markedCount += 1; s.markedBytes += size }
        }
        return s
    }

    // MARK: Navigace

    @discardableResult
    public func navigate(to url: URL, select: URL? = nil, recordHistory: Bool = true, keepMarks: Bool = false) -> Bool {
        let target = url.standardizedFileURL
        do {
            let items = try fs.list(target, includeHidden: showHidden)
            if recordHistory && target != path { backStack.append(path); forwardStack.removeAll() }
            if target != path && !keepMarks { marked.removeAll(); quickFilter = "" }
            path = target
            all = items
            error = nil
            applyView(keeping: select)
            return true
        } catch {
            self.error = "\(target.path): \(error.localizedDescription)"
            revision &+= 1
            return false
        }
    }

    public func goUp() {
        guard path.path != "/" else { return }
        navigate(to: path.deletingLastPathComponent(), select: path)
    }

    public func goBack() {
        guard let prev = backStack.last else { return }
        let here = path
        if navigate(to: prev, recordHistory: false) { backStack.removeLast(); forwardStack.append(here) }
    }

    public func goForward() {
        guard let next = forwardStack.last else { return }
        let here = path
        if navigate(to: next, recordHistory: false) { forwardStack.removeLast(); backStack.append(here) }
    }

    /// Znovu načte adresář; když zmizel, vyleze na nejbližší existující nadřazený.
    public func reload(select: URL? = nil) {
        var dir = path
        let keep = select ?? cursorURL
        while !navigate(to: dir, select: keep, recordHistory: false, keepMarks: true) {
            guard dir.path != "/" else { return }
            dir = dir.deletingLastPathComponent()
        }
        marked.formIntersection(Set(all.map(\.url)))
        if error == nil { revision &+= 1 }
    }

    /// Enter: adresář otevře a vrátí nil; u souboru vrátí jeho URL k otevření.
    public func activateCursor() -> URL? {
        guard let e = cursorEntry else { return nil }
        if e.isParentLink { goUp(); return nil }
        if e.isDirectory { navigate(to: e.url); return nil }
        return e.url
    }

    // MARK: Označování

    public func toggleMark(at index: Int) {
        guard entries.indices.contains(index), !entries[index].isParentLink else { return }
        let u = entries[index].url
        if marked.contains(u) { marked.remove(u) } else { marked.insert(u) }
        revision &+= 1
    }

    /// Insert / mezerník: označí a posune kurzor dolů.
    public func toggleMarkAndAdvance() {
        toggleMark(at: cursor)
        moveCursor(to: min(cursor + 1, entries.count - 1))
    }

    public func markAll() {
        marked = Set(entries.filter { !$0.isParentLink }.map(\.url)); revision &+= 1
    }
    public func unmarkAll() { marked.removeAll(); revision &+= 1 }
    public func invertMarks() {
        let all = Set(entries.filter { !$0.isParentLink }.map(\.url))
        marked = all.subtracting(marked); revision &+= 1
    }

    /// Num+ / Num−: označí/odznačí soubory podle masky (adresáře ne).
    public func mark(matching masks: String, on: Bool) {
        for e in entries where !e.isParentLink && !e.isDirectory && GlobMatcher.matches(e.name, masks: masks) {
            if on { marked.insert(e.url) } else { marked.remove(e.url) }
        }
        revision &+= 1
    }

    public func moveCursor(to index: Int) {
        guard !entries.isEmpty else { return }
        cursor = max(0, min(index, entries.count - 1)); revision &+= 1
    }

    // MARK: Velikosti adresářů

    public func computeDirSize(_ entry: FileEntry) {
        guard entry.isDirectory, !entry.isParentLink else { return }
        let url = entry.url
        Task {
            let size = await Task.detached { DirectorySize.compute(url) }.value
            self.dirSizes[url] = size
            self.revision &+= 1
        }
    }

    public func computeAllDirSizes() { entries.filter { $0.isDirectory && !$0.isParentLink }.forEach(computeDirSize) }

    // MARK: Interní

    private func applyView(keeping url: URL?) {
        let q = quickFilter.lowercased()
        var visible = all
        if !q.isEmpty { visible = visible.filter { $0.name.lowercased().contains(q) } }
        var result = sortEntries(visible, by: sort)
        if path.path != "/" { result.insert(FileEntry.parent(of: path), at: 0) }
        entries = result
        if let url, let i = entries.firstIndex(where: { $0.url == url && !$0.isParentLink }) { cursor = i }
        else { cursor = min(cursor, max(0, entries.count - 1)) }
        revision &+= 1
    }
}

@MainActor @Observable
public final class PanelGroup {
    public private(set) var tabs: [PanelTab]
    public var activeIndex = 0
    public var active: PanelTab { tabs[activeIndex] }

    public init(paths: [URL], showHidden: Bool = false) {
        let valid = paths.isEmpty ? [FileManager.default.homeDirectoryForCurrentUser] : paths
        tabs = valid.map { PanelTab(path: $0, showHidden: showHidden) }
    }

    public func newTab(at path: URL? = nil) {
        let tab = PanelTab(path: path ?? active.path, showHidden: active.showHidden)
        tabs.insert(tab, at: activeIndex + 1)
        activeIndex += 1
    }

    public func closeActiveTab() {
        guard tabs.count > 1 else { return }
        tabs.remove(at: activeIndex)
        activeIndex = min(activeIndex, tabs.count - 1)
    }

    public func select(_ index: Int) { if tabs.indices.contains(index) { activeIndex = index } }
    public func nextTab() { activeIndex = (activeIndex + 1) % tabs.count }
    public func previousTab() { activeIndex = (activeIndex - 1 + tabs.count) % tabs.count }
}
