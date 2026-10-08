#!/usr/bin/env swift
// Vykreslí ikonu aplikace (dva panely se seznamem souborů) do appstore/AppIcon.iconset a složí appstore/AppIcon.icns.
// Použití: swift scripts/make_icon.swift
import AppKit

func render(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

    // podložka (ikona macOS: čtverec 824/1024 s poloměrem ~185/1024)
    let inset = s * 100 / 1024, body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = s * 185 / 1024
    let base = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 12 / 1024), blur: s * 28 / 1024, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(base); ctx.setFillColor(NSColor(srgbRed: 0.10, green: 0.20, blue: 0.62, alpha: 1).cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(base); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(srgbRed: 0.16, green: 0.55, blue: 0.98, alpha: 1).cgColor, NSColor(srgbRed: 0.35, green: 0.22, blue: 0.86, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // dva panely
    func unit(_ v: CGFloat) -> CGFloat { s * v / 1024 }
    let panelW = unit(300), panelH = unit(520), gap = unit(36)
    let totalW = 2 * panelW + gap
    let x0 = (s - totalW) / 2, y0 = (s - panelH) / 2 - unit(6)
    for p in 0..<2 {
        let rect = CGRect(x: x0 + CGFloat(p) * (panelW + gap), y: y0, width: panelW, height: panelH)
        let path = CGPath(roundedRect: rect, cornerWidth: unit(34), cornerHeight: unit(34), transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -unit(8)), blur: unit(18), color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.addPath(path); ctx.setFillColor(NSColor.white.withAlphaComponent(0.97).cgColor); ctx.fillPath()
        ctx.restoreGState()
        // záhlaví
        let head = CGRect(x: rect.minX, y: rect.maxY - unit(78), width: rect.width, height: unit(78))
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        ctx.setFillColor(NSColor(srgbRed: 0.88, green: 0.91, blue: 0.97, alpha: 1).cgColor); ctx.fill(head); ctx.restoreGState()
        // řádky souborů
        let rows = 7
        for r in 0..<rows {
            let ry = rect.maxY - unit(122) - CGFloat(r) * unit(58)
            let widths: [CGFloat] = [190, 150, 210, 120, 170, 140, 180]
            let selected = (p == 0 && r == 2) || (p == 1 && r == 4)
            if selected {
                ctx.setFillColor(NSColor(srgbRed: 1.0, green: 0.62, blue: 0.18, alpha: 1).cgColor)
                ctx.fill(CGRect(x: rect.minX + unit(14), y: ry - unit(14), width: panelW - unit(28), height: unit(46)))
            }
            // ikona souboru + název
            let tint = selected ? NSColor.white : NSColor(srgbRed: 0.28, green: 0.40, blue: 0.80, alpha: 1)
            ctx.setFillColor(tint.cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: rect.minX + unit(30), y: ry - unit(6), width: unit(30), height: unit(30)), cornerWidth: unit(6), cornerHeight: unit(6), transform: nil)); ctx.fillPath()
            ctx.setFillColor((selected ? NSColor.white : NSColor(white: 0.55, alpha: 1)).cgColor)
            ctx.addPath(CGPath(roundedRect: CGRect(x: rect.minX + unit(76), y: ry + unit(2), width: unit(widths[r % widths.count] * 0.82), height: unit(14)), cornerWidth: unit(7), cornerHeight: unit(7), transform: nil)); ctx.fillPath()
        }
    }
    ctx.restoreGState()
    // jemný světlý okraj
    ctx.addPath(base); ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor); ctx.setLineWidth(unit(3)); ctx.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = FileManager.default.currentDirectoryPath
let set = root + "/appstore/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256),
                   ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(set)/\(name).png"))
}
let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil"); p.arguments = ["-c", "icns", set, "-o", root + "/appstore/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Hotovo: appstore/AppIcon.icns" : "iconutil selhal")
