import AVFoundation
import Foundation
import ImageIO
import PDFKit
import TCCore

/// Vestavěné obsahové sloupce (obdoba WDX pluginů): rozměry obrázků, délka médií, počet stran PDF, počet řádků textu.
final class BuiltinContentColumns: ContentColumnProvider, @unchecked Sendable {
    let providerID = "builtin"
    let columns: [ContentColumn] = [
        ContentColumn(providerID: "builtin", id: "dimensions", title: "Rozměry", width: 100, rightAligned: true),
        ContentColumn(providerID: "builtin", id: "duration", title: "Délka", width: 80, rightAligned: true),
        ContentColumn(providerID: "builtin", id: "pages", title: "Stran", width: 60, rightAligned: true),
        ContentColumn(providerID: "builtin", id: "lines", title: "Řádků", width: 70, rightAligned: true),
    ]

    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "tiff", "tif", "heic", "bmp", "webp", "ico"]
    private static let mediaExts: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "mp4", "mov", "m4v", "avi", "mkv"]
    private static let textExts: Set<String> = ["txt", "md", "swift", "java", "py", "js", "ts", "c", "h", "cpp", "json", "xml", "html", "css", "csv", "log", "sh", "yml", "yaml"]

    func values(column: String, for urls: [URL]) -> [URL: String] {
        var out: [URL: String] = [:]
        for u in urls {
            let ext = u.pathExtension.lowercased()
            switch column {
            case "dimensions":
                guard Self.imageExts.contains(ext), let src = CGImageSourceCreateWithURL(u as CFURL, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                      let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int else { continue }
                out[u] = "\(w)×\(h)"
            case "duration":
                guard Self.mediaExts.contains(ext) else { continue }
                let s = CMTimeGetSeconds(AVURLAsset(url: u).duration)
                guard s.isFinite, s > 0 else { continue }
                let t = Int(s.rounded())
                out[u] = t >= 3600 ? String(format: "%d:%02d:%02d", t / 3600, t % 3600 / 60, t % 60) : String(format: "%d:%02d", t / 60, t % 60)
            case "pages":
                guard ext == "pdf", let doc = PDFDocument(url: u) else { continue }
                out[u] = String(doc.pageCount)
            case "lines":
                guard Self.textExts.contains(ext), let d = try? Data(contentsOf: u, options: .alwaysMapped), d.count < 50_000_000,
                      !ListerSupport.looksBinary(d) else { continue }
                out[u] = Fmt.bytes(Int64(d.reduce(0) { $1 == 10 ? $0 + 1 : $0 }) + (d.last == 10 || d.isEmpty ? 0 : 1))
            default: break
            }
        }
        return out
    }
}
