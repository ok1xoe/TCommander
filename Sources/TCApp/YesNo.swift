import TCCore

/// Hodnoty ano/ne v editovatelných tabulkách: zobrazují se v jazyce aplikace, ale zadat lze obojí (ano/ne i yes/no).
@MainActor
enum YesNo {
    static func text(_ value: Bool) -> String { Localization.translate(value ? "ano" : "ne", language: AppModel.shared.settings.language) }

    static func parse(_ text: String) -> Bool? {
        switch text.trimmingCharacters(in: .whitespaces).lowercased() {
        case "ano", "yes", "y", "a", "true", "1": return true
        case "ne", "no", "n", "false", "0": return false
        default: return nil
        }
    }
}
