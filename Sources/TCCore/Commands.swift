import Foundation

/// Klávesová zkratka v textovém tvaru, např. "F5", "ctrl+shift+c", "alt+F7", "delete".
public struct Shortcut: Hashable, Codable, Sendable, CustomStringConvertible {
    public enum Modifier: String, CaseIterable, Codable, Sendable { case ctrl, alt, shift, cmd }

    public var key: String                 // malými písmeny; názvy: f1…f12, return, tab, space, delete, backspace, escape, insert, up, down, left, right, home, end, pageup, pagedown, + - * / . , ;
    public var modifiers: Set<Modifier>

    public init(key: String, modifiers: Set<Modifier> = []) { self.key = key.lowercased(); self.modifiers = modifiers }

    public init?(_ text: String) {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let k = parts.last, !k.isEmpty else {
            // znak "+" jako klávesa ("ctrl++")
            if text.hasSuffix("++") { self.init(key: "+", modifiers: Set(text.dropLast(2).split(separator: "+").compactMap { Modifier(rawValue: $0.lowercased()) })); return }
            return nil
        }
        var mods = Set<Modifier>()
        for m in parts.dropLast() {
            guard let mod = Modifier(rawValue: m == "control" ? "ctrl" : (m == "option" ? "alt" : (m == "command" ? "cmd" : m))) else { return nil }
            mods.insert(mod)
        }
        guard Shortcut.knownKeys.contains(k) || k.count == 1 else { return nil }
        self.init(key: k, modifiers: mods)
    }

    public var description: String {
        let order: [Modifier] = [.ctrl, .alt, .shift, .cmd]
        return (order.filter(modifiers.contains).map(\.rawValue) + [key]).joined(separator: "+")
    }

    public static let knownKeys: Set<String> = Set((1...12).map { "f\($0)" } + ["return", "tab", "space", "delete", "backspace", "escape",
        "insert", "up", "down", "left", "right", "home", "end", "pageup", "pagedown", "kp+", "kp-", "kp*", "kp/"])

    // Kódy kláves macOS (pro převod z NSEvent.keyCode)
    public static let macKeyCodes: [UInt16: String] = [
        122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6", 98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12",
        36: "return", 76: "return", 48: "tab", 49: "space", 117: "delete", 51: "backspace", 53: "escape", 114: "insert",
        126: "up", 125: "down", 123: "left", 124: "right", 115: "home", 119: "end", 116: "pageup", 121: "pagedown",
        69: "kp+", 78: "kp-", 67: "kp*", 75: "kp/",
    ]
}

/// Popis příkazu aplikace (obdoba interních příkazů cm_* v Total Commanderu).
public struct CommandInfo: Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var category: String
    public var defaultShortcuts: [Shortcut]
    public init(_ id: String, _ title: String, _ category: String, _ shortcuts: [Shortcut] = []) {
        self.id = id; self.title = title; self.category = category; self.defaultShortcuts = shortcuts
    }
}

public enum CommandRegistry {
    static func s(_ k: String, _ m: Set<Shortcut.Modifier> = []) -> Shortcut { Shortcut(key: k, modifiers: m) }

