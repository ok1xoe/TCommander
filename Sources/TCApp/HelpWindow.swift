import AppKit
import TCCore
import WebKit

/// Nápověda v aplikaci: uživatelská příručka (stejné stránky jako na webu) z balíčku aplikace v okně s prohlížečem.
@MainActor
final class HelpWindow: NSObject, NSWindowDelegate, WKNavigationDelegate {
    static let siteURL = URL(string: "https://ok1xoe.github.io/TCommander/")!
    static let issuesURL = URL(string: "https://github.com/ok1xoe/TCommander/issues")!
    private static var current: HelpWindow?

    /// Složka s nápovědou (`docs/<jazyk>/…`, `assets/…`): v balíčku `Resources/Help`, při vývoji `site/` vedle zdrojů.
    static func locateHelp(resources: URL? = Bundle.main.resourceURL, executable: URL? = Bundle.main.executableURL) -> URL? {
        let fm = FileManager.default
        if let r = resources?.appendingPathComponent("Help"), fm.fileExists(atPath: r.appendingPathComponent("docs").path) { return r }
        var dir = executable?.deletingLastPathComponent()
        for _ in 0..<8 {
            guard let d = dir else { break }
            let site = d.appendingPathComponent("site")
            if fm.fileExists(atPath: site.appendingPathComponent("docs").path) { return site }
            dir = d.deletingLastPathComponent()
        }
        return nil
    }

    /// Adresa stránky příručky (`index.html`, `12-shortcuts.html`, `privacy.html`, …) v jazyce aplikace; angličtina, pokud česká chybí.
    static func pageURL(_ page: String, help: URL, language: String) -> URL {
        let fm = FileManager.default
        let preferred = help.appendingPathComponent("docs/\(language)/\(page)")
        return fm.fileExists(atPath: preferred.path) ? preferred : help.appendingPathComponent("docs/en/\(page)")
    }

    /// Otevře nápovědu na dané stránce; bez příručky v balíčku otevře web.
    static func show(page: String = "index.html") {
        guard let help = locateHelp() else { NSWorkspace.shared.open(siteURL); return }
        let url = pageURL(page, help: help, language: AppModel.shared.settings.language)
        if let w = current { w.load(url, root: help); w.window.makeKeyAndOrderFront(nil); return }
        let w = HelpWindow(root: help)
        current = w
        w.load(url, root: help)
        w.window.makeKeyAndOrderFront(nil)
    }

    private let window: NSWindow
    private let web: WKWebView
    private var root: URL
    private let back = NSButton(title: "◀︎", target: nil, action: nil), forward = NSButton(title: "▶︎", target: nil, action: nil)
    private let home = NSButton(title: "Domů", target: nil, action: nil), site = NSButton(title: "Web", target: nil, action: nil)

    private init(root: URL) {
        self.root = root
        let cfg = WKWebViewConfiguration()
        web = WKWebView(frame: .zero, configuration: cfg)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "TCommander – " + L("Nápověda")
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("TCommanderHelp")
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = true
        back.target = self; back.action = #selector(goBack); back.toolTip = "Zpět"
        forward.target = self; forward.action = #selector(goForward); forward.toolTip = "Vpřed"
        home.target = self; home.action = #selector(goHome); site.target = self; site.action = #selector(openSite)
        site.toolTip = "Otevřít web aplikace"
        for b in [back, forward, home, site] { b.bezelStyle = .rounded; b.controlSize = .small }
        let bar = NSStackView(views: [back, forward, home, NSView(), site]); bar.spacing = 6; bar.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        let content = window.contentView!
        for v in [bar, web] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v) }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: content.topAnchor), bar.leadingAnchor.constraint(equalTo: content.leadingAnchor), bar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            web.topAnchor.constraint(equalTo: bar.bottomAnchor), web.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: content.trailingAnchor), web.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }

    private func load(_ url: URL, root: URL) {
        self.root = root
        web.loadFileURL(url, allowingReadAccessTo: root)
    }

    @objc private func goBack() { web.goBack() }
    @objc private func goForward() { web.goForward() }
    @objc private func goHome() {
        load(Self.pageURL("index.html", help: root, language: AppModel.shared.settings.language), root: root)
    }
    @objc private func openSite() { NSWorkspace.shared.open(Self.siteURL) }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated, let target = navigationAction.request.url else { decisionHandler(.allow); return }
        if target.isFileURL { decisionHandler(.allow); return }              // stránky příručky
        decisionHandler(.cancel)
        NSWorkspace.shared.open(target)                                       // web, GitHub, e-mail → v prohlížeči
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        back.isEnabled = web.canGoBack; forward.isEnabled = web.canGoForward
        if let t = web.title, !t.isEmpty { window.title = t }
    }

    func windowWillClose(_ notification: Notification) { Self.current = nil }
}
