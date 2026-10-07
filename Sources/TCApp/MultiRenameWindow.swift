import AppKit
import TCCore

@MainActor
final class MultiRenameWindow: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private static var current: MultiRenameWindow?

    static func show(files: [URL], onChange: @escaping (URL?) -> Void) {
        current?.window.close()
        let w = MultiRenameWindow(files: files, onChange: onChange)
        current = w
        w.window.makeKeyAndOrderFront(nil)
    }

    private let files: [URL]
    private let onChange: (URL?) -> Void
    private let window: NSWindow
    private let nameMask = NSTextField(string: "[N]"), extMask = NSTextField(string: "[E]")
    private let search = NSTextField(), replace = NSTextField()
    private let regex = NSButton(checkboxWithTitle: "Regulární výraz", target: nil, action: nil)
    private let caseSens = NSButton(checkboxWithTitle: "Rozlišovat velikost písmen", target: nil, action: nil)
    private let caseMode = NSPopUpButton(frame: .zero, pullsDown: false)
    private let cStart = NSTextField(string: "1"), cStep = NSTextField(string: "1"), cDigits = NSTextField(string: "1")
    private let presets = NSPopUpButton(frame: .zero, pullsDown: true)
    private let table = NSTableView()
    private let status = NSTextField(labelWithString: "")
    private let applyButton = NSButton(title: "Přejmenovat", target: nil, action: nil)
    private let undoButton = NSButton(title: "Vrátit zpět", target: nil, action: nil)
    private var previews: [RenamePreview] = []
    private var applied: [RenameEngine.Applied] = []

    private static let caseTitles: [(CaseMode, String)] = [
        (.unchanged, "beze změny"), (.lower, "malá písmena"), (.upper, "VELKÁ PÍSMENA"), (.firstUpper, "První velké"), (.eachWord, "Každé Slovo Velké"),
    ]
    private static let presetKey = "multirename.presets"

    private init(files: [URL], onChange: @escaping (URL?) -> Void) {
        self.files = files; self.onChange = onChange
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Hromadné přejmenování (\(files.count) souborů)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        caseMode.addItems(withTitles: Self.caseTitles.map(\.1))
        for f in [nameMask, extMask, search, replace, cStart, cStep, cDigits] { f.delegate = self }
        for c in [regex, caseSens] { c.target = self; c.action = #selector(changed) }
        caseMode.target = self; caseMode.action = #selector(changed)
        search.placeholderString = "hledat"; replace.placeholderString = "nahradit čím"
        for f in [cStart, cStep, cDigits] { f.widthAnchor.constraint(equalToConstant: 50).isActive = true; f.alignment = .right }
        reloadPresets()

        func row(_ label: String, _ views: [NSView]) -> NSStackView {
            let l = NSTextField(labelWithString: label); l.alignment = .right
            l.widthAnchor.constraint(equalToConstant: 120).isActive = true
            let s = NSStackView(views: [l] + views); s.spacing = 8; return s
        }
        let help = NSTextField(labelWithString: "[N] název  [E] přípona  [N1-3] znaky 1–3  [N2,5] od 2. znaku délka 5  [C] počítadlo  [C10+5:3] začátek+krok:číslic  [P] nadřazený adresář  [Y][M][D][h][m][s] datum změny  [d] [t]")
        help.font = .systemFont(ofSize: 11); help.textColor = .secondaryLabelColor; help.lineBreakMode = .byWordWrapping
        help.preferredMaxLayoutWidth = 860
        let form = NSStackView(views: [
            row("Maska názvu:", [nameMask]),
            row("Maska přípony:", [extMask]),
            row("Hledat / nahradit:", [search, replace]),
            row("", [regex, caseSens]),
            row("Velikost písmen:", [caseMode, NSTextField(labelWithString: "   Počítadlo [C]: začátek"), cStart,
                                     NSTextField(labelWithString: "krok"), cStep, NSTextField(labelWithString: "číslic"), cDigits]),
            help,
        ])
        form.orientation = .vertical; form.alignment = .leading; form.spacing = 6

        for (id, title, w) in [("old", "Původní název", 330.0), ("new", "Nový název", 330.0), ("state", "Stav", 200.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = w; table.addTableColumn(c)
        }
        table.dataSource = self; table.delegate = self; table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true

        applyButton.target = self; applyButton.action = #selector(applyRename); applyButton.keyEquivalent = "\r"
        undoButton.target = self; undoButton.action = #selector(undo); undoButton.isEnabled = false
        let save = NSButton(title: "Uložit předvolbu…", target: self, action: #selector(savePreset))
        let bottom = NSStackView(views: [status, NSView(), presets, save, undoButton, applyButton]); bottom.spacing = 8

        let c = window.contentView!
        for v in [form, scroll, bottom] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; c.addSubview(v) }
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: c.topAnchor, constant: 14),
            form.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14), form.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: form.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: c.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            bottom.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            bottom.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14), bottom.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14),
            bottom.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -12),
        ])
        refresh()
    }

    // MARK: Volby a náhled

    private var options: RenameOptions {
        var o = RenameOptions()
        o.nameMask = nameMask.stringValue; o.extMask = extMask.stringValue
        o.search = search.stringValue; o.replace = replace.stringValue
        o.useRegex = regex.state == .on; o.caseSensitive = caseSens.state == .on
        o.caseMode = Self.caseTitles[max(0, caseMode.indexOfSelectedItem)].0
        o.counterStart = Int(cStart.stringValue) ?? 1; o.counterStep = Int(cStep.stringValue) ?? 1
        o.counterDigits = max(1, Int(cDigits.stringValue) ?? 1)
        return o
    }

    private func set(_ o: RenameOptions) {
        nameMask.stringValue = o.nameMask; extMask.stringValue = o.extMask
        search.stringValue = o.search; replace.stringValue = o.replace
        regex.state = o.useRegex ? .on : .off; caseSens.state = o.caseSensitive ? .on : .off
        caseMode.selectItem(at: Self.caseTitles.firstIndex { $0.0 == o.caseMode } ?? 0)
        cStart.stringValue = "\(o.counterStart)"; cStep.stringValue = "\(o.counterStep)"; cDigits.stringValue = "\(o.counterDigits)"
        refresh()
    }

    @objc private func changed() { refresh() }
    func controlTextDidChange(_ obj: Notification) { refresh() }

    private func refresh() {
        let o = options
        if let err = RenameEngine.validateRegex(o) {
            status.stringValue = "Neplatný regulární výraz: \(err)"
            previews = files.map { RenamePreview(source: $0, newName: $0.lastPathComponent, problem: nil) }
            applyButton.isEnabled = false
        } else {
            previews = RenameEngine.preview(files, o)
            let changes = previews.filter(\.changed).count, problems = previews.filter { $0.problem != nil }.count
            status.stringValue = problems > 0 ? "\(problems) problémů – opravte je před přejmenováním" : "Změní se \(changes) z \(files.count)"
            applyButton.isEnabled = problems == 0 && changes > 0
        }
        table.reloadData()
    }

    // MARK: Akce

    @objc private func applyRename() {
        do {
            let done = try RenameEngine.apply(previews)
            applied = done
            undoButton.isEnabled = !done.isEmpty
            onChange(done.first?.to)
            window.close()
        } catch { Dialogs.error("Přejmenování selhalo", "\(error.localizedDescription)\nVše bylo vráceno do původního stavu.") }
    }

    @objc private func undo() {
        do { try RenameEngine.undo(applied); applied = []; undoButton.isEnabled = false; onChange(nil) }
        catch { Dialogs.error("Vrácení zpět selhalo", error.localizedDescription) }
    }

    // MARK: Předvolby

    private func loadPresets() -> [String: RenameOptions] {
        guard let d = UserDefaults.standard.data(forKey: Self.presetKey) else { return [:] }
        return (try? JSONDecoder().decode([String: RenameOptions].self, from: d)) ?? [:]
    }

    private func reloadPresets() {
        presets.removeAllItems()
        presets.addItem(withTitle: "Předvolby")
        for name in loadPresets().keys.sorted() { presets.addItem(withTitle: name) }
        presets.menu?.items.dropFirst().forEach { $0.target = self; $0.action = #selector(choosePreset(_:)) }
    }

    @objc private func choosePreset(_ item: NSMenuItem) { if let o = loadPresets()[item.title] { set(o) } }

    @objc private func savePreset() {
        guard let name = Dialogs.prompt(title: "Uložit předvolbu", message: "Název:", initial: "", ok: "Uložit"), !name.isEmpty else { return }
        var all = loadPresets(); all[name] = options
        if let d = try? JSONEncoder().encode(all) { UserDefaults.standard.set(d, forKey: Self.presetKey) }
        reloadPresets()
    }

    // MARK: Tabulka

    func numberOfRows(in tableView: NSTableView) -> Int { previews.count }

    func tableView(_ tv: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        guard let col, row < previews.count else { return nil }
        let p = previews[row]
        let cell = (tv.makeView(withIdentifier: col.identifier, owner: nil) as? NSTextField) ?? {
            let f = NSTextField(labelWithString: ""); f.identifier = col.identifier; f.lineBreakMode = .byTruncatingMiddle; return f
        }()
        switch col.identifier.rawValue {
        case "old": cell.stringValue = p.source.lastPathComponent; cell.textColor = .labelColor
        case "new": cell.stringValue = p.newName; cell.textColor = p.problem != nil ? .systemRed : (p.changed ? .systemBlue : .secondaryLabelColor)
        default:
            cell.textColor = p.problem != nil ? .systemRed : .secondaryLabelColor
            switch p.problem {
            case .empty: cell.stringValue = "prázdný název"
            case .invalidCharacter: cell.stringValue = "neplatný znak (/ nebo :)"
            case .duplicate: cell.stringValue = "duplicitní název"
            case .existsOnDisk: cell.stringValue = "již existuje"
            case nil: cell.stringValue = p.changed ? "" : "beze změny"
            }
        }
        return cell
    }

    func windowWillClose(_ notification: Notification) { Self.current = nil }
}