    public static let all: [CommandInfo] = [
        // soubory
        CommandInfo("cm_rename", "Přejmenovat", "Soubory", [s("f2"), s("f6", [.shift])]),
        CommandInfo("cm_view", "Zobrazit (Lister)", "Soubory", [s("f3")]),
        CommandInfo("cm_edit", "Editovat", "Soubory", [s("f4")]),
        CommandInfo("cm_newfile", "Nový soubor", "Soubory", [s("f4", [.shift])]),
        CommandInfo("cm_copy", "Kopírovat", "Soubory", [s("f5")]),
        CommandInfo("cm_pack", "Zabalit do archivu", "Soubory", [s("f5", [.alt])]),
        CommandInfo("cm_move", "Přesunout", "Soubory", [s("f6")]),
        CommandInfo("cm_mkdir", "Nový adresář", "Soubory", [s("f7")]),
        CommandInfo("cm_search", "Hledat soubory", "Soubory", [s("f7", [.alt])]),
        CommandInfo("cm_delete", "Smazat", "Soubory", [s("f8"), s("delete")]),
        CommandInfo("cm_deleteperm", "Smazat trvale", "Soubory", [s("f8", [.shift]), s("delete", [.shift])]),
        CommandInfo("cm_unpack", "Rozbalit archiv", "Soubory", [s("f9", [.alt])]),
        CommandInfo("cm_properties", "Vlastnosti", "Soubory", [s("return", [.alt])]),
        CommandInfo("cm_open", "Otevřít", "Soubory", [s("return")]),
        CommandInfo("cm_multirename", "Hromadné přejmenování", "Soubory", [s("m", [.ctrl])]),
        CommandInfo("cm_checksums", "Kontrolní součty", "Soubory"),
        CommandInfo("cm_split", "Rozdělit soubor", "Soubory"),
        CommandInfo("cm_combine", "Spojit soubory", "Soubory"),
        CommandInfo("cm_duplicates", "Najít duplicity", "Soubory"),
        CommandInfo("cm_encode", "Kódovat soubory", "Soubory"),
        CommandInfo("cm_decode", "Dekódovat soubory", "Soubory"),
        // označování
        CommandInfo("cm_markall", "Označit vše", "Označování"),
        CommandInfo("cm_unmarkall", "Zrušit označení", "Označování"),
        CommandInfo("cm_invertmarks", "Invertovat označení", "Označování", [s("kp*")]),
        CommandInfo("cm_markmask", "Označit podle masky", "Označování", [s("kp+")]),
        CommandInfo("cm_unmarkmask", "Odznačit podle masky", "Označování", [s("kp-")]),
        CommandInfo("cm_markext", "Označit stejnou příponu", "Označování"),
        CommandInfo("cm_savesel", "Uložit výběr", "Označování"),
        CommandInfo("cm_restoresel", "Obnovit výběr", "Označování"),
        // panely
        CommandInfo("cm_switchpanel", "Přepnout panel", "Panely", [s("tab")]),
        CommandInfo("cm_swappanels", "Prohodit panely", "Panely"),
        CommandInfo("cm_targetsource", "Cíl = zdroj", "Panely"),
        CommandInfo("cm_goup", "Nadřazený adresář", "Panely", [s("backspace")]),
        CommandInfo("cm_goback", "Zpět", "Panely"),
        CommandInfo("cm_goforward", "Vpřed", "Panely"),
        CommandInfo("cm_reload", "Obnovit", "Panely"),
        CommandInfo("cm_branchview", "Branch view", "Panely", [s("b", [.ctrl])]),
        CommandInfo("cm_quickfilter", "Rychlý filtr", "Panely", [s("s", [.ctrl])]),
        CommandInfo("cm_quickview", "Quick View", "Panely", [s("q", [.ctrl])]),
        CommandInfo("cm_viewfull", "Plný režim", "Panely"),
        CommandInfo("cm_viewbrief", "Stručný režim", "Panely"),
        CommandInfo("cm_viewthumbs", "Náhledy", "Panely"),
        CommandInfo("cm_viewtree", "Strom adresářů", "Panely"),
        CommandInfo("cm_hidden", "Skryté soubory", "Panely"),
        CommandInfo("cm_newtab", "Nový tab", "Panely"),
        CommandInfo("cm_closetab", "Zavřít tab", "Panely"),
        CommandInfo("cm_nexttab", "Další tab", "Panely", [s("tab", [.ctrl])]),
        CommandInfo("cm_prevtab", "Předchozí tab", "Panely", [s("tab", [.ctrl, .shift])]),
        CommandInfo("cm_locktab", "Zamknout tab", "Panely"),
        CommandInfo("cm_layout", "Panely nad sebou / vedle sebe", "Panely"),
        CommandInfo("cm_addhotlist", "Přidat do oblíbených", "Panely"),
        // porovnání, nástroje
        CommandInfo("cm_comparefiles", "Porovnat soubory", "Porovnání"),
        CommandInfo("cm_comparedirs", "Porovnat adresáře", "Porovnání"),
        CommandInfo("cm_sync", "Synchronizovat adresáře", "Porovnání"),
        CommandInfo("cm_connect", "Připojit k serveru", "Síť"),
        CommandInfo("cm_disconnect", "Odpojit server", "Síť"),
        CommandInfo("cm_terminal", "Terminál", "Nástroje"),
        CommandInfo("cm_settings", "Nastavení", "Nástroje"),
        CommandInfo("cm_cmdhistory", "Příkazová řádka: vložit název", "Nástroje", [s("return", [.ctrl])]),
    ]

