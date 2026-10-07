import AppKit
import TCCore

/// Porovnání dvou textových souborů vedle sebe: rozdíly, přenos bloku doleva/doprava a uložení změn.
/// Binární soubory se porovnávají po bajtech (`BinaryCompareWindow`).
@MainActor
final class FileCompareWindow: NSObject, NSWindowDelegate {
    private static var open: [FileCompareWindow] = []

    static func show(_ left: URL, _ right: URL) {
        guard let leftData = try? Data(contentsOf: left, options: .alwaysMapped), let rightData = try? Data(contentsOf: right, options: .alwaysMapped) else {
            Dialogs.error("Porovnání", "Soubor nelze přečíst."); return
        }
        if ListerSupport.looksBinary(leftData.prefix(8192)) || ListerSupport.looksBinary(rightData.prefix(8192)) {
            BinaryCompareWindow.show(left, right, leftData, rightData); return
        }
        func lines(_ d: Data) -> (lines: [String], encoding: String) {
            let dec = TextDecoding.decode(d)
            return (dec.text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }, dec.encoding)
        }
        let (a, ea) = lines(leftData), (b, eb) = lines(rightData)
        guard let ops = LineDiff.diff(a, b) else { Dialogs.error("Porovnání", "Soubory se příliš liší pro zobrazení rozdílů."); return }
        let w = FileCompareWindow(left: left, right: right, rows: LineDiff.sideBySide(a, b, ops), leftEncoding: ea, rightEncoding: eb)
        open.append(w)
        w.window.makeKeyAndOrderFront(nil)
    }

    private let leftURL: URL, rightURL: URL
    private let leftEncoding: String, rightEncoding: String
    private var rows: [LineDiff.Row]
    private var leftDirty = false, rightDirty = false
    private let window: NSWindow
    private let leftView = NSTextView(), rightView = NSTextView()
    private let leftScroll = NSScrollView(), rightScroll = NSScrollView()
    private let status = NSTextField(labelWithString: "")
    private let toRightButton = NSButton(title: "Blok → doprava", target: nil, action: nil)
    private let toLeftButton = NSButton(title: "← Blok doleva", target: nil, action: nil)
    private let saveLeft = NSButton(title: "Uložit levý", target: nil, action: nil)
    private let saveRight = NSButton(title: "Uložit pravý", target: nil, action: nil)
    private var cursorBlock = -1
    private var syncing = false

    private init(left: URL, right: URL, rows: [LineDiff.Row], leftEncoding: String, rightEncoding: String) {
        leftURL = left; rightURL = right; self.rows = rows
        self.leftEncoding = leftEncoding; self.rightEncoding = rightEncoding
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        for (tv, sv) in [(leftView, leftScroll), (rightView, rightScroll)] {
            tv.isEditable = false; tv.isRichText = true; tv.isSelectable = true
            tv.isHorizontallyResizable = true; tv.textContainer?.widthTracksTextView = false
            tv.textContainer?.containerSize = NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
            sv.documentView = tv; sv.hasVerticalScroller = true; sv.hasHorizontalScroller = true
            sv.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: sv.contentView)
        }
        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin
        split.addArrangedSubview(leftScroll); split.addArrangedSubview(rightScroll)
        split.setHoldingPriority(.defaultLow, forSubviewAt: 0); split.setHoldingPriority(.defaultLow, forSubviewAt: 1)

        let prev = NSButton(title: "◀︎ Předchozí rozdíl", target: self, action: #selector(previousDiff))
        let next = NSButton(title: "Další rozdíl ▶︎", target: self, action: #selector(nextDiff))
        toRightButton.target = self; toRightButton.action = #selector(copyToRight)
        toLeftButton.target = self; toLeftButton.action = #selector(copyToLeft)
        saveLeft.target = self; saveLeft.action = #selector(saveLeftAction)
        saveRight.target = self; saveRight.action = #selector(saveRightAction)
        let bar = NSStackView(views: [status, NSView(), toLeftButton, toRightButton, prev, next, saveLeft, saveRight]); bar.spacing = 8
        let c = window.contentView!
        for v in [split, bar] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; c.addSubview(v) }
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: c.topAnchor), split.leadingAnchor.constraint(equalTo: c.leadingAnchor), split.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            bar.topAnchor.constraint(equalTo: split.bottomAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 12), bar.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -10),
        ])
        render()
        // rozdělení na dvě stejné poloviny (až po rozložení okna)
        DispatchQueue.main.async { [weak split] in split?.setPosition((split?.bounds.width ?? 1200) / 2, ofDividerAt: 0) }
    }

    // MARK: Zobrazení

    private func render() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let placeholder = NSColor.secondaryLabelColor.withAlphaComponent(0.12)
        let red = NSColor.systemRed.withAlphaComponent(0.22), green = NSColor.systemGreen.withAlphaComponent(0.22), yellow = NSColor.systemYellow.withAlphaComponent(0.30)
        let l = NSMutableAttributedString(), r = NSMutableAttributedString()
        func add(_ s: NSMutableAttributedString, _ text: String?, _ bg: NSColor?) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            if let bg { attrs[.backgroundColor] = bg }
            s.append(NSAttributedString(string: (text ?? "") + "\n", attributes: attrs))
        }
        for row in rows {
            switch row.kind {
            case .same: add(l, row.left, nil); add(r, row.right, nil)
            case .changed: add(l, row.left, yellow); add(r, row.right, yellow)
            case .onlyLeft: add(l, row.left, red); add(r, nil, placeholder)
            case .onlyRight: add(l, nil, placeholder); add(r, row.right, green)
            }
        }
        let keep = leftScroll.contentView.bounds.origin
        leftView.textStorage?.setAttributedString(l); rightView.textStorage?.setAttributedString(r)
        leftScroll.contentView.scroll(to: keep); rightScroll.contentView.scroll(to: keep)
        updateStatus()
    }

    private func updateStatus() {
        let n = DiffMerge.blocks(rows).count
        status.stringValue = n == 0 ? "Soubory jsou shodné" : "Počet bloků rozdílů: \(n)"
        toLeftButton.isEnabled = n > 0; toRightButton.isEnabled = n > 0
        saveLeft.isEnabled = leftDirty; saveRight.isEnabled = rightDirty
        window.title = "Porovnání: \(leftURL.lastPathComponent)\(leftDirty ? " •" : "") ↔ \(rightURL.lastPathComponent)\(rightDirty ? " •" : "")"
        window.isDocumentEdited = leftDirty || rightDirty
    }

    @objc private func scrolled(_ n: Notification) {
        guard !syncing, let src = n.object as? NSClipView else { return }
        let other = src === leftScroll.contentView ? rightScroll.contentView : leftScroll.contentView
        syncing = true
        other.scroll(to: src.bounds.origin)
        other.superview.flatMap { ($0 as? NSScrollView)?.reflectScrolledClipView(other) }
        syncing = false
    }

    // MARK: Navigace mezi rozdíly

    private func lineIndex(in view: NSTextView) -> Int {
        let loc = min(view.selectedRange().location, (view.string as NSString).length)
        return (view.string as NSString).substring(to: loc).filter { $0 == "\n" }.count
    }

    private func jump(to block: Int) {
        let blocks = DiffMerge.blocks(rows)
        guard blocks.indices.contains(block) else { return }
        cursorBlock = block
        let line = blocks[block].lowerBound
        let ns = leftView.string as NSString
        var idx = 0, offset = 0
        while idx < line, offset < ns.length { offset = NSMaxRange(ns.lineRange(for: NSRange(location: offset, length: 0))); idx += 1 }
        let range = NSRange(location: min(offset, max(0, ns.length - 1)), length: 0)
        leftView.setSelectedRange(range)
        rightView.setSelectedRange(range)
        leftView.scrollRangeToVisible(range)
        let y = leftScroll.contentView.bounds.origin.y
        leftScroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, y - 80)))
        leftScroll.reflectScrolledClipView(leftScroll.contentView)
    }

    @objc private func nextDiff() { jump(to: min(cursorBlock + 1, DiffMerge.blocks(rows).count - 1)) }
    @objc private func previousDiff() { jump(to: max(cursorBlock - 1, 0)) }

    // MARK: Úpravy

    private func currentBlock() -> Range<Int>? {
        let blocks = DiffMerge.blocks(rows)
        if blocks.indices.contains(cursorBlock) { return blocks[cursorBlock] }
        let line = max(lineIndex(in: leftView), lineIndex(in: rightView))
        return DiffMerge.block(containing: line, in: rows)
    }

    private func transfer(toRight: Bool) {
        guard let block = currentBlock() else { return }
        rows = DiffMerge.apply(rows, block: block, toRight: toRight)
        if toRight { rightDirty = true } else { leftDirty = true }
        cursorBlock = min(cursorBlock, DiffMerge.blocks(rows).count - 1)
        render()
    }

    @objc private func copyToRight() { transfer(toRight: true) }
    @objc private func copyToLeft() { transfer(toRight: false) }

    private func save(right: Bool) -> Bool {
        let url = right ? rightURL : leftURL
        let enc = right ? rightEncoding : leftEncoding
        let text = DiffMerge.lines(rows, right: right).joined(separator: "\n")
        var data = TextDecoding.encode(text, as: enc)
        if data == nil {
            guard Dialogs.confirm(title: "Text nelze uložit v kódování \(enc)", message: "Uložit jako UTF-8?", ok: "Uložit jako UTF-8") else { return false }
            data = Data(text.utf8)
        }
        do { try data!.write(to: url, options: .atomic) } catch { Dialogs.error("Uložení selhalo", error.localizedDescription); return false }
        if right { rightDirty = false } else { leftDirty = false }
        updateStatus()
        return true
    }

    @objc private func saveLeftAction() { _ = save(right: false) }
    @objc private func saveRightAction() { _ = save(right: true) }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard leftDirty || rightDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Uložit změny?"
        alert.informativeText = [leftDirty ? leftURL.lastPathComponent : nil, rightDirty ? rightURL.lastPathComponent : nil].compactMap { $0 }.joined(separator: ", ")
        alert.addButton(withTitle: "Uložit"); alert.addButton(withTitle: "Zahodit změny"); alert.addButton(withTitle: "Zrušit")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            var ok = true
            if leftDirty { ok = save(right: false) && ok }
            if rightDirty { ok = save(right: true) && ok }
            return ok
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        Self.open.removeAll { $0 === self }
    }
}

