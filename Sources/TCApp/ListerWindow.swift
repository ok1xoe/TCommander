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

    static func show(_ url: URL, skipPlugins: Bool = false) {
        if !skipPlugins, PluginViewWindow.tryShow(url) { return }
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
    private var textPage = 0
    private var textArea: NSTextView?
    private var pageLabel = NSTextField(labelWithString: "")
    private let hexSearch = NSSearchField()
    private let gotoOffset = NSTextField()
    private let encodingPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let wrapBox = NSButton(checkboxWithTitle: "Zalamovat řádky", target: nil, action: nil)
    private var forcedEncoding = "Automaticky"
    private var wrap = true
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
        player?.pause(); player = nil; hexTable = nil; textArea = nil
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
        scroll.documentView = tv
        textArea = tv
        applyWrap(scroll)
        let pages = TextPager.count(of: data.count, size: Self.textLimit)
        showTextPage(min(textPage, pages - 1))

        // lišta: kódování, zalamování a (u velkých souborů) stránkování po 16 MB
        if encodingPopup.numberOfItems == 0 { encodingPopup.addItems(withTitles: TextDecoding.selectableEncodings) }
        encodingPopup.selectItem(withTitle: forcedEncoding)
        encodingPopup.target = self; encodingPopup.action = #selector(encodingChanged)
        wrapBox.state = wrap ? .on : .off
        wrapBox.target = self; wrapBox.action = #selector(wrapChanged)
        var items: [NSView] = [NSTextField(labelWithString: "Kódování:"), encodingPopup, wrapBox]
        if pages > 1 {
            let prev = NSButton(title: "◀︎ Předchozí část", target: self, action: #selector(prevPage))
            let next = NSButton(title: "Další část ▶︎", target: self, action: #selector(nextPage))
            pageLabel.font = .systemFont(ofSize: 11); pageLabel.textColor = .secondaryLabelColor
            items += [prev, next, pageLabel]
        }
        let bar = NSStackView(views: items + [NSView()]); bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        let box = NSStackView(views: [bar, scroll]); box.orientation = .vertical; box.spacing = 0; box.alignment = .leading
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        return box
    }

    private func applyWrap(_ scroll: NSScrollView? = nil) {
        guard let tv = textArea else { return }
        let sv = scroll ?? tv.enclosingScrollView
        tv.isHorizontallyResizable = !wrap
        tv.textContainer?.widthTracksTextView = wrap
        tv.textContainer?.containerSize = NSSize(width: wrap ? max(100, (sv?.contentSize.width ?? 800)) : 1_000_000, height: CGFloat.greatestFiniteMagnitude)
        sv?.hasHorizontalScroller = !wrap
        tv.sizeToFit()
    }

    @objc private func wrapChanged() { wrap = wrapBox.state == .on; applyWrap() }

    @objc private func encodingChanged() {
        forcedEncoding = encodingPopup.titleOfSelectedItem ?? "Automaticky"
        showTextPage(textPage)
    }

    private func showTextPage(_ i: Int) {
        let pages = TextPager.count(of: data.count, size: Self.textLimit)
        textPage = max(0, min(i, pages - 1))
        let r = TextPager.range(in: data, index: textPage, size: Self.textLimit)
        let chunk = Data(data[data.startIndex + r.lowerBound..<data.startIndex + r.upperBound])
        let decoded = forcedEncoding == "Automaticky" ? TextDecoding.decode(chunk) : (TextDecoding.decode(chunk, forced: forcedEncoding), forcedEncoding + " (ručně)")
        encodingName = decoded.1 + (pages > 1 ? " · část \(textPage + 1) z \(pages)" : "")
        textArea?.string = decoded.0
        textArea?.scrollToBeginningOfDocument(nil)
        pageLabel.stringValue = pages > 1 ? "Část \(textPage + 1) z \(pages) (bajty \(r.lowerBound)–\(r.upperBound))" : ""
        info.stringValue = [ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file), encodingName].joined(separator: " · ")
    }

    @objc private func prevPage() { showTextPage(textPage - 1) }
    @objc private func nextPage() { showTextPage(textPage + 1) }

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
        hexSearch.placeholderString = "Hledat: text nebo bajty (např. 4D 5A)"
        hexSearch.target = self; hexSearch.action = #selector(searchHex)
        hexSearch.translatesAutoresizingMaskIntoConstraints = false
        hexSearch.widthAnchor.constraint(equalToConstant: 320).isActive = true
        gotoOffset.placeholderString = "Offset: 0x1F40 nebo 8000"
        gotoOffset.target = self; gotoOffset.action = #selector(gotoOffsetAction)
        gotoOffset.translatesAutoresizingMaskIntoConstraints = false
        gotoOffset.widthAnchor.constraint(equalToConstant: 190).isActive = true
        let bar = NSStackView(views: [hexSearch, NSTextField(labelWithString: "Přejít na:"), gotoOffset, NSView()]); bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        let box = NSStackView(views: [bar, scroll]); box.orientation = .vertical; box.spacing = 0; box.alignment = .leading
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        return box
    }

    @objc private func gotoOffsetAction() {
        guard let t = hexTable, let off = TextDecoding.parseOffset(gotoOffset.stringValue) else { NSSound.beep(); return }
        guard off >= 0, off < data.count else { info.stringValue = "Offset je mimo soubor (velikost \(data.count) bajtů)"; NSSound.beep(); return }
        let row = off / HexDump.width
        t.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        t.scrollRowToVisible(row)
        info.stringValue = String(format: "Offset 0x%X (%d)", off, off)
    }

    /// Enter v poli hledání: najde další výskyt od vybraného řádku (na konci se vrací na začátek).
    @objc private func searchHex() {
        guard let t = hexTable, let pattern = HexSearch.pattern(from: hexSearch.stringValue) else { return }
        let from = t.selectedRow >= 0 ? (t.selectedRow + 1) * HexDump.width : 0
        guard let off = HexSearch.find(pattern, in: data, from: from) else { info.stringValue = "Nenalezeno"; NSSound.beep(); return }
        let row = off / HexDump.width
        t.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        t.scrollRowToVisible(row)
        info.stringValue = String(format: "Nalezeno na offsetu 0x%X (%d)", off, off)
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
