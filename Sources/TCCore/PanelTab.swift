import Foundation
import Observation

public enum ViewMode: String, Sendable, CaseIterable { case full, brief, thumbnails }

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
    public var viewMode = ViewMode.full
    /// Naposledy navštívené adresáře (nejnovější první).
    public private(set) var recent: [URL] = []
    /// Branch view: všechny soubory z podadresářů v jednom seznamu.
    public private(set) var isBranch = false
    @ObservationIgnored private var savedSelection: Set<URL> = []
    @ObservationIgnored private var watcher: DirectoryWatcher?
    public var autoRefresh = true { didSet { updateWatcher() } }
    public var sort = SortDescriptor() { didSet { if sort != oldValue { applyView(keeping: cursorURL) } } }
    public var showHidden = false { didSet { if showHidden != oldValue { reload() } } }
    public var quickFilter = "" { didSet { if quickFilter != oldValue { applyView(keeping: cursorURL) } } }

    @ObservationIgnored private var all: [FileEntry] = []
    @ObservationIgnored private var backStack: [URL] = []
    @ObservationIgnored private var forwardStack: [URL] = []
    @ObservationIgnored private var fs: any VirtualFileSystem
    @ObservationIgnored private var saved: SavedLocation?
    /// Archiv, do kterého panel právě vstoupil (cesty uvnitř jsou cesty v archivu).
    public private(set) var archiveFile: URL?
    @ObservationIgnored public private(set) var archiveFS: ArchiveFileSystem?

    private struct SavedLocation { let fs: any VirtualFileSystem; let path: URL; let back: [URL]; let forward: [URL] }

    public init(path: URL, fs: any VirtualFileSystem = LocalFileSystem(), showHidden: Bool = false) {
        self.fs = fs
        self.path = path.standardizedFileURL
        self.showHidden = showHidden
        reload()
    }

    public var insideArchive: Bool { archiveFile != nil }

    /// Cesta na disku, kterou lze uložit nebo přidat do oblíbených (u archivu adresář s archivem).
    public var persistentPath: URL { archiveFile?.deletingLastPathComponent() ?? path }

    /// Cesta pro zobrazení v adresním řádku.
    public var displayPath: String { archiveFile.map { $0.path + " ▸ " + path.path } ?? path.path }

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
            isBranch = false
            error = nil
            if archiveFile == nil {
                recent.removeAll { $0 == target }
                recent.insert(target, at: 0)
                if recent.count > 30 { recent.removeLast() }
            }
            updateWatcher()
            applyView(keeping: select)
            return true
        } catch {
            self.error = "\(target.path): \(error.localizedDescription)"
            revision &+= 1
            return false
        }
    }

    public func goUp() {
        if archiveFile != nil && path.path == "/" { leaveArchive(); return }
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
        if isBranch { enterBranchView(); return }
        if let a = archiveFile, !FileManager.default.fileExists(atPath: a.path) { leaveArchive(); return }
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
        if archiveFile == nil && ArchiveSupport.isArchive(e.name), enterArchive(e.url) { return nil }
        return e.url
    }

    // MARK: Archivy

    /// Vstoupí do archivu (jako do adresáře); při chybě nastaví `error` a vrátí false.
    @discardableResult
    public func enterArchive(_ url: URL) -> Bool {
        do {
            let afs = try ArchiveFileSystem(archiveURL: url)
            saved = SavedLocation(fs: fs, path: path, back: backStack, forward: forwardStack)
            fs = afs; archiveFS = afs; archiveFile = url
            watcher?.stop(); watcher = nil
            backStack = []; forwardStack = []; marked.removeAll(); quickFilter = ""
            path = URL(fileURLWithPath: "/")
            all = try afs.list(path, includeHidden: showHidden)
            error = nil
            applyView(keeping: nil)
            cursor = 0
            return true
        } catch {
            self.error = "\(url.lastPathComponent): \(error.localizedDescription)"
            revision &+= 1
            return false
        }
    }

    /// Přejde na adresář na disku; pokud je panel v archivu, nejdřív z něj vystoupí.
    @discardableResult
    public func navigateLocal(_ url: URL, select: URL? = nil) -> Bool {
        if archiveFile != nil { leaveArchive() }
        return navigate(to: url, select: select)
    }

    public func leaveArchive() {
        guard let archive = archiveFile, let s = saved else { return }
        fs = s.fs; archiveFS = nil; archiveFile = nil; saved = nil
        backStack = s.back; forwardStack = s.forward; marked.removeAll(); quickFilter = ""
        navigate(to: s.path, select: archive, recordHistory: false)
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

    /// Označí všechny soubory se stejnou příponou jako soubor pod kurzorem.
    public func markSameExtension() {
        guard let e = cursorEntry, !e.isParentLink, !e.isDirectory else { return }
        let ext = e.ext.lowercased()
        for x in entries where !x.isParentLink && !x.isDirectory && x.ext.lowercased() == ext { marked.insert(x.url) }
        revision &+= 1
    }

    /// Nahradí označení danými URL (jen položky, které v panelu jsou).
    public func setMarks(_ urls: Set<URL>) { marked = urls.intersection(Set(entries.map(\.url))); revision &+= 1 }

    public func saveSelection() { savedSelection = marked }

    public func restoreSelection() {
        marked = savedSelection.intersection(Set(entries.map(\.url))); revision &+= 1
    }

    // MARK: Branch view

    /// Ctrl+B: zobrazí všechny soubory ze všech podadresářů (názvy jsou relativní cesty).
    public func enterBranchView(limit: Int = 200_000) {
        guard archiveFile == nil else { return }
        var flat: [FileEntry] = []
        var stack = [path]
        while let dir = stack.popLast(), flat.count < limit {
            for e in (try? fs.list(dir, includeHidden: showHidden)) ?? [] {
                if e.isDirectory { if !e.isSymlink { stack.append(e.url) }; continue }
                let rel = String(e.url.path.dropFirst(path.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                flat.append(FileEntry(url: e.url, name: rel, isDirectory: false, isSymlink: e.isSymlink, isHidden: e.isHidden,
                                      size: e.size, modified: e.modified, permissions: e.permissions))
            }
        }
        all = flat
        isBranch = true
        error = nil
        marked.formIntersection(Set(flat.map(\.url)))
        applyView(keeping: cursorURL)
    }

    public func exitBranchView() { if isBranch { navigate(to: path, select: cursorURL, recordHistory: false, keepMarks: true) } }

    private func updateWatcher() {
        watcher?.stop(); watcher = nil
        guard autoRefresh, archiveFile == nil else { return }
        watcher = DirectoryWatcher(url: path) { [weak self] in
            Task { @MainActor in
                guard let self, !self.isBranch else { return }
                self.reload()
            }
        }
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
        if path.path != "/" || archiveFile != nil { result.insert(FileEntry.parent(of: path), at: 0) }
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
