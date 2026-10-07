import SwiftUI
import AppKit
import TCCore

extension View {
    /// Skryje položku hlavního menu (včetně její zkratky), pokud ji uživatel vypnul v Nastavení › Hlavní menu.
    @ViewBuilder func hideable(_ model: AppModel, _ key: String) -> some View {
        if model.mainMenu.isVisible(key) { self }
    }
}

enum MenuShortcut {
    /// Převod zkratky z nastavení na zkratku SwiftUI menu; nil pro prázdnou nebo neplatnou zkratku.
    static func keyboardShortcut(_ text: String) -> KeyboardShortcut? {
        guard let s = Shortcut(text) else { return nil }
        let named: [String: KeyEquivalent] = [
            "return": .return, "tab": .tab, "space": .space, "delete": .deleteForward, "backspace": .delete, "escape": .escape,
            "up": .upArrow, "down": .downArrow, "left": .leftArrow, "right": .rightArrow, "home": .home, "end": .end,
            "pageup": .pageUp, "pagedown": .pageDown,
        ]
        var key: KeyEquivalent?
        if let k = named[s.key] { key = k }
        else if s.key.hasPrefix("f"), let n = Int(s.key.dropFirst()), (1...12).contains(n), let u = UnicodeScalar(NSF1FunctionKey + n - 1) { key = KeyEquivalent(Character(u)) }
        else if s.key.count == 1, let c = s.key.first { key = KeyEquivalent(c) }
        guard let key else { return nil }
        var m: EventModifiers = []
        if s.modifiers.contains(.ctrl) { m.insert(.control) }
        if s.modifiers.contains(.alt) { m.insert(.option) }
        if s.modifiers.contains(.shift) { m.insert(.shift) }
        if s.modifiers.contains(.cmd) { m.insert(.command) }
        return KeyboardShortcut(key, modifiers: m)
    }
}

/// Vlastní menu z nastavení (položky, podmenu, oddělovače a zkratky).
struct CustomMenuContent: View {
    let model: AppModel
    let nodes: [MenuNode]

    var body: some View {
        ForEach(nodes) { node in
            switch node {
            case .separator: Divider()
            case .item(let item):
                Button(item.title) { model.run(command: item.command, parameters: item.parameters) }
                    .keyboardShortcut(MenuShortcut.keyboardShortcut(item.shortcut))
            case .submenu(let name, let children):
                Menu(name) { AnyView(CustomMenuContent(model: model, nodes: children)) }
            }
        }
    }
}