    public static let byID: [String: CommandInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

/// Klávesové zkratky: výchozí z registru a uživatelské úpravy (přepisují výchozí pro daný příkaz).
public struct Keymap: Codable, Sendable, Equatable {
    /// Příkaz → zkratky; chybějící příkaz používá výchozí; prázdné pole znamená „bez zkratky“.
    public var overrides: [String: [Shortcut]] = [:]
    public init() {}

    public func shortcuts(for id: String) -> [Shortcut] {
        overrides[id] ?? CommandRegistry.byID[id]?.defaultShortcuts ?? []
    }

    /// Příkaz pro zkratku (uživatelský přiřazení má přednost před výchozím).
    public func command(for shortcut: Shortcut) -> String? {
        for (id, list) in overrides where list.contains(shortcut) { return id }
        for c in CommandRegistry.all where overrides[c.id] == nil && c.defaultShortcuts.contains(shortcut) { return c.id }
        return nil
    }

    /// Dvojice příkazů se stejnou zkratkou.
    public func conflicts() -> [(Shortcut, [String])] {
        var map: [Shortcut: [String]] = [:]
        for c in CommandRegistry.all { for s in shortcuts(for: c.id) { map[s, default: []].append(c.id) } }
        return map.filter { $0.value.count > 1 }.map { ($0.key, $0.value) }.sorted { $0.0.description < $1.0.description }
    }

    public mutating func set(_ shortcuts: [Shortcut], for id: String) {
        if shortcuts == (CommandRegistry.byID[id]?.defaultShortcuts ?? []) { overrides[id] = nil } else { overrides[id] = shortcuts }
    }

    public mutating func reset(_ id: String) { overrides[id] = nil }
}

// MARK: Uživatelské příkazy, tlačítka, přidružení

/// Uživatelský příkaz: spuštění programu nebo interního příkazu s parametry (placeholdery viz `PlaceholderExpander`).
public struct UserCommand: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String            // např. "em_gitstatus"
    public var title: String
    public var command: String         // program, shellový příkaz, nebo "cm_*"
    public var parameters: String
    public var startPath: String
    public var icon: String            // SF Symbol
    public var runInTerminal: Bool
    public init(name: String, title: String, command: String, parameters: String = "", startPath: String = "", icon: String = "gearshape", runInTerminal: Bool = false) {
        self.name = name; self.title = title; self.command = command; self.parameters = parameters
        self.startPath = startPath; self.icon = icon; self.runInTerminal = runInTerminal
    }
}

public struct ButtonBarItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var icon: String            // SF Symbol
    /// "cm_*" (interní příkaz), "em_*" (uživatelský příkaz) nebo shellový příkaz.
    public var command: String
    public var parameters: String
    public init(id: UUID = UUID(), title: String, icon: String = "gearshape", command: String, parameters: String = "") {
        self.id = id; self.title = title; self.icon = icon; self.command = command; self.parameters = parameters
    }
}

/// Přidružení přípon k příkazu (obdoba Internal Associations v TC).
public struct FileAssociation: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var extensions: [String]    // bez tečky, malými písmeny
    public var command: String         // program / aplikace (.app) / shellový příkaz
    public var parameters: String      // např. "%P%N"; prázdné = cesta k souboru
    public init(id: UUID = UUID(), extensions: [String], command: String, parameters: String = "") {
        self.id = id; self.extensions = extensions.map { $0.lowercased() }; self.command = command; self.parameters = parameters
    }
}

public enum Associations {
    public static func match(_ fileName: String, in list: [FileAssociation]) -> FileAssociation? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return list.first { $0.extensions.contains(ext) }
    }
}

