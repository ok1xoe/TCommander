import AppKit
import TCCore

/// Dialog Vlastnosti: informace o souboru (vlastník, skupina, časy, velikost i u složek), oprávnění, datum změny,
/// příznaky souboru a možnost použít změny rekurzivně na obsah složky.
@MainActor
final class PropertiesDialog: NSObject {
    struct Result {
        var permissions: UInt16?
        var modified: Date?
        var setFlags: Set<FileFlag>
        var clearFlags: Set<FileFlag>
        var recursive: Bool
    }

    private let entries: [FileEntry]
    private let sizeLabel = NSTextField(labelWithString: "")
    private let perm = NSTextField(), date = NSTextField()
    private var flagBoxes: [FileFlag: NSButton] = [:]
    private let recursive = NSButton(checkboxWithTitle: L("Použít změny i na obsah složky (rekurzivně)"), target: nil, action: nil)
    private var initialFlags: [FileFlag: Bool] = [:]
    private var task: Task<Void, Never>?
    static let dateFormat: DateFormatter = { let f = DateFormatter(); f.dateFormat = "dd.MM.yyyy HH:mm:ss"; return f }()

    init(entries: [FileEntry]) { self.entries = entries }

    func run() -> Result? {
        let single = entries.count == 1 ? entries[0] : nil
        func line(_ l: String, _ v: NSView, _ labelWidth: CGFloat = 150) -> NSStackView {
            let t = NSTextField(labelWithString: l); t.alignment = .right; t.textColor = .secondaryLabelColor
            t.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
            let s = NSStackView(views: [t, v]); s.spacing = 8; return s
        }
        func text(_ s: String) -> NSTextField { let f = NSTextField(labelWithString: s); f.lineBreakMode = .byTruncatingMiddle; f.isSelectable = true
            f.widthAnchor.constraint(lessThanOrEqualToConstant: 420).isActive = true; return f }

        var rows: [NSView] = []
        if let e = single {
            let pathLabel = NSTextField(wrappingLabelWithString: e.url.path)
            pathLabel.isSelectable = true; pathLabel.preferredMaxLayoutWidth = 400
            pathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 400).isActive = true
            rows.append(line(L("Cesta:"), pathLabel))
            rows.append(line(L("Druh:"), text(Fmt.kind(of: e))))
            rows.append(line(L("Velikost:"), sizeLabel))
            rows.append(line(L("Vlastník / skupina:"), text("\(FileAttributes.ownerName(e.ownerID)) / \(FileAttributes.groupName(e.groupID))")))
            rows.append(line(L("Vytvořeno:"), text(Fmt.date(e.created))))
            rows.append(line(L("Otevřeno:"), text(Fmt.date(e.accessed))))
            sizeLabel.stringValue = e.isDirectory ? "počítám…" : "\(Fmt.bytes(e.size)) bajtů (\(Fmt.human(e.size)))"
        } else {
            rows.append(line(L("Položek:"), text("\(entries.count)")))
            rows.append(line(L("Velikost:"), sizeLabel))
            sizeLabel.stringValue = "počítám…"
        }
        perm.stringValue = single.map { String($0.permissions, radix: 8) } ?? ""
        perm.placeholderString = "např. 644 (prázdné = beze změny)"
        date.stringValue = single?.modified.map { Self.dateFormat.string(from: $0) } ?? ""
        date.placeholderString = "dd.MM.yyyy HH:mm:ss (prázdné = beze změny)"
        for f in [perm, date] { f.widthAnchor.constraint(equalToConstant: 320).isActive = true }
        rows.append(line(L("Oprávnění (osmičkově):"), perm))
        rows.append(line(L("Datum změny:"), date))
        for flag in FileFlag.allCases {
            let b = NSButton(checkboxWithTitle: L(flag.title), target: nil, action: nil)
            let all = entries.compactMap { FileAttributes.flags(of: $0.url) }
            let on = !all.isEmpty && all.allSatisfy { $0.contains(flag) }
            let some = all.contains { $0.contains(flag) }
            b.allowsMixedState = true
            b.state = on ? .on : (some ? .mixed : .off)
            initialFlags[flag] = on
            flagBoxes[flag] = b
            rows.append(line(flag == .immutable ? "Příznaky:" : "", b))
        }
        recursive.state = .off
        rows.append(line("", recursive))
        let note = NSTextField(wrappingLabelWithString: L("Změna vlastníka a skupiny vyžaduje práva správce a v TCommander není k dispozici."))
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        rows.append(line("", note))

        let stack = NSStackView(views: rows); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 5
        let alert = NSAlert()
        alert.messageText = single.map { L("Vlastnosti – \($0.name)") } ?? L("Vlastnosti – \(entries.count) položek")
        alert.accessoryView = Dialogs.fit(stack, minWidth: 520)
        alert.addButton(withTitle: L("Použít")); alert.addButton(withTitle: L("Zrušit"))
        alert.window.initialFirstResponder = perm

        // velikost složek se počítá na pozadí
        let urls = entries.map { ($0.url, $0.isDirectory, $0.size) }
        task = Task { [sizeLabel] in
            let total = await Task.detached { urls.reduce(Int64(0)) { $0 + ($1.1 ? DirectorySize.compute($1.0) : $1.2) } }.value
            if !Task.isCancelled { sizeLabel.stringValue = "\(Fmt.bytes(total)) bajtů (\(Fmt.human(total)))" }
        }
        defer { task?.cancel() }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        var r = Result(permissions: nil, modified: nil, setFlags: [], clearFlags: [], recursive: recursive.state == .on)
        if !perm.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let p = FileAttributes.parseOctal(perm.stringValue) else { Dialogs.error("Neplatná oprávnění", "Zadejte osmičkově, např. 644."); return nil }
            if single == nil || p != single!.permissions { r.permissions = p }
        }
        if !date.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let d = Self.dateFormat.date(from: date.stringValue) else { Dialogs.error("Neplatné datum", "Formát: dd.MM.yyyy HH:mm:ss"); return nil }
            if single == nil || abs(d.timeIntervalSince(single!.modified ?? .distantPast)) > 0.5 { r.modified = d }
        }
        for (flag, box) in flagBoxes {
            let was = initialFlags[flag] ?? false
            if box.state == .on && !was { r.setFlags.insert(flag) }
            if box.state == .off && (was || entries.contains { FileAttributes.flags(of: $0.url)?.contains(flag) == true }) { r.clearFlags.insert(flag) }
        }
        return r
    }
}
