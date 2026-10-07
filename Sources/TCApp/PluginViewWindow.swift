import AppKit
import TCCore
import WebKit

/// Zobrazení výstupu pluginu-prohlížeče (text, HTML nebo obrázek).
@MainActor
final class PluginViewWindow: NSObject, NSWindowDelegate {
    private static var open: [PluginViewWindow] = []

    /// Zkusí soubor zobrazit pluginem; vrací true, pokud nějaký plugin soubor převzal (i při chybě).
    static func tryShow(_ url: URL) -> Bool {
        guard let plugin = PluginHost.shared.viewerPlugin(for: url.lastPathComponent) else { return false }
        Task {
            let result = await Task.detached { Result { try PluginHost.shared.render(url, with: plugin) } }.value
            switch result {
            case .success(let r): PluginViewWindow(title: url.lastPathComponent + " – \(plugin.id)", result: r)
            case .failure(let e):
                Dialogs.error("Plugin „\(plugin.id)“ soubor nezobrazil", "\(e.localizedDescription)\n\nOtevírám ve vestavěném Listeru.")
                ListerWindow.show(url, skipPlugins: true)
            }
        }
        return true
    }

    private let window: NSWindow

    @discardableResult
    init(title: String, result: PluginHost.ViewResult) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = title
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let view: NSView
        switch result.kind {
        case "html":
            let w = WKWebView(); w.loadHTMLString(result.content, baseURL: nil); view = w
        case "image":
            let iv = NSImageView(image: NSImage(contentsOfFile: result.content) ?? NSImage()); iv.imageScaling = .scaleProportionallyUpOrDown; view = iv
        default:
            let scroll = NSScrollView(); let tv = NSTextView()
            tv.isEditable = false; tv.usesFindBar = true; tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            tv.autoresizingMask = [.width]; tv.string = result.content
            scroll.documentView = tv; scroll.hasVerticalScroller = true; view = scroll
        }
        view.frame = window.contentView!.bounds
        view.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(view)
        Self.open.append(self)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) { Self.open.removeAll { $0 === self } }
}
