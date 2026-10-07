import AppKit
import AVKit
import PDFKit
import TCCore
import WebKit

private final class ListerPanel: NSWindow {
    var onKey: ((String) -> Bool)?
    override func cancelOperation(_ sender: Any?) { close() }

    override func keyDown(with event: NSEvent) {
        // N / P = další / předchozí soubor (mimo psaní do textových polí)
        if !(firstResponder is NSText), event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let c = event.charactersIgnoringModifiers?.lowercased(), onKey?(c) == true { return }
        super.keyDown(with: event)
    }
}

/// Clip view, který vycentruje menší dokument (obrázek) v okně místo přilepení k rohu.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposed)
        guard let doc = documentView else { return rect }
        let f = doc.frame
        if f.width < proposed.width { rect.origin.x = (f.width - proposed.width) / 2 }
        if f.height < proposed.height { rect.origin.y = (f.height - proposed.height) / 2 }
        return rect
    }
}

/// Okno Listeru (F3): text, hex, obrázek, PDF, média, HTML. Esc zavře, 1–3 přepínají režimy.
@MainActor
final class ListerWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, WKNavigationDelegate {
    private static var open: [ListerWindow] = []

    static func show(_ url: URL, skipPlugins: Bool = false, siblings: [URL] = []) {
        if !skipPlugins, PluginViewWindow.tryShow(url) { return }
        if let w = open.first(where: { $0.url == url }) { w.window.makeKeyAndOrderFront(nil); return }
        guard let w = ListerWindow(url: url, siblings: siblings) else { return }
        open.append(w)
        w.window.makeKeyAndOrderFront(nil)
    }

    /// Přepne na další (+1) nebo předchozí (−1) soubor ze seznamu v panelu; nové okno převezme polohu a velikost.
    private func navigate(by delta: Int) {
        guard siblings.count > 1, let i = siblings.firstIndex(of: url) else { return }
        var j = i
        for _ in 0..<siblings.count {
            j = (j + delta + siblings.count) % siblings.count
            guard j != i, let w = ListerWindow(url: siblings[j], siblings: siblings) else { continue }
            Self.open.append(w)
            w.window.setFrame(window.frame, display: true)
            w.window.makeKeyAndOrderFront(nil)
            window.close()
            return
        }
    }

    private let url: URL
    private let siblings: [URL]
    private let data: Data
    private let window: ListerPanel
    private let modes: [ListerMode]
    private let container = NSView()
    private let segmented: NSSegmentedControl
    private let info = NSTextField(labelWithString: "")
    private let prevButton = NSButton(title: "◀︎", target: nil, action: nil)
    private let nextButton = NSButton(title: "▶︎", target: nil, action: nil)
    private var imageRotation = 0
    private var imageInfo = ""
    private var imageScroll: NSScrollView?
    private var imageBase: NSImage?
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
    private enum DiagramState { case idle, rendering, done([NSImage]), failed(String) }
    private var diagramState = DiagramState.idle
    private var diagramIndex = 0

