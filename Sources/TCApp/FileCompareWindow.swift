import AppKit
import TCCore

@MainActor
final class FileCompareWindow: NSObject, NSWindowDelegate {
    private static var open: [FileCompareWindow] = []

    static func show(_ left: URL, _ right: URL) {
        guard let leftData = try? Data(contentsOf: left, options: .alwaysMapped), let rightData = try? Data(contentsOf: right, options: .alwaysMapped) else {
            Dialogs.error("Porovnání", "Soubor nelze přečíst."); return
        }
        if ListerSupport.looksBinary(leftData.prefix(8192)) || ListerSupport.looksBinary(rightData.prefix(8192)) {
            Dialogs.error("Porovnání binárních souborů", leftData == rightData ? "Soubory jsou shodné." : "Soubory se liší.")
            return
        }
        func lines(_ d: Data) -> [String] {
            TextDecoding.decode(d).text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        }
        let a = lines(leftData), b = lines(rightData)
        guard let ops = LineDiff.diff(a, b) else { Dialogs.error("Porovnání", "Soubory se příliš liší pro zobrazení rozdílů."); return }
        let w = FileCompareWindow(left: left, right: right, rows: LineDiff.sideBySide(a, b, ops))
        open.append(w)
        w.window.makeKeyAndOrderFront(nil)
    }

    private let window: NSWindow
    private let leftView = NSTextView(), rightView = NSTextView()
    private let leftScroll = NSScrollView(), rightScroll = NSScrollView()
    private var blockStarts: [Int] = []       // čísla řádků, kde začíná blok rozdílů
    private var cursorBlock = -1
    private var syncing = false

    private init(left: URL, right: URL, rows: [LineDiff.Row]) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 700),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Porovnání: \(left.lastPathComponent) ↔ \(right.lastPathComponent)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let placeholder = NSColor.secondaryLabelColor.withAlphaComponent(0.12)
        let red = NSColor.systemRed.withAlphaComponent(0.22), green = NSColor.systemGreen.withAlphaComponent(0.22)
        let yellow = NSColor.systemYellow.withAlphaComponent(0.30)
        let l = NSMutableAttributedString(), r = NSMutableAttributedString()
        func add(_ s: NSMutableAttributedString, _ text: String?, _ bg: NSColor?) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            if let bg { attrs[.backgroundColor] = bg }
            s.append(NSAttributedString(string: (text ?? "") + "\n", attributes: attrs))
        }
        var diffCount = 0, inBlock = false
        for (i, row) in rows.enumerated() {
            switch row.kind {
            case .same: add(l, row.left, nil); add(r, row.right, nil); inBlock = false
            case .changed: add(l, row.left, yellow); add(r, row.right, yellow)
            case .onlyLeft: add(l, row.left, red); add(r, nil, placeholder)
            case .onlyRight: add(l, nil, placeholder); add(r, row.right, green)
            }
            if row.kind != .same { if !inBlock { blockStarts.append(i); diffCount += 1 }; inBlock = true }
        }
        for (tv, sv, text) in [(leftView, leftScroll, l), (rightView, rightScroll, r)] {
            tv.isEditable = false; tv.isRichText = true; tv.textStorage?.setAttributedString(text)
            tv.isHorizontallyResizable = true; tv.textContainer?.widthTracksTextView = false
            tv.textContainer?.containerSize = NSSize(width: 100_000, height: CGFloat.greatestFiniteMagnitude)
            sv.documentView = tv; sv.hasVerticalScroller = true; sv.hasHorizontalScroller = true
            sv.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled(_:)), name: NSView.boundsDidChangeNotification, object: sv.contentView)
        }
        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin
        split.addArrangedSubview(leftScroll); split.addArrangedSubview(rightScroll)

        let prev = NSButton(title: "◀︎ Předchozí rozdíl", target: self, action: #selector(previousDiff))
        let next = NSButton(title: "Další rozdíl ▶︎", target: self, action: #selector(nextDiff))
        next.keyEquivalent = "\r"
        let status = NSTextField(labelWithString: diffCount == 0 ? "Soubory jsou shodné" : "Počet bloků rozdílů: \(diffCount)")
        let bar = NSStackView(views: [status, NSView(), prev, next]); bar.spacing = 8
        let c = window.contentView!
        for v in [split, bar] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; c.addSubview(v) }
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: c.topAnchor), split.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            bar.topAnchor.constraint(equalTo: split.bottomAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 12), bar.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -10),
        ])
        next.isEnabled = diffCount > 0; prev.isEnabled = diffCount > 0
    }

    @objc private func scrolled(_ n: Notification) {
        guard !syncing, let src = n.object as? NSClipView else { return }
        let other = src === leftScroll.contentView ? rightScroll.contentView : leftScroll.contentView
        syncing = true
        other.scroll(to: src.bounds.origin)
        other.superview.flatMap { ($0 as? NSScrollView)?.reflectScrolledClipView(other) }
        syncing = false
    }

    private func jump(to block: Int) {
        guard blockStarts.indices.contains(block) else { return }
        cursorBlock = block
        let line = blockStarts[block]
        let ns = leftView.string as NSString
        var idx = 0, offset = 0
        while idx < line, offset < ns.length { offset = NSMaxRange(ns.lineRange(for: NSRange(location: offset, length: 0))); idx += 1 }
        leftView.scrollRangeToVisible(NSRange(location: min(offset, max(0, ns.length - 1)), length: 0))
        let y = leftScroll.contentView.bounds.origin.y
        leftScroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, y - 80)))
        leftScroll.reflectScrolledClipView(leftScroll.contentView)
    }

    @objc private func nextDiff() { jump(to: min(cursorBlock + 1, blockStarts.count - 1)) }
    @objc private func previousDiff() { jump(to: max(cursorBlock - 1, 0)) }

    func windowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        Self.open.removeAll { $0 === self }
    }
}
