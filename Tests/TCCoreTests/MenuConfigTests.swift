import Testing
import Foundation
@testable import TCCore

@Suite struct MenuConfigTests {
    func item(_ t: String) -> CustomMenuItem { CustomMenuItem(title: t, command: "cm_x") }

    @Test func buildsSubmenusAndSeparatorsInOrder() {
        // položky stejného podmenu se spojí na místě prvního výskytu; oddělovač mezi nimi zůstane na vnější úrovni
        let tree = MenuNode.tree(from: [item("První"), item("Nástroje/A"), item("-"), item("Nástroje/B"), item("Nástroje/Vnořené/C")])
        #expect(tree.count == 3)
        guard case .item(let first) = tree[0], first.title == "První" else { Issue.record("první položka"); return }
        guard case .submenu(let name, let kids) = tree[1], name == "Nástroje", kids.count == 3 else { Issue.record("podmenu"); return }
        guard case .item(let a) = kids[0], case .item(let b) = kids[1], case .submenu(let inner, let innerKids) = kids[2] else { Issue.record("obsah podmenu"); return }
        #expect(a.title == "A" && b.title == "B" && inner == "Vnořené" && innerKids.count == 1)
        if case .separator = tree[2] {} else { Issue.record("oddělovač") }
    }

    @Test func ignoresEmptyTitlesAndTrimsPaths() {
        let tree = MenuNode.tree(from: [item(""), item(" / "), item(" A / B ")])
        #expect(tree.count == 1)
        guard case .submenu(let n, let k) = tree[0], n == "A", case .item(let leaf) = k[0] else { Issue.record("strom"); return }
        #expect(leaf.title == "B")
    }

    @Test func decodingToleratesMissingAndInvalidFields() throws {
        let c = try JSONDecoder().decode(MainMenuConfig.self, from: Data(#"{"customTitle":"X","hidden":["Soubor/Otevřít"]}"#.utf8))
        #expect(c.customTitle == "X" && c.customItems.isEmpty && !c.isVisible("Soubor/Otevřít") && c.isVisible("Soubor/Nový soubor…"))
        let d = try JSONDecoder().decode(MainMenuConfig.self, from: Data("{}".utf8))
        #expect(d == MainMenuConfig())
        let e = try JSONDecoder().decode(MainMenuConfig.self, from: Data(#"{"customItems":"nesmysl","hidden":5}"#.utf8))
        #expect(e == MainMenuConfig())
    }

    @Test func roundTripsThroughJSON() throws {
        let c = MainMenuConfig(customTitle: "Moje", customItems: [CustomMenuItem(title: "A/B", command: "cm_copy", parameters: "x", shortcut: "ctrl+k")], hidden: ["Zobrazení/Zpět"])
        #expect(try JSONDecoder().decode(MainMenuConfig.self, from: JSONEncoder().encode(c)) == c)
    }

    @Test func catalogIsUniqueAndMatchesTheHideableItemsInTheMenuSource() throws {
        #expect(Set(MainMenuCatalog.items).count == MainMenuCatalog.items.count)
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/TCApp/MacTCApp.swift")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        let re = try NSRegularExpression(pattern: #"\.hideable\(model, "((?:[^"\\]|\\.)*)"\)"#)
        let used = Set(re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range(at: 1)) })
        #expect(used == Set(MainMenuCatalog.items), "rozdíl: \(used.symmetricDifference(Set(MainMenuCatalog.items)))")
    }
}
