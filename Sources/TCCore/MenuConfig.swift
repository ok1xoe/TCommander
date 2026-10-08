import Foundation

/// Vlastní položka hlavního menu. Název může obsahovat cestu „Podmenu/Položka“; samotné „-“ je oddělovač.
public struct CustomMenuItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// „cm_*“ (interní příkaz), „em_*“ (uživatelský příkaz) nebo shellový příkaz.
    public var command: String
    public var parameters: String
    /// Zkratka ve tvaru jako v záložce Zkratky (např. „ctrl+shift+k“); prázdná = bez zkratky.
    public var shortcut: String
    public init(id: UUID = UUID(), title: String, command: String = "", parameters: String = "", shortcut: String = "") {
        self.id = id; self.title = title; self.command = command; self.parameters = parameters; self.shortcut = shortcut
    }
    public var isSeparator: Bool { title.trimmingCharacters(in: .whitespaces) == "-" }
}

/// Uspořádání hlavního menu: skrytí vestavěných položek a vlastní menu s položkami, podmenu a oddělovači.
public struct MainMenuConfig: Codable, Equatable, Sendable {
    /// Název vlastního menu; prázdný = výchozí „Vlastní“ / „Custom“ podle jazyka.
    public var customTitle: String
    public var customItems: [CustomMenuItem]
    /// Klíče skrytých vestavěných položek ve tvaru „Menu/Položka“ (viz `MainMenuCatalog`).
    public var hidden: Set<String>

    public init(customTitle: String = "", customItems: [CustomMenuItem] = [], hidden: Set<String> = []) {
        self.customTitle = customTitle; self.customItems = customItems; self.hidden = hidden
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customTitle = (try? c.decode(String.self, forKey: .customTitle)) ?? ""
        customItems = (try? c.decode([CustomMenuItem].self, forKey: .customItems)) ?? []
        hidden = (try? c.decode(Set<String>.self, forKey: .hidden)) ?? []
    }

    public func isVisible(_ key: String) -> Bool { !hidden.contains(key) }
}

/// Strom vlastního menu sestavený z plochého seznamu položek.
public indirect enum MenuNode: Equatable, Identifiable, Sendable {
    case item(CustomMenuItem)
    case separator(UUID)
    case submenu(name: String, children: [MenuNode])

    public var id: String {
        switch self {
        case .item(let i): return i.id.uuidString
        case .separator(let u): return "sep-" + u.uuidString
        case .submenu(let name, let children): return "sub-" + name + "-" + (children.first?.id ?? "")
        }
    }

    /// Cesta „A/B/Položka“ vytvoří vnořená podmenu „A“ a „B“; položky stejného podmenu se spojí na místě prvního výskytu.
    public static func tree(from items: [CustomMenuItem]) -> [MenuNode] {
        var out: [MenuNode] = []
        for item in items {
            if item.isSeparator { out.append(.separator(item.id)); continue }
            let parts = item.title.split(separator: "/", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let leaf = parts.last else { continue }
            var leafItem = item; leafItem.title = leaf
            insert(.item(leafItem), path: Array(parts.dropLast()), into: &out)
        }
        return out
    }

    private static func insert(_ node: MenuNode, path: [String], into list: inout [MenuNode]) {
        guard let first = path.first else { list.append(node); return }
        if let i = list.firstIndex(where: { if case .submenu(let n, _) = $0 { return n == first }; return false }),
           case .submenu(let name, var children) = list[i] {
            insert(node, path: Array(path.dropFirst()), into: &children)
            list[i] = .submenu(name: name, children: children)
        } else {
            var children: [MenuNode] = []
            insert(node, path: Array(path.dropFirst()), into: &children)
            list.append(.submenu(name: first, children: children))
        }
    }
}

/// Vestavěné položky hlavního menu, které lze skrýt (klíč „Menu/Položka“). Musí odpovídat položkám s `.hideable` v `TCCommands`.
public enum MainMenuCatalog {
    public static let items: [String] = [
        "Soubor/Otevřít",
        "Soubor/Hledat soubory…",
        "Soubor/Přejmenovat…",
        "Soubor/Nový adresář…",
        "Soubor/Nový soubor…",
        "Soubor/Kopírovat…",
        "Soubor/Přesunout…",
        "Soubor/Smazat…",
        "Soubor/Smazat trvale…",
        "Soubor/Ověřovat kopie (SHA-256)",
        "Porovnání/Porovnat soubory podle obsahu…",
        "Porovnání/Porovnat adresáře (označit rozdíly)",
        "Porovnání/Synchronizovat adresáře…",
        "Nástroje/Nastavení…",
        "Nástroje/Terminál",
        "Nástroje/Importovat nastavení z Total Commanderu…",
        "Nástroje/Hromadné přejmenování…",
        "Nástroje/Vlastnosti…",
        "Nástroje/Kontrolní součty…",
        "Nástroje/Ověřit kontrolní součty ze souboru",
        "Nástroje/Zabalit do archivu…",
        "Nástroje/Rozbalit archiv…",
        "Nástroje/Otestovat archiv",
        "Nástroje/Najít duplicitní soubory…",
        "Nástroje/Kódovat soubory (MIME, UUE, XXE) do druhého panelu…",
        "Nástroje/Dekódovat soubory do druhého panelu…",
        "Nástroje/Rozdělit soubor…",
        "Nástroje/Spojit soubory (.001)…",
        "Nástroje/Symbolický odkaz do druhého panelu…",
        "Nástroje/Pevný odkaz do druhého panelu…",
        "Označit/Označit vše",
        "Označit/Zrušit označení",
        "Označit/Invertovat označení",
        "Označit/Označit podle masky…",
        "Označit/Odznačit podle masky…",
        "Označit/Označit stejnou příponu",
        "Označit/Uložit výběr",
        "Označit/Obnovit výběr",
        "Označit/Spočítat velikosti adresářů",
        "Síť/Připojit k serveru…",
        "Síť/Odpojit panel od serveru",
        "Karty/Zamknout / odemknout kartu",
        "Karty/Uložit sadu karet…",
        "Oblíbené/Přidat aktuální adresář",
        "Zobrazení/Skryté soubory",
        "Zobrazení/Plný režim",
        "Zobrazení/Stručný režim",
        "Zobrazení/Náhledy",
        "Zobrazení/Strom adresářů",
        "Zobrazení/Panely nad sebou / vedle sebe",
        "Zobrazení/Quick View (druhý panel)",
        "Zobrazení/Obnovit",
        "Zobrazení/Branch view (všechny podadresáře)",
        "Zobrazení/Rychlý filtr",
        "Zobrazení/Nadřazený adresář",
        "Zobrazení/Zpět",
        "Zobrazení/Vpřed",
        "Zobrazení/Cíl = zdroj",
        "Zobrazení/Prohodit panely",
        "Zobrazení/Další tab",
        "Zobrazení/Předchozí tab",
    ]
    public static func menu(of key: String) -> String { String(key.split(separator: "/", maxSplits: 1).first ?? "") }
    public static func title(of key: String) -> String { String(key.split(separator: "/", maxSplits: 1).last ?? "") }
}
