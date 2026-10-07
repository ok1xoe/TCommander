import AppKit
import TCCore

/// Okno Nastavení: obecné volby, klávesové zkratky, tlačítková lišta a Start menu, uživatelské příkazy, přidružení, barvy.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private static var current: SettingsWindow?

    static func show(_ model: AppModel) {
        if let w = current { w.window.makeKeyAndOrderFront(nil); return }
        let w = SettingsWindow(model)
        current = w
        w.window.makeKeyAndOrderFront(nil)
    }

    private let model: AppModel
    private let window: NSWindow
    private let tabs = NSTabView()
    private var keepAlive: [AnyObject] = []

    // obecné
    private let editor = NSTextField(), terminal = NSTextField(), proxyNote = NSTextField(labelWithString: "")
    private let trash = NSButton(checkboxWithTitle: "Mazat do koše (jinak trvale)", target: nil, action: nil)
    private let verify = NSButton(checkboxWithTitle: "Ověřovat kopie (SHA-256)", target: nil, action: nil)
    private let hidden = NSButton(checkboxWithTitle: "Zobrazovat skryté soubory", target: nil, action: nil)
    private let stacked = NSButton(checkboxWithTitle: "Panely nad sebou (místo vedle sebe)", target: nil, action: nil)
    private let fontSize = NSTextField(), rowHeight = NSTextField()
    private let language = NSPopUpButton(frame: .zero, pullsDown: false)

    private init(_ model: AppModel) {
        self.model = model
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Nastavení macTC"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 10),
            tabs.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -10),
            tabs.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 10),
            tabs.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -10),
        ])
        add(L("Obecné"), generalTab())
        add(L("Zkratky"), shortcutsTab())
        add(L("Tlačítková lišta"), buttonsTab(start: false))
        add(L("Start menu"), buttonsTab(start: true))
        add(L("Uživatelské příkazy"), commandsTab())
        add(L("Přidružení souborů"), associationsTab())
        add(L("Sloupce"), columnsTab())
        add(L("Barvy"), colorsTab())
        add(L("Pluginy"), pluginsTab())
    }

    private func add(_ title: String, _ content: NSView) {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 12), content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12), content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
        ])
        item.view = container
        tabs.addTabViewItem(item)
    }

    // MARK: Obecné

    private func generalTab() -> NSView {
        let s = model.settings
        editor.stringValue = s.editorApp; terminal.stringValue = s.terminalApp
        trash.state = s.deleteToTrash ? .on : .off; verify.state = s.verifyCopies ? .on : .off
        hidden.state = s.showHidden ? .on : .off; stacked.state = s.panelsStacked ? .on : .off
        fontSize.stringValue = String(format: "%g", s.fontSize); rowHeight.stringValue = String(format: "%g", s.rowHeight)
        language.addItems(withTitles: ["Čeština", "English"]); language.selectItem(at: s.language == "en" ? 1 : 0)
        for c in [trash, verify, hidden, stacked] { c.target = self; c.action = #selector(generalChanged) }
        for f in [editor, terminal, fontSize, rowHeight] { f.target = self; f.action = #selector(generalChanged) }
        language.target = self; language.action = #selector(generalChanged)

        func row(_ label: String, _ v: [NSView]) -> NSStackView {
            let l = NSTextField(labelWithString: label); l.alignment = .right
            l.widthAnchor.constraint(equalToConstant: 170).isActive = true
            let st = NSStackView(views: [l] + v); st.spacing = 8; return st
        }
        editor.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        terminal.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        let chooseEditor = NSButton(title: "Vybrat…", target: self, action: #selector(pickEditor))
        let chooseTerminal = NSButton(title: "Vybrat…", target: self, action: #selector(pickTerminal))
        for f in [fontSize, rowHeight] { f.widthAnchor.constraint(equalToConstant: 60).isActive = true }
        let note = NSTextField(wrappingLabelWithString: "Změna jazyka se projeví po restartu aplikace. Úpravy zkratek platí okamžitě; zkratky v hlavním menu jsou pevné.")
        note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize: 11)
        let stack = NSStackView(views: [
            row("Editor (F4):", [editor, chooseEditor]), row("Terminál:", [terminal, chooseTerminal]),
            row("", [trash]), row("", [verify]), row("", [hidden]), row("", [stacked]),
            row("Velikost písma:", [fontSize]), row("Výška řádku:", [rowHeight]), row("Jazyk:", [language]), note,
        ])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        let wrap = NSView(); stack.translatesAutoresizingMaskIntoConstraints = false; wrap.addSubview(stack)
        NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: wrap.topAnchor), stack.leadingAnchor.constraint(equalTo: wrap.leadingAnchor)])
        return wrap
    }

    @objc private func generalChanged() {
        var s = model.settings
        s.editorApp = editor.stringValue; s.terminalApp = terminal.stringValue
        s.deleteToTrash = trash.state == .on; s.verifyCopies = verify.state == .on
        s.showHidden = hidden.state == .on; s.panelsStacked = stacked.state == .on
        s.fontSize = min(24, max(9, Double(fontSize.stringValue.replacingOccurrences(of: ",", with: ".")) ?? s.fontSize))
        s.rowHeight = min(40, max(14, Double(rowHeight.stringValue.replacingOccurrences(of: ",", with: ".")) ?? s.rowHeight))
        s.language = language.indexOfSelectedItem == 1 ? "en" : "cs"
        model.settings = s
    }

    @objc private func pickEditor() { pickApp(editor) }
    @objc private func pickTerminal() { pickApp(terminal) }
    private func pickApp(_ field: NSTextField) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]; p.directoryURL = URL(fileURLWithPath: "/Applications"); p.allowsMultipleSelection = false
        if p.runModal() == .OK, let u = p.url { field.stringValue = u.path; generalChanged() }
    }

    // MARK: Zkratky

    private func shortcutsTab() -> NSView {
        let table = StringTable(columns: [.init(title: "Příkaz", width: 150, editable: false), .init(title: "Název", width: 300, editable: false),
                                          .init(title: "Zkratky (oddělené čárkou, např. ctrl+shift+c, f5)", width: 360)],
                                rows: shortcutRows(), canAddRemove: false)
        let status = NSTextField(labelWithString: conflictText())
        status.textColor = .systemOrange
        let reset = NSButton(title: "Obnovit výchozí zkratky", target: nil, action: nil)
        table.validate = { [weak self] row, col, value in
            guard let self, col == 2 else { return false }
            let id = CommandRegistry.all[row].id
            let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let parsed = parts.compactMap { Shortcut($0) }
            guard parsed.count == parts.count else { Dialogs.error("Neplatná zkratka", "Použijte např. „ctrl+shift+c“, „f5“, „alt+return“."); return false }
            self.model.keymap.set(parsed, for: id)
            status.stringValue = self.conflictText()
            return true
        }
        reset.target = self
        let handler = ResetHandler { [weak self] in
            guard let self else { return }
            self.model.keymap = Keymap(); table.setRows(self.shortcutRows()); status.stringValue = self.conflictText()
        }
        reset.target = handler; reset.action = #selector(ResetHandler.fire)
        keepAlive.append(table); keepAlive.append(handler)
        return stackWithFooter(table.view, [status, NSView(), reset])
    }

    private func shortcutRows() -> [[String]] {
        CommandRegistry.all.map { [$0.id, $0.title, model.keymap.shortcuts(for: $0.id).map(\.description).joined(separator: ", ")] }
    }

    private func conflictText() -> String {
        let c = model.keymap.conflicts()
        return c.isEmpty ? "Bez konfliktů" : "Konflikt: " + c.prefix(3).map { "\($0.0) → \($0.1.joined(separator: ", "))" }.joined(separator: "; ")
    }

    // MARK: Lišta a Start menu

    private func buttonsTab(start: Bool) -> NSView {
        func rows() -> [[String]] { (start ? model.startMenu : model.buttonBar).map { [$0.title, $0.icon, $0.command, $0.parameters] } }
        let table = StringTable(columns: [.init(title: "Název", width: 160), .init(title: "Ikona (SF Symbol)", width: 170),
                                          .init(title: "Příkaz (cm_*, em_* nebo program)", width: 280), .init(title: "Parametry", width: 220)],
                                rows: rows(), newRow: { ["Nové", "star", "cm_", ""] })
        table.onChange = { [weak self] r in
            let items = r.map { ButtonBarItem(title: $0[0], icon: $0[1], command: $0[2], parameters: $0[3]) }
            if start { self?.model.startMenu = items } else { self?.model.buttonBar = items }
        }
        keepAlive.append(table)
        let hint = NSTextField(wrappingLabelWithString: "Příkazy: cm_copy, cm_search … (viz záložka Zkratky), em_<název> pro uživatelský příkaz, nebo libovolný program. Parametry: %P zdrojový adresář, %N název pod kurzorem, %S označené, %T cíl, %F plná cesta, %L soubor se seznamem.")
        hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 11)
        return stackWithFooter(table.view, [hint])
    }

    // MARK: Uživatelské příkazy

    private func commandsTab() -> NSView {
        let table = StringTable(columns: [.init(title: "Jméno (em_…)", width: 110), .init(title: "Název", width: 140), .init(title: "Příkaz", width: 200),
                                          .init(title: "Parametry", width: 160), .init(title: "Startovní cesta", width: 120), .init(title: "Ikona", width: 90), .init(title: "Terminál (ano/ne)", width: 90)],
                                rows: model.userCommands.map { [$0.name, $0.title, $0.command, $0.parameters, $0.startPath, $0.icon, $0.runInTerminal ? "ano" : "ne"] },
                                newRow: { ["em_novy", "Nový příkaz", "", "", "", "gearshape", "ne"] })
        table.onChange = { [weak self] r in
            self?.model.userCommands = r.map { UserCommand(name: $0[0], title: $0[1], command: $0[2], parameters: $0[3], startPath: $0[4], icon: $0[5], runInTerminal: $0[6].lowercased() == "ano") }
        }
        keepAlive.append(table)
        return table.view
    }

    // MARK: Přidružení

    private func associationsTab() -> NSView {
        let table = StringTable(columns: [.init(title: "Přípony (čárkou)", width: 150), .init(title: "Enter: program / aplikace / příkaz", width: 230),
                                          .init(title: "Parametry", width: 90), .init(title: "F3 Zobrazit (prázdné = podle typu)", width: 190), .init(title: "F4 Editovat (prázdné = podle typu)", width: 190)],
                                rows: model.associations.map { [$0.extensions.joined(separator: ", "), $0.command, $0.parameters, $0.viewCommand, $0.editCommand] },
                                newRow: { ["png, jpg", "", "", "/System/Applications/Preview.app", ""] })
        table.onChange = { [weak self] r in
            self?.model.associations = r.map {
                FileAssociation(extensions: $0[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                                command: $0[1], parameters: $0[2], viewCommand: $0[3], editCommand: $0[4])
            }
        }
        keepAlive.append(table)
        let hint = NSTextField(wrappingLabelWithString: "Bez přidružení platí pravidla podle typu: F3 zobrazí text, obrázky, PDF a média v Listeru, dokumenty (Word, Pages, Excel…) přes Quick Look; F4 otevře textové soubory ve zvoleném editoru a ostatní typy v jejich výchozí aplikaci. Příkaz může být aplikace (.app) nebo shellový příkaz s %F.")
        hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 11)
        return stackWithFooter(table.view, [hint])
    }

    // MARK: Sloupce (vlastní pohledy)

    private func columnsTab() -> NSView {
        let table = StringTable(columns: [.init(title: "Název pohledu", width: 200), .init(title: "Sloupce (čárkou): \(PanelColumn.allCases.map(\.rawValue).joined(separator: ", "))", width: 640)],
                                rows: model.settings.columnSets.map { [$0.name, $0.columns.map(\.rawValue).joined(separator: ", ")] },
                                newRow: { ["Nový pohled", "name, size, date"] })
        table.onChange = { [weak self] r in
            self?.model.settings.columnSets = r.filter { !$0[0].isEmpty }.map { ColumnSet(name: $0[0], columns: ColumnSet.parse($0[1])) }
        }
        keepAlive.append(table)
        let hint = NSTextField(labelWithString: "Pohled vyberete v menu Zobrazení › Sloupce. Název je vždy první sloupec.")
        hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 11)
        return stackWithFooter(table.view, [hint])
    }

    // MARK: Pluginy

    private func pluginsTab() -> NSView {
        func rows() -> [[String]] {
            PluginHost.shared.plugins.map { p in
                guard let m = p.manifest else { return [p.directory.lastPathComponent, "", "", "CHYBA: \(p.error ?? "?")"] }
                var caps: [String] = []
                if let c = m.capabilities.columns, !c.isEmpty { caps.append("sloupce: " + c.map(\.title).joined(separator: ", ")) }
                if let v = m.capabilities.viewer { caps.append("prohlížeč: " + v.extensions.joined(separator: ", ")) }
                if let a = m.capabilities.archive { caps.append("archivy: " + a.extensions.joined(separator: ", ")) }
                if let f = m.capabilities.filesystem { caps.append("souborový systém: \(f.scheme)://") }
                return [m.name, m.version ?? "", caps.joined(separator: "; "), "načten"]
            }
        }
        let table = StringTable(columns: [.init(title: "Plugin", width: 150, editable: false), .init(title: "Verze", width: 60, editable: false),
                                          .init(title: "Schopnosti", width: 480, editable: false), .init(title: "Stav", width: 140, editable: false)],
                                rows: rows(), canAddRemove: false)
        let reload = NSButton(title: "Znovu načíst", target: nil, action: nil)
        let openFolder = NSButton(title: "Otevřít složku pluginů", target: nil, action: nil)
        let h1 = ResetHandler { PluginHost.shared.reload(); table.setRows(rows()) }
        let h2 = ResetHandler { NSWorkspace.shared.open(PluginHost.shared.directory) }
        reload.target = h1; reload.action = #selector(ResetHandler.fire)
        openFolder.target = h2; openFolder.action = #selector(ResetHandler.fire)
        keepAlive += [table, h1, h2]
        let hint = NSTextField(wrappingLabelWithString: "Plugin je složka s plugin.json a spustitelným souborem; viz docs/plugins.md. Složka: \(PluginHost.shared.directory.path)")
        hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 11)
        return stackWithFooter(table.view, [hint, NSView(), openFolder, reload])
    }

    // MARK: Barvy

    private func colorsTab() -> NSView {
        let table = StringTable(columns: [.init(title: "Masky souborů", width: 460), .init(title: "Barva (#rrggbb)", width: 140)],
                                rows: model.settings.colorRules.map { [$0.masks, $0.hex] }, newRow: { ["*.log", "#808080"] })
        table.validate = { _, col, value in col == 0 || NSColor(hex: value) != nil }
        table.onChange = { [weak self] r in self?.model.settings.colorRules = r.map { ColorRule(masks: $0[0], hex: $0[1]) } }
        keepAlive.append(table)
        let hint = NSTextField(labelWithString: "Název souboru se obarví podle první odpovídající masky. Adresáře a označené soubory mají vlastní barvy.")
        hint.textColor = .secondaryLabelColor; hint.font = .systemFont(ofSize: 11)
        return stackWithFooter(table.view, [hint])
    }

    private func stackWithFooter(_ main: NSView, _ footer: [NSView]) -> NSView {
        let bar = NSStackView(views: footer); bar.spacing = 8
        let v = NSView()
        for sub in [main, bar] { sub.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(sub) }
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: v.topAnchor), main.leadingAnchor.constraint(equalTo: v.leadingAnchor), main.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            bar.topAnchor.constraint(equalTo: main.bottomAnchor, constant: 8), bar.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: v.trailingAnchor), bar.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        return v
    }

    func windowWillClose(_ notification: Notification) { Self.current = nil }
}

private final class ResetHandler: NSObject {
    let action: () -> Void
    init(_ a: @escaping () -> Void) { action = a }
    @objc func fire() { action() }
}

extension NSColor {
    /// "#rrggbb" nebo "rrggbb".
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
