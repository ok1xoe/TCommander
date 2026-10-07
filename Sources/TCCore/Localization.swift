import Foundation

/// Anglické překlady českých textů v menu, liště a nastavení (klíčem je český text).
public enum Localization {
    public static let supported: [(code: String, title: String)] = [("cs", "Čeština"), ("en", "English")]

    public static func translate(_ cs: String, language: String) -> String {
        language == "en" ? (en[cs] ?? cs) : cs
    }

    /// Texty, které se záměrně neliší (vlastní názvy).
    public static let untranslated: Set<String> = ["Start", "Server", "Quick View (druhý panel)", "Branch view (všechny podadresáře)"]

    public static let en: [String: String] = [
        "Nový tab": "New Tab", "Zavřít tab": "Close Tab", "Soubor": "File", "Otevřít": "Open", "Hledat soubory…": "Find Files…",
        "Přejmenovat…": "Rename…", "Nový adresář…": "New Folder…", "Nový soubor…": "New File…", "Kopírovat…": "Copy…",
        "Přesunout…": "Move…", "Smazat…": "Delete…", "Smazat trvale…": "Delete Permanently…", "Ověřovat kopie (SHA-256)": "Verify Copies (SHA-256)",
        "Porovnání": "Compare", "Porovnat soubory podle obsahu…": "Compare Files by Content…", "Porovnat adresáře (označit rozdíly)": "Compare Folders (Mark Differences)",
        "Synchronizovat adresáře…": "Synchronize Folders…", "Nástroje": "Tools", "Nastavení…": "Settings…",
        "Importovat nastavení z Total Commanderu…": "Import Settings from Total Commander…", "Hromadné přejmenování…": "Multi-Rename…",
        "Vlastnosti…": "Properties…", "Kontrolní součty…": "Checksums…", "Ověřit kontrolní součty ze souboru": "Verify Checksums from File",
        "Zabalit do archivu…": "Pack to Archive…", "Rozbalit archiv…": "Unpack Archive…", "Otestovat archiv": "Test Archive",
        "Najít duplicitní soubory…": "Find Duplicate Files…", "Kódovat soubory (MIME, UUE, XXE) do druhého panelu…": "Encode Files (MIME, UUE, XXE) to Other Panel…",
        "Dekódovat soubory do druhého panelu…": "Decode Files to Other Panel…", "Rozdělit soubor…": "Split File…", "Spojit soubory (.001)…": "Combine Files (.001)…",
        "Symbolický odkaz do druhého panelu…": "Symbolic Link in Other Panel…", "Pevný odkaz do druhého panelu…": "Hard Link in Other Panel…",
        "Označit": "Mark", "Označit vše": "Mark All", "Zrušit označení": "Unmark All", "Invertovat označení": "Invert Marks",
        "Označit podle masky…": "Mark by Mask…", "Odznačit podle masky…": "Unmark by Mask…", "Označit stejnou příponu": "Mark Same Extension",
        "Uložit výběr": "Save Selection", "Obnovit výběr": "Restore Selection", "Spočítat velikosti adresářů": "Calculate Folder Sizes",
        "Síť": "Network", "Připojit k serveru…": "Connect to Server…", "Odpojit panel od serveru": "Disconnect Panel from Server",
        "Zapomenout připojení": "Forget Connection", "Karty": "Tabs", "Zamknout / odemknout kartu": "Lock / Unlock Tab",
        "Uložit sadu karet…": "Save Tab Set…", "Smazat sadu": "Delete Set", "Oblíbené": "Favorites", "Přidat aktuální adresář": "Add Current Folder",
        "Odebrat": "Remove", "Historie": "History", "Zobrazení": "View", "Skryté soubory": "Hidden Files", "Plný režim": "Full Mode",
        "Stručný režim": "Brief Mode", "Náhledy": "Thumbnails", "Strom adresářů": "Directory Tree", "Sloupce (plný režim)": "Columns (Full Mode)",
        "Panely nad sebou / vedle sebe": "Panels Stacked / Side by Side", "Obnovit": "Refresh", "Rychlý filtr": "Quick Filter",
        "Nadřazený adresář": "Parent Folder", "Zpět": "Back", "Vpřed": "Forward", "Cíl = zdroj": "Target = Source", "Prohodit panely": "Swap Panels",
        "Další tab": "Next Tab", "Předchozí tab": "Previous Tab",
        "příkaz (Enter spustí, „cd cesta“ změní adresář)": "command (Enter runs it, “cd path” changes folder)",
        "F2 Přejmenovat": "F2 Rename", "⌃M Hromadně": "⌃M Multi-Rename", "F3 Zobrazit": "F3 View", "F4 Editovat": "F4 Edit",
        "F5 Kopírovat": "F5 Copy", "F6 Přesunout": "F6 Move", "F7 Nový adresář": "F7 New Folder", "⌥F7 Hledat": "⌥F7 Find", "F8 Smazat": "F8 Delete",
        "Cesta": "Path", "Rychlý filtr (Esc zruší)": "Quick filter (Esc clears)", "Domů": "Home", "Aplikace": "Applications",
        "Obecné": "General", "Zkratky": "Shortcuts", "Tlačítková lišta": "Button Bar", "Start menu": "Start Menu",
        "Uživatelské příkazy": "User Commands", "Přidružení souborů": "File Associations", "Sloupce": "Columns", "Barvy": "Colors", "Pluginy": "Plugins",
        // výchozí tlačítka a Start menu
        "Zobrazit": "View", "Editovat": "Edit", "Kopírovat": "Copy", "Přesunout": "Move", "Nový adresář": "New Folder", "Smazat": "Delete",
        "Hledat": "Find", "Hromadně": "Multi-Rename", "Porovnat": "Compare", "Synchronizovat": "Synchronize", "Server": "Server", "Nastavení": "Settings",
        "Terminál zde": "Terminal Here", "Monitor aktivity": "Activity Monitor", "Systémová nastavení": "System Settings", "Zobrazit ve Finderu": "Reveal in Finder",
        "Terminál": "Terminal",
    ]
}
