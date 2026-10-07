import AppKit
import SwiftUI

/// Poloha aktivní položky v pásu (v souřadnicích pásu); pás ji podle potřeby odroluje do viditelné oblasti.
struct ActiveFrameKey: PreferenceKey {
    static var defaultValue: CGRect? { nil }
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

extension View {
    /// Označí položku pásu jako aktivní, aby ji `ScrollStrip` udržel viditelnou.
    func stripActive(_ active: Bool) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: ActiveFrameKey.self, value: active ? g.frame(in: .named(ScrollStrip<EmptyView>.space)) : nil) })
    }
}

/// Vodorovný pás (záložky, disky), který se nikdy nerozšíří přes šířku panelu: přetékající položky se rolují kolečkem, gestem
/// nebo šipkami vlevo a vpravo na krajích (zobrazí se jen když se obsah nevejde).
struct ScrollStrip<Content: View>: NSViewRepresentable {
    static var space: String { "tc-scroll-strip" }
    let content: Content

    init(@ViewBuilder _ content: () -> Content) { self.content = content() }

    func makeNSView(context: Context) -> StripView { StripView() }

    func updateNSView(_ view: StripView, context: Context) {
        view.setContent(AnyView(content.coordinateSpace(name: Self.space).onPreferenceChange(ActiveFrameKey.self) { [weak view] rect in view?.reveal(rect) }))
    }

    /// Šířku určuje vždy nabídnutá šířka (ne obsah), výška je výška obsahu.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: StripView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: nsView.contentHeight)
    }
}

final class StripView: NSView {
    private let scroll = HorizontalScrollView()
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private let left = StripView.arrowButton("chevron.left", tip: "Doleva")
    private let right = StripView.arrowButton("chevron.right", tip: "Doprava")
    private var pendingReveal: CGRect?
    private static let arrowWidth: CGFloat = 20

    var contentHeight: CGFloat { max(host.fittingSize.height, 1) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.documentView = host
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        left.target = self; left.action = #selector(scrollLeft)
        right.target = self; right.action = #selector(scrollRight)
        for v in [scroll, left, right] as [NSView] { addSubview(v) }
        wantsLayer = true; layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }
    deinit { NotificationCenter.default.removeObserver(self) }

    private static func arrowButton(_ symbol: String, tip: String) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip) ?? NSImage(), target: nil, action: nil)
        b.isBordered = false; b.imagePosition = .imageOnly; b.toolTip = tip
        b.contentTintColor = .secondaryLabelColor
        b.focusRingType = .none; b.refusesFirstResponder = true
        return b
    }

    func setContent(_ view: AnyView) {
        host.rootView = view
        needsLayout = true
    }

    /// Odroluje tak, aby byl daný rámec (aktivní položka) vidět.
    func reveal(_ rect: CGRect?) {
        guard let rect else { return }
        pendingReveal = rect
        DispatchQueue.main.async { [weak self] in self?.applyReveal() }
    }

    private func applyReveal() {
        guard let rect = pendingReveal else { return }
        pendingReveal = nil
        let visible = scroll.contentView.bounds
        guard host.frame.width > visible.width else { return }
        var x = visible.origin.x
        if rect.minX - 6 < visible.minX { x = rect.minX - 6 }
        else if rect.maxX + 6 > visible.maxX { x = rect.maxX + 6 - visible.width }
        scrollTo(x)
    }

    override func layout() {
        super.layout()
        let size = host.fittingSize
        host.setFrameSize(NSSize(width: max(size.width, 1), height: bounds.height))
        let overflow = size.width > bounds.width + 0.5
        left.isHidden = !overflow; right.isHidden = !overflow
        let inset = overflow ? Self.arrowWidth : 0
        left.frame = NSRect(x: 0, y: 0, width: Self.arrowWidth, height: bounds.height)
        right.frame = NSRect(x: bounds.width - Self.arrowWidth, y: 0, width: Self.arrowWidth, height: bounds.height)
        scroll.frame = NSRect(x: inset, y: 0, width: max(0, bounds.width - 2 * inset), height: bounds.height)
        host.setFrameSize(NSSize(width: max(size.width, 1), height: bounds.height))
        clampOffset()
        updateArrows()
    }

    private func maxOffset() -> CGFloat { max(0, host.frame.width - scroll.contentView.bounds.width) }

    private func clampOffset() {
        let x = min(max(0, scroll.contentView.bounds.origin.x), maxOffset())
        if x != scroll.contentView.bounds.origin.x { scroll.contentView.setBoundsOrigin(NSPoint(x: x, y: 0)) }
    }

    private func scrollTo(_ x: CGFloat, animated: Bool = true) {
        let target = NSPoint(x: min(max(0, x), maxOffset()), y: 0)
        if animated { NSAnimationContext.runAnimationGroup { $0.duration = 0.18; scroll.contentView.animator().setBoundsOrigin(target) } }
        else { scroll.contentView.setBoundsOrigin(target) }
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    @objc private func scrolled() { updateArrows() }

    private func updateArrows() {
        let x = scroll.contentView.bounds.origin.x
        left.isEnabled = x > 0.5; right.isEnabled = x < maxOffset() - 0.5
        left.alphaValue = left.isEnabled ? 1 : 0.3; right.alphaValue = right.isEnabled ? 1 : 0.3
    }

    @objc private func scrollLeft() { scrollTo(scroll.contentView.bounds.origin.x - scroll.contentView.bounds.width * 0.7) }
    @objc private func scrollRight() { scrollTo(scroll.contentView.bounds.origin.x + scroll.contentView.bounds.width * 0.7) }
}

/// NSScrollView, který svislé kolečko myši převádí na vodorovné rolování.
private final class HorizontalScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        let dx = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        guard let doc = documentView else { return }
        let maxX = max(0, doc.frame.width - contentView.bounds.width)
        let x = min(max(0, contentView.bounds.origin.x - dx), maxX)
        contentView.setBoundsOrigin(NSPoint(x: x, y: 0))
        reflectScrolledClipView(contentView)
    }
}
