import Foundation

/// Výsledek importu nastavení z Total Commanderu.
public struct WincmdImport: Equatable, Sendable {
    public var buttonBar: [ButtonBarItem] = []
    public var userCommands: [UserCommand] = []
    public var shortcuts: [String: [Shortcut]] = [:]       // příkaz (cm_*) -> zkratky
    public var hotlist: [HotlistEntry] = []
    /// Co se nepodařilo převést (a proč).
    public var skipped: [String] = []
    public init() {}
    public var isEmpty: Bool { buttonBar.isEmpty && userCommands.isEmpty && shortcuts.isEmpty && hotlist.isEmpty }
}

public enum WincmdImporter {
    /// Příkazy TC → příkazy macTC (jen ty, které macTC má).
    public static let commandMap: [String: String] = [
        "cm_copy": "cm_copy", "cm_renmov": "cm_move", "cm_delete": "cm_delete", "cm_mkdir": "cm_mkdir", "cm_list": "cm_view",
        "cm_edit": "cm_edit", "cm_searchfor": "cm_search", "cm_multirenamefiles": "cm_multirename", "cm_comparefilesbycontent": "cm_comparefiles",
        "cm_compareDirs": "cm_comparedirs", "cm_comparedirs": "cm_comparedirs", "cm_syncdirs": "cm_sync", "cm_packfiles": "cm_pack", "cm_unpackfiles": "cm_unpack",
        "cm_switchhidsys": "cm_hidden", "cm_ftpconnect": "cm_connect", "cm_ftpdisconnect": "cm_disconnect", "cm_dirbranch": "cm_branchview",
        "cm_srcthumbs": "cm_viewthumbs", "cm_srcbrief": "cm_viewbrief", "cm_srcfull": "cm_viewfull", "cm_srctree": "cm_viewtree",
        "cm_selectall": "cm_markall", "cm_clearall": "cm_unmarkall", "cm_exchangesel": "cm_invertmarks", "cm_selectbymask": "cm_markmask",
        "cm_unselectbymask": "cm_unmarkmask", "cm_selectcurrentextension": "cm_markext", "cm_saveselection": "cm_savesel", "cm_restoreselection": "cm_restoresel",
        "cm_exchange": "cm_swappanels", "cm_targetequalsource": "cm_targetsource", "cm_gotopreviousdir": "cm_goback", "cm_gotonextdir": "cm_goforward",
        "cm_cdup": "cm_goup", "cm_refresh": "cm_reload", "cm_properties": "cm_properties", "cm_checksumcalc": "cm_checksums", "cm_checksumverify": "cm_checksums",
        "cm_splitfile": "cm_split", "cm_combinefiles": "cm_combine", "cm_newtab": "cm_newtab", "cm_closecurrenttab": "cm_closetab",
        "cm_nexttab": "cm_nexttab", "cm_prevtab": "cm_prevtab", "cm_lockuncloseable": "cm_locktab", "cm_horzpanel": "cm_layout", "cm_vertpanel": "cm_layout",
        "cm_quickview": "cm_quickview", "cm_putfiletext": "cm_cmdhistory", "cm_config": "cm_settings", "cm_dirhotlist": "cm_addhotlist",
        "cm_findduplicates": "cm_duplicates", "cm_extractfiles": "cm_unpack", "cm_testarchive": "cm_unpack",
    ]

    static let icons: [String: String] = [
        "cm_copy": "doc.on.doc", "cm_move": "arrow.right.circle", "cm_delete": "trash", "cm_mkdir": "folder.badge.plus", "cm_view": "eye",
        "cm_edit": "pencil", "cm_search": "magnifyingglass", "cm_multirename": "textformat.abc", "cm_comparefiles": "rectangle.split.2x1",
        "cm_sync": "arrow.triangle.2.circlepath", "cm_pack": "archivebox", "cm_unpack": "archivebox.fill", "cm_connect": "network",
    ]

    // MARK: INI

