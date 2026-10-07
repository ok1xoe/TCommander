import AppKit
import QuickLookUI
import SwiftUI

struct QuickViewPane: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .normal)!
        v.autostarts = true
        return v
    }

    func updateNSView(_ v: QLPreviewView, context: Context) {
        let target = url as NSURL?
        if (v.previewItem as? NSURL) != target { v.previewItem = target }
    }

    static func dismantleNSView(_ v: QLPreviewView, coordinator: ()) { v.close() }
}
