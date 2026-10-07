import AppKit
import QuickLookThumbnailing
import SwiftUI
import TCCore

final class KeyCollectionView: NSCollectionView {
    var keyHandler: ((NSEvent) -> Bool)?
    var focusHandler: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) { focusHandler?(); super.mouseDown(with: event) }

    override func becomeFirstResponder() -> Bool { focusHandler?(); return super.becomeFirstResponder() }
}

final class ThumbItem: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("thumb")
    private let image = NSImageView()
    private let label = NSTextField(labelWithString: "")
    var representedURL: URL?

    override func loadView() {
        let v = NSView()
        image.imageScaling = .scaleProportionallyUpOrDown
        label.alignment = .center; label.lineBreakMode = .byTruncatingMiddle; label.font = .systemFont(ofSize: 11)
        for sub in [image, label] as [NSView] { sub.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(sub) }
        NSLayoutConstraint.activate([
            image.topAnchor.constraint(equalTo: v.topAnchor, constant: 4), image.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 4),
            image.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -4), image.heightAnchor.constraint(equalToConstant: 96),
            label.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 2), label.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -2),
        ])
        view = v
        v.wantsLayer = true
        v.layer?.cornerRadius = 6
    }

    override var isSelected: Bool {
        didSet { view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.35).cgColor : nil }
    }

    func configure(_ e: FileEntry, marked: Bool, thumbnail: NSImage?) {
        representedURL = e.url
        label.stringValue = e.isParentLink ? ".." : e.name
        label.textColor = marked ? .systemRed : .labelColor
        image.image = thumbnail ?? IconCache.icon(for: e)
    }

    func setImage(_ img: NSImage, for url: URL) { if representedURL == url { image.image = img } }
}

@MainActor
enum ThumbnailCache {
    private static var cache: [String: NSImage] = [:]

    static func key(_ e: FileEntry) -> String { e.url.path + "|\(e.modified?.timeIntervalSince1970 ?? 0)" }
    static func cached(_ e: FileEntry) -> NSImage? { cache[key(e)] }

    static func load(_ e: FileEntry, completion: @escaping @MainActor (NSImage) -> Void) {
        let k = key(e)
        if let i = cache[k] { completion(i); return }
        let req = QLThumbnailGenerator.Request(fileAt: e.url, size: CGSize(width: 160, height: 120), scale: 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
            guard let cg = rep?.cgImage else { return }
            let img = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
            DispatchQueue.main.async { MainActor.assumeIsolated { cache[k] = img; completion(img) } }
        }
    }
}

struct ThumbnailGridView: NSViewRepresentable {
    let tab: PanelTab
    let revision: Int
    let isActive: Bool
    let onFocus: () -> Void
    let onKey: (NSEvent) -> Bool
    let onOpen: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let grid = KeyCollectionView()
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 130, height: 126)
        layout.minimumInteritemSpacing = 6; layout.minimumLineSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        grid.collectionViewLayout = layout
        grid.isSelectable = true
        grid.allowsMultipleSelection = false
        grid.register(ThumbItem.self, forItemWithIdentifier: ThumbItem.id)
        grid.dataSource = c; grid.delegate = c
        grid.keyHandler = { [weak c] e in c?.parent.onKey(e) ?? false }
        grid.focusHandler = { [weak c] in c?.parent.onFocus() }
        grid.backgroundColors = [.textBackgroundColor]
        c.grid = grid
        let click = NSClickGestureRecognizer(target: c, action: #selector(Coordinator.doubleClicked(_:)))
        click.numberOfClicksRequired = 2
        grid.addGestureRecognizer(click)
        let scroll = NSScrollView()
        scroll.documentView = grid
        scroll.hasVerticalScroller = true
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: ThumbnailGridView
        weak var grid: KeyCollectionView?
        private var lastRevision = -1, lastActive = false, syncing = false

        init(_ p: ThumbnailGridView) { parent = p }

        func sync() {
            guard let grid else { return }
            syncing = true
            if parent.revision != lastRevision { lastRevision = parent.revision; grid.reloadData() }
            let cur = parent.tab.cursor
            if parent.tab.entries.indices.contains(cur), grid.selectionIndexPaths != [IndexPath(item: cur, section: 0)] {
                grid.selectionIndexPaths = [IndexPath(item: cur, section: 0)]
                grid.scrollToItems(at: [IndexPath(item: cur, section: 0)], scrollPosition: .nearestVerticalEdge)
            }
            syncing = false
            if parent.isActive && !lastActive, let w = grid.window, w.firstResponder !== grid, !(w.firstResponder is NSText) {
                DispatchQueue.main.async { w.makeFirstResponder(grid) }
            }
            lastActive = parent.isActive
        }

        func collectionView(_ cv: NSCollectionView, numberOfItemsInSection section: Int) -> Int { parent.tab.entries.count }

        func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt ip: IndexPath) -> NSCollectionViewItem {
            let item = cv.makeItem(withIdentifier: ThumbItem.id, for: ip) as! ThumbItem
            let e = parent.tab.entries[ip.item]
            item.configure(e, marked: parent.tab.marked.contains(e.url), thumbnail: e.isDirectory ? nil : ThumbnailCache.cached(e))
            if !e.isDirectory && !e.isParentLink && ThumbnailCache.cached(e) == nil {
                ThumbnailCache.load(e) { [weak item] img in item?.setImage(img, for: e.url) }
            }
            return item
        }

        func collectionView(_ cv: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard !syncing, let i = indexPaths.first?.item else { return }
            parent.tab.cursor = i
        }

        @objc func doubleClicked(_ g: NSClickGestureRecognizer) {
            guard let grid, let ip = grid.indexPathForItem(at: g.location(in: grid)) else { return }
            parent.tab.cursor = ip.item
            parent.onOpen()
        }
    }
}
