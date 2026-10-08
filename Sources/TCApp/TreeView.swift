import AppKit
import SwiftUI
import TCCore

/// Uzel stromu adresářů; podadresáře se načítají až při rozbalení.
final class DirNode: NSObject {
    let url: URL
    let name: String
    private(set) var children: [DirNode]?

    init(url: URL, name: String? = nil) {
        self.url = url
        self.name = name ?? (url.path == "/" ? "/" : url.lastPathComponent)
    }

    func loadChildren(showHidden: Bool) -> [DirNode] {
        if let c = children { return c }
        let fs = LocalFileSystem()
        let dirs = ((try? fs.list(url, includeHidden: showHidden)) ?? []).filter { $0.isDirectory && !$0.isSymlink }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let c = dirs.map { DirNode(url: $0.url) }
        children = c
        return c
    }

    func invalidate() { children = nil }
}

/// Strom adresářů vedle seznamu souborů (Ctrl+F8 v TC).
struct TreeView: NSViewRepresentable {
    let tab: PanelTab
    let revision: Int
    let onNavigate: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let outline = NSOutlineView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dir"))
        col.title = "Adresáře"
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.headerView = nil
        outline.rowHeight = 20
        outline.style = .sourceList
        outline.dataSource = c; outline.delegate = c
        c.outline = outline
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync()
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: TreeView
        weak var outline: NSOutlineView?
        private var roots: [DirNode] = []
        private var syncing = false
        private var lastPath: URL?
        private var lastHidden = false

        init(_ p: TreeView) { parent = p; super.init(); buildRoots() }

        private func buildRoots() {
            var r: [DirNode] = [DirNode(url: Sandbox.home, name: "Domů"), DirNode(url: URL(fileURLWithPath: "/"), name: "/")]
            let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
            for v in vols where v.path != "/" { r.append(DirNode(url: v, name: (try? v.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? v.lastPathComponent)) }
            roots = r
        }

        func sync() {
            guard let outline else { return }
            let tab = parent.tab
            if tab.showHidden != lastHidden { lastHidden = tab.showHidden; buildRoots(); outline.reloadData(); lastPath = nil }
            let target = tab.persistentPath.standardizedFileURL
            guard target != lastPath else { return }
            lastPath = target
            syncing = true
            defer { syncing = false }
            // kořen s nejdelší shodnou předponou
            let candidates = roots.filter { target.path == $0.url.standardizedFileURL.path || target.path.hasPrefix($0.url.standardizedFileURL.path == "/" ? "/" : $0.url.standardizedFileURL.path + "/") }
            guard let root = candidates.max(by: { $0.url.path.count < $1.url.path.count }) else { return }
            var node = root
            outline.expandItem(node)
            let rootPath = root.url.standardizedFileURL.path
            let rel = target.path == rootPath ? [] : String(target.path.dropFirst(rootPath == "/" ? 1 : rootPath.count + 1)).split(separator: "/").map(String.init)
            for comp in rel {
                guard let next = node.loadChildren(showHidden: tab.showHidden).first(where: { $0.url.lastPathComponent == comp }) else { break }
                node = next
                outline.expandItem(node)
            }
            let row = outline.row(forItem: node)
            if row >= 0 {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outline.scrollRowToVisible(row)
            }
        }

        func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            guard let n = item as? DirNode else { return roots.count }
            return n.loadChildren(showHidden: parent.tab.showHidden).count
        }

        func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            guard let n = item as? DirNode else { return roots[index] }
            return n.loadChildren(showHidden: parent.tab.showHidden)[index]
        }

        func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool { true }

        func outlineView(_ ov: NSOutlineView, viewFor col: NSTableColumn?, item: Any) -> NSView? {
            guard let n = item as? DirNode else { return nil }
            let id = NSUserInterfaceItemIdentifier("dircell")
            let cell = (ov.makeView(withIdentifier: id, owner: nil) as? FileCell) ?? FileCell(identifier: id, withIcon: true, alignment: .left, mono: false)
            cell.label.stringValue = n.name
            cell.icon.image = NSWorkspace.shared.icon(forFile: n.url.path)
            return cell
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !syncing, let outline, let n = outline.item(atRow: outline.selectedRow) as? DirNode else { return }
            lastPath = n.url.standardizedFileURL
            parent.onNavigate(n.url)
        }
    }
}
