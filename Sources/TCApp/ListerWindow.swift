import AppKit
import AVKit
import PDFKit
import TCCore
import WebKit

private final class ListerPanel: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }
}

/// Okno Listeru (F3): text, hex, obrázek, PDF, média, HTML. Esc zavře, 1–3 přepínají režimy.
@MainActor
final class ListerWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var open: [ListerWindow] = []

    static func show(_ url: URL) {
        if let w = open.first(where: { $0.url == url }) { w.window.makeKeyAndOrderFront(nil); return }
        guard let w = ListerWindow(url: url) else { return }
        open.append(w)
        w.window.makeKeyAndOrderFront(nil)
    }

    private let url: URL
    private let data: Data
    private let window: ListerPanel
    private let modes: [ListerMode]
    private let container = NSView()
    private let segmented: NSSegmentedControl
    private let info = NSTextField(labelWithString: "")
    private var encodingName = ""
    private var hexTable: NSTableView?
    private var player: AVPlayer?

    private init?(url: URL) {
        self.url = url
        guard let d = try? Data(contentsOf: url, options: .alwaysMapped) else {
            Dialogs.error("Soubor nelze otevřít", url.path); return nil
        }
        data = d
        modes = ListerSupport.modes(for: url, sample: d.prefix(8192))
        segmented = NSSegmentedControl(labels: modes.map(Self.title), trackingMode: .selectOne, target: nil, action: nil)
        window = ListerPanel(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                             styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "\(url.lastPathComponent) – Lister"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()

        segmented.target = self
        segmented.action = #selector(modeChanged)
        segmented.selectedSegment = 0
        info.font = .systemFont(ofSize: 11)
        info.textColor = .secondaryLabelColor
        for v in [segmented, info, container] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; window.contentView?.addSubview(v) }
        let c = window.contentView!
        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: c.topAnchor, constant: 8),
            segmented.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 10),
            info.centerYAnchor.constraint(equalTo: segmented.centerYAnchor),
            info.leadingAnchor.constraint(equalTo: segmented.trailingAnchor, constant: 12),
            info.trailingAnchor.constraint(lessThanOrEqualTo: c.trailingAnchor, constant: -10),
            container.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: c.bottomAnchor),
        ])
        show(modes[0])
    }

    private static func title(_ m: ListerMode) -> String {
        switch m {
        case .text: "Text"; case .hex: "Hex"; case .image: "Obrázek"; case .pdf: "PDF"; case .media: "Přehrávač"; case .web: "HTML"
        }
    }

    @objc private func modeChanged() { show(modes[segmented.selectedSegment]) }

    private func show(_ mode: ListerMode) {
        player?.pause(); player = nil; hexTable = nil
        container.subviews.forEach { $0.removeFromSuperview() }
        let view: NSView
        switch mode {
        case .text: view = textView()
        case .hex: view = hexView()
        case .image: view = imageView()
        case .pdf:
            let v = PDFView(); v.document = PDFDocument(url: url); v.autoScales = true; view = v
        case .media:
            let v = AVPlayerView(); let p = AVPlayer(url: url); v.player = p; player = p; view = v
        case .web:
            let v = WKWebView(); v.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()); view = v
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor), view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor), view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        info.stringValue = [size, mode == .text ? encodingName : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        if let i = modes.firstIndex(of: mode) { segmented.selectedSegment = i }
    }

    // MARK: Režimy

    private static let textLimit = 16 * 1024 * 1024

    private func textView() -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let tv = NSTextView()
        tv.isEditable = false
        tv.usesFindBar = true
        tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        let chunk = data.count > Self.textLimit ? data.prefix(Self.textLimit) : data
        let decoded = TextDecoding.decode(Data(chunk))
        encodingName = decoded.encoding + (data.count > Self.textLimit ? " · zobrazeno prvních 16 MB (celý soubor v režimu Hex)" : "")
        tv.string = decoded.text
        scroll.documentView = tv
        return scroll
    }

    private func hexView() -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        let t = NSTableView()
        t.usesAlternatingRowBackgroundColors = true
        t.rowHeight = 17
        t.allowsEmptySelection = true
        for (id, title, w) in [("off", "Offset", 80.0), ("hex", "Hex", 400.0), ("asc", "ASCII", 160.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); col.title = title; col.width = w; t.addTableColumn(col)
        }
        t.dataSource = self
        t.delegate = self
        scroll.documentView = t
        hexTable = t
        return scroll
    }

    private func imageView() -> NSView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true
        let iv = NSImageView(image: NSImage(contentsOf: url) ?? NSImage())
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.frame = NSRect(origin: .zero, size: iv.image?.size ?? NSSize(width: 100, height: 100))
        scroll.documentView = iv
        return scroll
    }

    func numberOfRows(in tableView: NSTableView) -> Int { HexDump.rowCount(length: data.count) }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let col else { return nil }
        let cell = (tv.makeView(withIdentifier: col.identifier, owner: nil) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: ""); f.identifier = col.identifier
            f.font = .monospacedSystemFont(ofSize: 12, weight: .regular); return f
        }()
        let r = HexDump.row(data, index: row)
        cell.stringValue = col.identifier.rawValue == "off" ? r.offset : (col.identifier.rawValue == "hex" ? r.hex : r.ascii)
        return cell
    }

    func windowWillClose(_ notification: Notification) {
        player?.pause()
        Self.open.removeAll { $0 === self }
    }
}
