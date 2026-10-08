import Testing
import Foundation

/// Texty pro App Store Connect musí splňovat limity obchodu (jinak je formulář odmítne).
@Suite struct AppStoreMetadataTests {
    static let limits: [String: Int] = ["name": 30, "subtitle": 30, "promotional_text": 170, "keywords": 100, "description": 4000, "release_notes": 4000]
    static var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("appstore/metadata") }

    @Test func everyLocaleHasAllFieldsWithinTheLimits() throws {
        for locale in ["en-US", "cs"] {
            for (field, limit) in Self.limits {
                let url = Self.root.appendingPathComponent("\(locale)/\(field).txt")
                let text = try String(contentsOf: url, encoding: .utf8)
                #expect(!text.isEmpty, "\(locale)/\(field) je prázdný")
                #expect(text.count <= limit, "\(locale)/\(field): \(text.count) > \(limit) znaků")
                #expect(text == text.trimmingCharacters(in: .whitespacesAndNewlines) || field == "description", "\(locale)/\(field) má okolní mezery")
            }
        }
    }

    @Test func keywordsAreCommaSeparatedWithoutSpacesAfterCommas() throws {
        for locale in ["en-US", "cs"] {
            let k = try String(contentsOf: Self.root.appendingPathComponent("\(locale)/keywords.txt"), encoding: .utf8)
            #expect(!k.contains(", ") && !k.contains(" ,"), "\(locale): mezery kolem čárek zbytečně zabírají znaky")
            let words = k.split(separator: ",").map(String.init)
            #expect(Set(words.map { $0.lowercased() }).count == words.count, "\(locale): duplicitní klíčová slova")
        }
    }

    @Test func descriptionsDoNotMentionFeaturesTheSandboxEditionLacks() throws {
        for locale in ["en-US", "cs"] {
            let d = try String(contentsOf: Self.root.appendingPathComponent("\(locale)/description.txt"), encoding: .utf8).lowercased()
            for banned in ["sftp", "plugin", "plantuml"] { #expect(!d.contains(banned), "\(locale): popis slibuje „\(banned)“, které edice z App Store nemá") }
        }
    }
}
