import Foundation

/// Texty rozhraní webu a příručky v obou jazycích.
struct Strings {
    let lang: String
    let locale: String
    let guide: String, searchPlaceholder: String, noResults: String, previous: String, next: String, onThisSite: String
    let download: String, appStore: String, appStoreSoon: String, readGuide: String, otherLanguage: String, otherLanguageName: String
    let tagline: String, subtitle: String, featuresTitle: String, editionsTitle: String, screenshotsTitle: String, footerNote: String
    let features: [(String, String)]
    let editionsIntro: String
    let editionRows: [(String, String, String)]      // funkce, App Store, GitHub
    let editionHeads: (String, String, String)
    let privacy: String, support: String, license: String, home: String, requirements: String, faqTitle: String
    let faq: [(String, String)]

    static let en = Strings(
        lang: "en", locale: "en_US",
        guide: "User Guide", searchPlaceholder: "Search the guide…", noResults: "Nothing found.", previous: "Previous", next: "Next", onThisSite: "TCommander",
        download: "Download for macOS", appStore: "Download on the Mac App Store", appStoreSoon: "Mac App Store (coming soon)", readGuide: "Read the guide",
        otherLanguage: "cs", otherLanguageName: "Čeština",
        tagline: "The two-panel file manager for macOS.",
        subtitle: "Fast, keyboard-first file management with everything built in: viewer and editor, search, comparison and synchronization, archives as folders, FTP and network shares, a terminal and more.",
        featuresTitle: "Everything in one window", editionsTitle: "Two editions, one app", screenshotsTitle: "See it in action",
        footerNote: "Made for people who like their files organized.",
        features: [
            ("Two panels, many tabs", "Copy and move between two folders with F5 and F6. Every panel has tabs, history, favorites and four view modes: full, brief, thumbnails and tree."),
            ("Viewer with syntax highlighting", "F3 shows text in any encoding, hex, images, PDF, audio and video, plus a built-in Markdown reader. Source code is colored in 25+ languages, light and dark."),
            ("Editor", "F4 edits files with syntax highlighting while you type, and saves in the original encoding."),
            ("Search that finds anything", "Names, text inside files, regular expressions, hex bytes, dates, sizes and attributes, even inside archives. Save searches as templates."),
            ("Compare and synchronize", "Side-by-side file comparison with block transfer and live editing, folder comparison and two-way or mirror synchronization with a preview."),
            ("Archives as folders", "Browse and change zip, tar, 7z and read rar, iso and cab like ordinary folders. Pack, unpack, test."),
            ("FTP, SMB, WebDAV, SFTP", "Connect to servers and shares, resume interrupted transfers, use proxies, keep passwords in your Keychain."),
            ("Multi-Rename", "Rename hundreds of files with patterns, counters, dates, search and replace, and a live preview."),
            ("Real terminal", "A built-in terminal with colors and full-screen programs such as vim and top, right in the current folder."),
            ("Make it yours", "Change every keyboard shortcut, buttons, the Start menu and the main menu; add your own commands; import your Total Commander settings."),
            ("Plugins", "Extend it with plugins in any language: columns, viewers, archive formats and file systems. Ten working examples included."),
            ("Native and fast", "A native Apple silicon and Intel app. APFS cloning makes copies instant. English and Czech interface.")],
        editionsIntro: "TCommander is available as a free download from GitHub and on the Mac App Store. The App Store edition runs in Apple's App Sandbox: it asks once for the folders it may use, and leaves out the features that need to run other programs.",
        editionRows: [("Core file manager, viewer, editor, search, compare, sync, archives", "✓", "✓"), ("FTP, FTPS, SMB, WebDAV", "✓", "✓"), ("Built-in terminal", "✓ (allowed folders only)", "✓"),
                      ("SFTP", "–", "✓"), ("Plugins", "–", "✓"), ("PlantUML diagrams", "–", "✓"), ("Access to files", "folders you allow", "full disk")],
        editionHeads: ("", "Mac App Store", "GitHub"),
        privacy: "Privacy Policy", support: "Support", license: "Source code", home: "Home", requirements: "Requires macOS 14 Sonoma or later. Apple silicon and Intel.",
        faqTitle: "Questions",
        faq: [("Is it like Total Commander?", "Yes, in spirit: two panels, function keys and the same logic. Most keys are identical, and you can import your wincmd.ini."),
              ("Does it collect any data?", "No. No accounts, no analytics, no tracking. See the privacy policy."),
              ("Which macOS versions are supported?", "macOS 14 Sonoma and later, on Apple silicon and Intel Macs.")])