    public static func parseINI(_ text: String) -> [String: [(key: String, value: String)]] {
        var sections: [String: [(String, String)]] = [:]
        var current = ""
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") { current = String(line.dropFirst().dropLast()).lowercased(); sections[current, default: []] = sections[current] ?? []; continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let k = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let v = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            sections[current, default: []].append((k, v))
        }
        return sections
    }

    // MARK: Zkratky

    static let keyNames: [String: String] = [
        "ENTER": "return", "RETURN": "return", "ESC": "escape", "TAB": "tab", "SPACE": "space", "DEL": "delete", "DELETE": "delete",
        "INS": "insert", "INSERT": "insert", "BACKSPACE": "backspace", "BS": "backspace", "UP": "up", "DOWN": "down", "LEFT": "left", "RIGHT": "right",
        "HOME": "home", "END": "end", "PGUP": "pageup", "PGDN": "pagedown", "NUM+": "kp+", "NUM-": "kp-", "NUM*": "kp*", "NUM/": "kp/",
    ]

    /// "C+F5", "CA+X", "ENTER" -> zkratka; nil, pokud ji nelze převést.
    public static func parseShortcut(_ text: String) -> Shortcut? {
        var mods = Set<Shortcut.Modifier>()
        var key = text.trimmingCharacters(in: .whitespaces)
        // modifikátory před prvním "+", ale ne "NUM+": rozhodneme podle toho, zda před "+" jsou jen písmena C A S W
        if let plus = key.firstIndex(of: "+"), plus != key.startIndex {
            let prefix = key[..<plus]
            if prefix.allSatisfy({ "CASWcasw".contains($0) }) && !prefix.isEmpty {
                for ch in prefix.uppercased() {
                    switch ch { case "C": mods.insert(.ctrl); case "A": mods.insert(.alt); case "S": mods.insert(.shift); default: mods.insert(.cmd) }
                }
                key = String(key[key.index(after: plus)...])
            }
        }
        let name = keyNames[key.uppercased()] ?? key.lowercased()
        guard Shortcut.knownKeys.contains(name) || name.count == 1 else { return nil }
        return Shortcut(key: name, modifiers: mods)
    }

    // MARK: Import

    /// `pathExists` umožňuje otestovat převod cest bez disku.
    public static func parse(ini: String, userCommands usercmd: String? = nil,
                             pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> WincmdImport {
        var result = WincmdImport()
        let sections = parseINI(ini)

        // tlačítková lišta
        if let bar = sections["buttonbar"] {
            let dict = Dictionary(bar.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, new in new })
            let count = Int(dict["buttoncount"] ?? "") ?? 0
            for i in 1...max(1, count) where count > 0 {
                let cmd = dict["cmd\(i)"] ?? ""
                let title = dict["menu\(i)"] ?? cmd
                guard !cmd.isEmpty else { continue }
                if let mapped = commandMap[cmd.lowercased()] ?? commandMap[cmd] {
                    result.buttonBar.append(ButtonBarItem(title: title, icon: icons[mapped] ?? "gearshape", command: mapped))
                } else if cmd.lowercased().hasPrefix("em_") {
                    result.buttonBar.append(ButtonBarItem(title: title, icon: "gearshape", command: cmd))
                } else {
                    result.skipped.append("Tlačítko „\(title)“: příkaz \(cmd) nelze převést (program pro Windows nebo neznámý příkaz)")
                }
            }
        }

        // uživatelské příkazy
        if let usercmd {
            for (name, items) in parseINI(usercmd) where name.hasPrefix("em_") {
                let d = Dictionary(items.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, new in new })
                let cmd = d["cmd"] ?? ""
                let title = d["menu"] ?? name
                if let mapped = commandMap[cmd.lowercased()] {
                    result.userCommands.append(UserCommand(name: name, title: title, command: mapped))
                } else if cmd.lowercased().hasSuffix(".exe") || cmd.contains("\\") || cmd.range(of: "^[A-Za-z]:", options: .regularExpression) != nil {
                    result.skipped.append("Příkaz \(name) („\(title)“): \(cmd) je program pro Windows")
                } else if !cmd.isEmpty {
                    result.userCommands.append(UserCommand(name: name, title: title, command: cmd, parameters: d["param"] ?? "",
                                                           startPath: d["path"] ?? ""))
                }
            }
            result.userCommands.sort { $0.name < $1.name }
        }

        // zkratky
        for sec in ["shortcuts"] {
            for (k, v) in sections[sec] ?? [] {
                guard let mapped = commandMap[v.lowercased()] ?? commandMap[v] else {
                    if v.lowercased().hasPrefix("cm_") { result.skipped.append("Zkratka \(k): příkaz \(v) macTC nemá") }
                    continue
                }
                guard let sc = parseShortcut(k) else { result.skipped.append("Zkratka \(k) → \(v): klávesu nelze převést"); continue }
                if !(result.shortcuts[mapped]?.contains(sc) ?? false) { result.shortcuts[mapped, default: []].append(sc) }
            }
        }

        // oblíbené adresáře (jen ty, které na tomto počítači existují)
        if let menu = sections["dirmenu"] {
            let d = Dictionary(menu.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, new in new })
            var i = 1
            while let title = d["menu\(i)"] {
                defer { i += 1 }
                guard var path = d["cmd\(i)"], title != "-", !title.hasPrefix("--") else { continue }
                if path.lowercased().hasPrefix("cd ") { path = String(path.dropFirst(3)) }
                let converted = path.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: .whitespaces)
                if converted.hasPrefix("/") && pathExists(converted) {
                    result.hotlist.append(HotlistEntry(name: title.replacingOccurrences(of: "&", with: ""), path: converted))
                } else {
                    result.skipped.append("Oblíbený adresář „\(title)“: cesta \(path) na tomto počítači neexistuje")
                }
            }
        }
        return result
    }

    /// Načte soubory (kódování se rozpozná) a vrátí výsledek; `usercmd.ini` se hledá vedle `wincmd.ini`.
    public static func load(from iniURL: URL) throws -> WincmdImport {
        let ini = TextDecoding.decode(try Data(contentsOf: iniURL)).text
        let userURL = iniURL.deletingLastPathComponent().appendingPathComponent("usercmd.ini")
        let user = (try? Data(contentsOf: userURL)).map { TextDecoding.decode($0).text }
        return parse(ini: ini, userCommands: user)
    }
}
