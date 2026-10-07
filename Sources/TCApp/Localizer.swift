import TCCore

/// Přeloží český text podle jazyka v nastavení (čeština = beze změny).
@MainActor
func L(_ cs: String) -> String { Localization.translate(cs, language: AppModel.shared.settings.language) }