/// Dosazení placeholderů: %P zdrojový adresář (s lomítkem), %N název pod kurzorem, %S označené názvy, %T cílový adresář (s lomítkem),
/// %F plná cesta k souboru pod kurzorem, %L soubor se seznamem označených cest, %% procento.
public struct PlaceholderContext: Sendable {
    public var sourcePath: String
    public var targetPath: String
    public var cursorName: String?
    public var selectedNames: [String]
    public var listFile: String?
    public init(sourcePath: String, targetPath: String, cursorName: String? = nil, selectedNames: [String] = [], listFile: String? = nil) {
        self.sourcePath = sourcePath; self.targetPath = targetPath; self.cursorName = cursorName
        self.selectedNames = selectedNames; self.listFile = listFile
    }
}

public enum PlaceholderExpander {
    public static func shellQuote(_ s: String) -> String {
        s.range(of: "^[A-Za-z0-9_./,:+@%=-]+$", options: .regularExpression) != nil ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// `quote`: názvy se ošetří pro shell. Neznámé placeholdery zůstanou beze změny.
    public static func expand(_ template: String, _ c: PlaceholderContext, quote: Bool = true) -> String {
        func q(_ s: String) -> String { quote ? shellQuote(s) : s }
        func dir(_ p: String) -> String { p.hasSuffix("/") ? p : p + "/" }
        var out = "", i = template.startIndex
        while i < template.endIndex {
            let ch = template[i]
            guard ch == "%", template.index(after: i) < template.endIndex else { out.append(ch); i = template.index(after: i); continue }
            let k = template[template.index(after: i)]
            switch k {
            case "P": out += q(dir(c.sourcePath))
            case "T": out += q(dir(c.targetPath))
            case "N": out += q(c.cursorName ?? "")
            case "F": out += q(c.cursorName.map { dir(c.sourcePath) + $0 } ?? "")
            case "S": out += c.selectedNames.map(q).joined(separator: " ")
            case "L": out += q(c.listFile ?? "")
            case "%": out += "%"
            default: out += "%" + String(k)
            }
            i = template.index(i, offsetBy: 2)
        }
        return out
    }
}

// MARK: Nastavení

public struct AppSettings: Codable, Equatable, Sendable {
    public var editorApp: String = "/System/Applications/TextEdit.app"
    public var terminalApp: String = "/System/Applications/Utilities/Terminal.app"
    public var deleteToTrash = true
    public var verifyCopies = false
    public var showHidden = false
    public var rowHeight = 20.0
    public var fontSize = 12.0
    public var language = "cs"
    public var panelsStacked = false
    public var colorRules: [ColorRule] = ColorRule.defaults
    public init() {}
}

/// Barva názvu podle masky (obdoba barev podle typu souboru v TC).
public struct ColorRule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var masks: String
    public var hex: String             // např. "#cc0000"
    public init(id: UUID = UUID(), masks: String, hex: String) { self.id = id; self.masks = masks; self.hex = hex }

    public static let defaults: [ColorRule] = [
        ColorRule(masks: "*.zip;*.7z;*.rar;*.tar;*.gz;*.tgz;*.bz2;*.xz", hex: "#a64ca6"),
        ColorRule(masks: "*.app;*.sh;*.command", hex: "#2b9348"),
        ColorRule(masks: "*.jpg;*.jpeg;*.png;*.gif;*.heic;*.tiff;*.webp", hex: "#c77700"),
    ]

    public static func color(for fileName: String, isDirectory: Bool, rules: [ColorRule]) -> String? {
        guard !isDirectory else { return nil }
        return rules.first { GlobMatcher.matches(fileName, masks: $0.masks) }?.hex
    }
}

/// Jednoduché úložiště JSON v Application Support.
public struct JSONStore<T: Codable>: Sendable where T: Sendable {
    public let file: URL
    public init(name: String, directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("macTC")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        file = dir.appendingPathComponent(name + ".json")
    }
    public func load(default value: T) -> T {
        guard let d = try? Data(contentsOf: file), let v = try? JSONDecoder().decode(T.self, from: d) else { return value }
        return v
    }
    public func save(_ value: T) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(value) { try? d.write(to: file, options: .atomic) }
    }
}