    private init?(url: URL, siblings: [URL] = []) {
        self.url = url
        self.siblings = siblings
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
        prevButton.target = self; prevButton.action = #selector(prevFile)
        nextButton.target = self; nextButton.action = #selector(nextFile)
        prevButton.toolTip = "Předchozí soubor (P)"; nextButton.toolTip = "Další soubor (N)"
        let multiple = siblings.count > 1
        prevButton.isHidden = !multiple; nextButton.isHidden = !multiple
        if multiple, let i = siblings.firstIndex(of: url) { window.title = "\(url.lastPathComponent) – Lister (\(i + 1)/\(siblings.count))" }
        window.onKey = { [weak self] c in
            switch c { case "n": self?.navigate(by: 1); return true; case "p": self?.navigate(by: -1); return true; default: return false }
        }
        for v in [segmented, info, container, prevButton, nextButton] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; window.contentView?.addSubview(v) }
        let c = window.contentView!
        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: c.topAnchor, constant: 8),
            segmented.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 10),
            info.centerYAnchor.constraint(equalTo: segmented.centerYAnchor),
            info.leadingAnchor.constraint(equalTo: segmented.trailingAnchor, constant: 12),
            nextButton.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -10),
            nextButton.centerYAnchor.constraint(equalTo: segmented.centerYAnchor),
            prevButton.trailingAnchor.constraint(equalTo: nextButton.leadingAnchor, constant: -4),
            prevButton.centerYAnchor.constraint(equalTo: segmented.centerYAnchor),
            info.trailingAnchor.constraint(lessThanOrEqualTo: prevButton.leadingAnchor, constant: -10),
            container.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 8),
            container.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: c.bottomAnchor),
        ])
        show(modes[0])
    }

    private static func title(_ m: ListerMode) -> String {
        switch m {
        case .text: "Text"; case .hex: "Hex"; case .image: "Obrázek"; case .pdf: "PDF"; case .media: "Přehrávač"; case .web: "HTML"; case .diagram: "Diagram"; case .markdown: "Markdown"
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
        case .diagram: view = diagramView()
        case .markdown: view = markdownView()
        case .pdf:
            let v = PDFView(); v.document = PDFDocument(url: url); v.autoScales = true; view = v
        case .media:
            let v = AVPlayerView(); let p = AVPlayer(url: url); v.player = p; player = p; view = v
        case .web:
            let v = WKWebView()
            // HTML bez deklarovaného kódování (meta charset) se dekóduje podle obsahu, jinak by WebKit rozbil diakritiku
            let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
            if head.contains("charset") { v.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
            else { v.loadHTMLString(TextDecoding.decode(data).text, baseURL: url.deletingLastPathComponent()) }
            view = v
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor), view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor), view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        info.stringValue = [size, mode == .text ? encodingName : "", (mode == .image || mode == .diagram) ? imageInfo : ""].filter { !$0.isEmpty }.joined(separator: " · ")
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
        if let lang = SyntaxHighlighter.language(forFileName: url.lastPathComponent), let storage = textArea?.textStorage {
            SyntaxStyle.apply(to: storage, language: lang, baseFont: textArea?.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular))
        }
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

    @objc private func prevFile() { navigate(by: -1) }
    @objc private func nextFile() { navigate(by: 1) }

    // MARK: Obrázky: přiblížení a otočení

    // MARK: Čtečka Markdownu

    private var markdownTemp: URL?
    private static let markdownLimit = 4 * 1024 * 1024

    /// Vykreslený Markdown: HTML se zapíše do dočasného souboru (aby šly načíst relativní obrázky), skripty jsou vypnuté;
    /// odkazy na weby se otevřou v prohlížeči, odkazy na soubory v Listeru.
    private func markdownView() -> NSView {
        let text = TextDecoding.decode(data.prefix(Self.markdownLimit)).text
        let html = MarkdownHTML.page(text, baseURL: url.deletingLastPathComponent(), title: url.lastPathComponent)
        let tmp = markdownTemp ?? FileManager.default.temporaryDirectory.appendingPathComponent("tcommander-md-\(UUID().uuidString).html")
        markdownTemp = tmp
        try? html.write(to: tmp, atomically: true, encoding: .utf8)
        let cfg = WKWebViewConfiguration()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = false
        let v = WKWebView(frame: .zero, configuration: cfg)
        v.navigationDelegate = self
        v.loadFileURL(tmp, allowingReadAccessTo: URL(fileURLWithPath: "/"))
        return v
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated, let target = navigationAction.request.url else { decisionHandler(.allow); return }
        if target.isFileURL {
            if target.fragment != nil, target.deletingLastPathComponent() == markdownTemp?.deletingLastPathComponent(), target.lastPathComponent == markdownTemp?.lastPathComponent { decisionHandler(.allow); return }
            decisionHandler(.cancel)
            let file = URL(fileURLWithPath: target.path)
            if FileManager.default.fileExists(atPath: file.path) { ListerWindow.show(file) }
        } else {
            decisionHandler(.cancel)
            NSWorkspace.shared.open(target)
        }
    }

    // MARK: Diagram (PlantUML)

    private func messageView(_ text: String, hint: String? = nil) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.alignment = .center; label.font = .systemFont(ofSize: 13); label.isSelectable = true
        var views: [NSView] = [label]
        if let hint {
            let h = NSTextField(wrappingLabelWithString: hint); h.alignment = .center; h.textColor = .secondaryLabelColor; h.font = .systemFont(ofSize: 12); h.isSelectable = true
            views.append(h)
        }
        let stack = NSStackView(views: views); stack.orientation = .vertical; stack.spacing = 10; stack.alignment = .centerX
        let box = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: box.centerXAnchor), stack.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: box.widthAnchor, constant: -60), stack.widthAnchor.constraint(lessThanOrEqualToConstant: 700),
        ])
        return box
    }

    private func diagramView() -> NSView {
        switch diagramState {
        case .idle:
            startDiagramRender()
            if case .failed = diagramState { return diagramView() }
            return messageView("Vykresluji diagram…")
        case .rendering: return messageView("Vykresluji diagram…")
        case .failed(let message):
            let notFound = message == Self.plantUMLMissing
            return messageView(message, hint: notFound ? "Nainstalujte ho příkazem  brew install plantuml  (potřebuje Javu), nebo v Nastavení › Obecné zadejte cestu k plantuml.jar. Zdroj diagramu je v záložce Text." : "Zdroj diagramu je v záložce Text.")
        case .done(let images):
            diagramIndex = min(max(0, diagramIndex), images.count - 1)
            return imageView(base: images[diagramIndex], pages: images.count)
        }
    }

    private static let plantUMLMissing = "PlantUML nebyl nalezen."

    private func startDiagramRender() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("macTC").path
        guard let launcher = PlantUML.locate(configured: AppModel.shared.settings.plantUMLPath, extraJarDirectories: [support]) else {
            diagramState = .failed(Self.plantUMLMissing); return
        }
        diagramState = .rendering
        let file = url
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("macTC-plantuml-\(UUID().uuidString)")
        Task.detached {
            let result = Result { try PlantUML.render(file: file, into: out, launcher: launcher) }
            let images = (try? result.get())?.compactMap { (try? Data(contentsOf: $0)).flatMap { NSImage(data: $0) } } ?? []
            try? FileManager.default.removeItem(at: out)
            await MainActor.run { [weak self] in
                guard let self else { return }
                switch result {
                case .success where !images.isEmpty: self.diagramState = .done(images)
                case .success: self.diagramState = .failed("Obrázek diagramu se nepodařilo načíst.")
                case .failure(let e): self.diagramState = .failed(e.localizedDescription)
                }
                if self.modes[self.segmented.selectedSegment] == .diagram { self.show(.diagram) }
            }
        }
    }

    @objc private func previousDiagram() { diagramIndex -= 1; show(.diagram) }
    @objc private func nextDiagram() { diagramIndex += 1; show(.diagram) }

    private func imageView(base: NSImage? = nil, pages: Int = 1) -> NSView {
        let scroll = NSScrollView()
        scroll.contentView = CenteringClipView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05; scroll.maxMagnification = 16
        imageScroll = scroll
        imageBase = base ?? NSImage(contentsOf: url)
        imageRotation = 0
        applyImage()

        func button(_ title: String, _ action: Selector, _ tip: String) -> NSButton {
            let b = NSButton(title: title, target: self, action: action); b.toolTip = tip; return b
        }
        let bar = NSStackView(views: [button("−", #selector(zoomOut), "Oddálit"), button("+", #selector(zoomIn), "Přiblížit"),
                                      button("100 %", #selector(zoomActual), "Skutečná velikost"), button("Přizpůsobit", #selector(zoomFit), "Přizpůsobit oknu"),
                                      button("⟲", #selector(rotateLeft), "Otočit doleva"), button("⟳", #selector(rotateRight), "Otočit doprava")]
                                     + (pages > 1 ? [button("◀︎ Diagram", #selector(previousDiagram), "Předchozí diagram"), button("Diagram ▶︎", #selector(nextDiagram), "Další diagram")] : []) + [NSView()])
        bar.spacing = 6; bar.edgeInsets = NSEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        let box = NSStackView(views: [bar, scroll]); box.orientation = .vertical; box.spacing = 0; box.alignment = .leading
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalTo: box.widthAnchor).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
        DispatchQueue.main.async { [weak self] in self?.zoomFit() }
        return box
    }

    private func applyImage() {
        guard let base = imageBase, let scroll = imageScroll else { return }
        let img = Self.rotated(base, quarterTurns: imageRotation)
        let iv = NSImageView(image: img)
        iv.imageScaling = .scaleNone
        iv.frame = NSRect(origin: .zero, size: img.size)
        scroll.documentView = iv
        let rot = ((imageRotation % 4) + 4) % 4
        let page: String = { if case .done(let images) = diagramState, images.count > 1 { return "diagram \(diagramIndex + 1)/\(images.count) · " }; return "" }()
        imageInfo = page + "\(Int(base.size.width))×\(Int(base.size.height)) px" + (rot != 0 ? " · otočeno \(rot * 90)°" : "")
        info.stringValue = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file) + " · " + imageInfo
    }

    /// Kopie obrázku otočená po čtvrtinách kruhu (kladný směr = doprava).
    static func rotated(_ image: NSImage, quarterTurns: Int) -> NSImage {
        let q = ((quarterTurns % 4) + 4) % 4
        guard q != 0 else { return image }
        let size = image.size
        let newSize = q % 2 == 1 ? NSSize(width: size.height, height: size.width) : size
        let out = NSImage(size: newSize)
        out.lockFocus()
        let t = NSAffineTransform()
        t.translateX(by: newSize.width / 2, yBy: newSize.height / 2)
        t.rotate(byDegrees: -CGFloat(q) * 90)
        t.translateX(by: -size.width / 2, yBy: -size.height / 2)
        t.concat()
        image.draw(at: .zero, from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        return out
    }

    @objc private func zoomIn() { imageScroll?.animator().magnification = min(16, (imageScroll?.magnification ?? 1) * 1.25) }
    @objc private func zoomOut() { imageScroll?.animator().magnification = max(0.05, (imageScroll?.magnification ?? 1) / 1.25) }
    @objc private func zoomActual() { imageScroll?.magnification = 1 }
    @objc private func zoomFit() {
        guard let scroll = imageScroll, let doc = scroll.documentView, doc.frame.width > 0, doc.frame.height > 0 else { return }
        let v = scroll.contentSize
        scroll.magnification = min(1, v.width / doc.frame.width, v.height / doc.frame.height)
    }
    @objc private func rotateLeft() { imageRotation -= 1; applyImage(); zoomFit() }
    @objc private func rotateRight() { imageRotation += 1; applyImage(); zoomFit() }

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
        if let t = markdownTemp { try? FileManager.default.removeItem(at: t) }
        player?.pause()
        Self.open.removeAll { $0 === self }
    }
}