    static let cs = Strings(
        lang: "cs", locale: "cs_CZ",
        guide: "Uživatelská příručka", searchPlaceholder: "Hledat v příručce…", noResults: "Nic nenalezeno.", previous: "Předchozí", next: "Další", onThisSite: "TCommander",
        download: "Stáhnout pro macOS", appStore: "Stáhnout z Mac App Store", appStoreSoon: "Mac App Store (připravujeme)", readGuide: "Číst příručku",
        otherLanguage: "en", otherLanguageName: "English",
        tagline: "Správce souborů se dvěma panely pro macOS.",
        subtitle: "Rychlá práce se soubory z klávesnice a všechno vestavěné: prohlížeč a editor, hledání, porovnání a synchronizace, archivy jako složky, FTP a síťové disky, terminál a další.",
        featuresTitle: "Všechno v jednom okně", editionsTitle: "Dvě edice, jedna aplikace", screenshotsTitle: "Jak to vypadá",
        footerNote: "Pro lidi, kteří mají své soubory v pořádku.",
        features: [
            ("Dva panely, mnoho záložek", "Kopírujte a přesouvejte mezi dvěma složkami klávesami F5 a F6. Každý panel má záložky, historii, oblíbené a čtyři režimy zobrazení: plný, stručný, náhledy a strom."),
            ("Prohlížeč se zvýrazněním syntaxe", "F3 ukáže text v libovolném kódování, hex, obrázky, PDF, zvuk a video i vestavěnou čtečku Markdownu. Zdrojový kód je barevný ve více než 25 jazycích, světle i tmavě."),
            ("Editor", "F4 upravuje soubory se zvýrazněním syntaxe při psaní a ukládá v původním kódování."),
            ("Hledání, které najde cokoli", "Názvy, text uvnitř souborů, regulární výrazy, bajty v hexu, data, velikosti a atributy, i uvnitř archivů. Hledání lze uložit jako šablony."),
            ("Porovnání a synchronizace", "Porovnání souborů vedle sebe s přenosem bloků a úpravami přímo v okně, porovnání složek a obousměrná či zrcadlová synchronizace s náhledem."),
            ("Archivy jako složky", "Procházejte a měňte zip, tar, 7z a čtěte rar, iso a cab jako běžné složky. Balení, rozbalení, test."),
            ("FTP, SMB, WebDAV, SFTP", "Připojte se k serverům a sdíleným diskům, navazujte přerušené přenosy, používejte proxy a držte hesla v Klíčence."),
            ("Hromadné přejmenování", "Přejmenujte stovky souborů podle vzorů, počítadel, dat, hledání a nahrazení, s živým náhledem."),
            ("Skutečný terminál", "Vestavěný terminál s barvami a celoobrazovkovými programy jako vim a top, rovnou v aktuální složce."),
            ("Přizpůsobte si ho", "Změňte každou klávesovou zkratku, tlačítka, menu Start i hlavní menu; přidejte vlastní příkazy; naimportujte nastavení z Total Commanderu."),
            ("Pluginy", "Rozšiřte ho pluginy v libovolném jazyce: sloupce, prohlížeče, formáty archivů a souborové systémy. Deset funkčních příkladů v balení."),
            ("Nativní a rychlý", "Nativní aplikace pro Apple silicon i Intel. Klonování na APFS dělá kopie okamžité. Rozhraní v angličtině a češtině.")],
        editionsIntro: "TCommander je k dispozici jako bezplatné stažení z GitHubu i v Mac App Store. Edice z App Store běží v App Sandboxu Applu: jednou se zeptá, které složky smí používat, a vynechává funkce, které potřebují spouštět jiné programy.",
        editionRows: [("Správce souborů, prohlížeč, editor, hledání, porovnání, synchronizace, archivy", "✓", "✓"), ("FTP, FTPS, SMB, WebDAV", "✓", "✓"), ("Vestavěný terminál", "✓ (jen povolené složky)", "✓"),
                      ("SFTP", "–", "✓"), ("Pluginy", "–", "✓"), ("Diagramy PlantUML", "–", "✓"), ("Přístup k souborům", "složky, které povolíte", "celý disk")],
        editionHeads: ("", "Mac App Store", "GitHub"),
        privacy: "Zásady ochrany soukromí", support: "Podpora", license: "Zdrojový kód", home: "Domů", requirements: "Vyžaduje macOS 14 Sonoma nebo novější. Apple silicon i Intel.",
        faqTitle: "Otázky",
        faq: [("Je to jako Total Commander?", "Ano, duchem: dva panely, funkční klávesy a stejná logika. Většina kláves je shodná a můžete naimportovat svůj wincmd.ini."),
              ("Shromažďuje nějaká data?", "Ne. Žádné účty, analytika ani sledování. Viz zásady ochrany soukromí."),
              ("Jaké verze macOS jsou podporované?", "macOS 14 Sonoma a novější, na Macích s Apple silicon i Intel.")])
}