/// Porovnání binárních souborů po bajtech: shrnutí a seznam rozdílných 16bajtových řádků vedle sebe.
@MainActor
final class BinaryCompareWindow: NSObject, NSWindowDelegate {
    private static var open: [BinaryCompareWindow] = []

    static func show(_ left: URL, _ right: URL, _ a: Data, _ b: Data) {
        let r = BinaryDiff.compare(a, b)
        if r.identical { Dialogs.error("Porovnání binárních souborů", "Soubory jsou shodné (\(Fmt.bytes(Int64(a.count))) bajtů)."); return }
        var out = "\(left.lastPathComponent): \(Fmt.bytes(Int64(a.count))) bajtů\n\(right.lastPathComponent): \(Fmt.bytes(Int64(b.count))) bajtů\n"
        out += r.sameSize ? "Rozdílných bajtů: \(Fmt.bytes(Int64(r.differingBytes)))\n" : "Velikosti se liší; rozdílných nebo chybějících bajtů: \(Fmt.bytes(Int64(r.differingBytes)))\n"
        if r.truncated { out += "(zobrazeno prvních \(r.rows.count) rozdílných řádků)\n" }
        out += "\nOffset    \(String(left.lastPathComponent.prefix(24)).padding(toLength: 52, withPad: " ", startingAt: 0))\(String(right.lastPathComponent.prefix(24)))\n"
        for row in r.rows {
            let l = HexDump.row(a, index: row), rr = HexDump.row(b, index: row)
            out += "\(l.offset)  \(l.hex.padding(toLength: 50, withPad: " ", startingAt: 0))  \(rr.hex)\n"
        }
        let w = BinaryCompareWindow(title: "Porovnání bajtů: \(left.lastPathComponent) ↔ \(right.lastPathComponent)", text: out)
        open.append(w)
        w.window.makeKeyAndOrderFront(nil)
    }

    private let window: NSWindow

    private init(title: String, text: String) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let scroll = NSScrollView(); let tv = NSTextView()
        tv.isEditable = false; tv.usesFindBar = true; tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        tv.isHorizontallyResizable = true; tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
        tv.string = text
        scroll.documentView = tv; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.frame = window.contentView!.bounds; scroll.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(scroll)
    }

    func windowWillClose(_ notification: Notification) { Self.open.removeAll { $0 === self } }
}
