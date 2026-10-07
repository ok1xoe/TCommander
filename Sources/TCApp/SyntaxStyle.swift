import AppKit
import TCCore

/// Barvy zvýrazněné syntaxe (přizpůsobují se světlému i tmavému vzhledu) a jejich aplikace na text.
enum SyntaxStyle {
    static let maxLength = 2 * 1024 * 1024          // větší texty se nezvýrazňují (plynulost)

    static func color(_ kind: SyntaxKind) -> NSColor {
        func c(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
            NSColor(name: nil) { a in
                let v = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
                return NSColor(srgbRed: v.0, green: v.1, blue: v.2, alpha: 1)
            }
        }
        switch kind {
        case .keyword: return c((0.68, 0.14, 0.64), (0.99, 0.37, 0.64))
        case .string: return c((0.77, 0.10, 0.09), (0.99, 0.42, 0.36))
        case .comment: return c((0.42, 0.47, 0.50), (0.50, 0.55, 0.60))
        case .number: return c((0.11, 0.00, 0.81), (0.82, 0.75, 0.40))
        case .type: return c((0.11, 0.43, 0.50), (0.36, 0.78, 0.86))
        case .preprocessor: return c((0.39, 0.22, 0.12), (0.99, 0.56, 0.25))
        case .tag: return c((0.13, 0.43, 0.54), (0.36, 0.78, 0.86))
        case .attribute: return c((0.45, 0.35, 0.00), (0.80, 0.69, 0.40))
        }
    }

    @MainActor
    static func apply(to storage: NSTextStorage, language: String, baseFont: NSFont) {
        let length = storage.length
        guard length > 0, length <= maxLength else { return }
        let all = NSRange(location: 0, length: length)
        let bold = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: all)
        storage.addAttribute(.font, value: baseFont, range: all)
        for t in SyntaxHighlighter.tokens(in: storage.string, language: language) where NSMaxRange(t.range) <= length {
            storage.addAttribute(.foregroundColor, value: color(t.kind), range: t.range)
            if t.kind == .keyword { storage.addAttribute(.font, value: bold, range: t.range) }
        }
        storage.endEditing()
    }
}
