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
    let editionRows: [(String, String, String, String)]      // funkce, GitHub, App Store, důvod
    let editionHeads: (String, String, String, String)
    let privacy: String, support: String, license: String, home: String, requirements: String, faqTitle: String
    let faq: [(String, String)]
    let downloadTitle: String, githubEditionTitle: String, githubEditionText: String, storeEditionTitle: String, storeEditionText: String
    let yes: String, no: String, allScreenshots: String
    let switchTitle: String, switchItems: [(String, String)], notFoundText: String

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
        editionsIntro: "TCommander is one app in two editions. The GitHub edition is a free download with full access to your disk. The Mac App Store edition is installed and updated by the App Store and runs in Apple's App Sandbox, a protection Apple requires of every app in the store. It asks you once which folders it may use, and a few features that need to run other programs are left out.",
        editionRows: [("File manager, viewer, editor, search, compare, sync, archives", "✓", "✓", ""),
                      ("FTP, FTPS, SMB, WebDAV", "✓", "✓", ""),
                      ("Built-in terminal", "✓", "✓", "In the App Store edition the shell reaches only the folders you allowed."),
                      ("SFTP", "✓", "✗", "It needs the system ssh and your keys, which the sandbox blocks."),
                      ("Plugins", "✓", "✗", "Apple does not allow apps to run downloaded code."),
                      ("PlantUML diagrams", "✓", "✗", "They need Java and an external program. The diagram source is still shown as text."),
                      ("Access to your files", "Whole disk (macOS asks once per protected folder)", "Only folders you choose, once", "The App Sandbox is required for every app in the store."),
                      ("Updates", "Download a new release", "Automatic, through the App Store", "")],
        editionHeads: ("Feature", "GitHub edition", "Mac App Store edition", "Why"),
        privacy: "Privacy Policy", support: "Support", license: "Source code", home: "Home", requirements: "Requires macOS 14 Sonoma or later. Apple silicon and Intel.",
        faqTitle: "Questions",
        faq: [("Is it like Total Commander?", "Yes, in spirit: two panels, function keys and the same logic. Most keys are identical, and you can import your wincmd.ini."),
              ("Does it collect any data?", "No. No accounts, no analytics, no tracking. See the privacy policy."),
              ("Which macOS versions are supported?", "macOS 14 Sonoma and later, on Apple silicon and Intel Macs.")],
        downloadTitle: "Get TCommander", githubEditionTitle: "GitHub edition", githubEditionText: "A free download with every feature: a universal disk image or zip for macOS 14 or later. On first launch, right-click the app and choose Open.",
        storeEditionTitle: "Mac App Store edition", storeEditionText: "Installs and updates automatically. It runs in the App Sandbox, so you allow your folders once. SFTP, plugins and PlantUML diagrams are not included.",
        yes: "Yes", no: "No", allScreenshots: "Show all screenshots",
        switchTitle: "Coming from Total Commander?",
        switchItems: [("The same keys", "F3 view, F4 edit, F5 copy, F6 move, F7 new folder, F8 delete: your fingers already know them."),
                      ("Bring your settings", "Import your wincmd.ini: shortcuts, the button bar and the Start menu come across."),
                      ("Made for the Mac", "Retina and dark mode, Quick View, the Keychain, APFS cloning and a real terminal.")],
        notFoundText: "This page does not exist. Go to the home page or search the guide.")

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
        editionsIntro: "TCommander je jedna aplikace ve dvou edicích. Edice z GitHubu je bezplatné stažení s plným přístupem k disku. Edice z Mac App Store se instaluje a aktualizuje přes App Store a běží v App Sandboxu, což je ochrana, kterou Apple vyžaduje u každé aplikace v obchodě. Jednou se zeptá, které složky smí používat, a pár funkcí, které potřebují spouštět jiné programy, v ní není.",
        editionRows: [("Správce souborů, prohlížeč, editor, hledání, porovnání, synchronizace, archivy", "✓", "✓", ""),
                      ("FTP, FTPS, SMB, WebDAV", "✓", "✓", ""),
                      ("Vestavěný terminál", "✓", "✓", "V edici z App Store dosáhne shell jen na složky, které jste povolili."),
                      ("SFTP", "✓", "✗", "Potřebuje systémový ssh a vaše klíče, které sandbox blokuje."),
                      ("Pluginy", "✓", "✗", "Apple nepovoluje aplikacím spouštět stažený kód."),
                      ("Diagramy PlantUML", "✓", "✗", "Potřebují Javu a externí program. Zdroj diagramu se dál zobrazí jako text."),
                      ("Přístup k souborům", "Celý disk (macOS se zeptá jednou u každé chráněné složky)", "Jen složky, které jednou vyberete", "App Sandbox je u každé aplikace v obchodě povinný."),
                      ("Aktualizace", "Stáhnete novou verzi", "Automaticky přes App Store", "")],
        editionHeads: ("Funkce", "Edice z GitHubu", "Edice z Mac App Store", "Proč"),
        privacy: "Zásady ochrany soukromí", support: "Podpora", license: "Zdrojový kód", home: "Domů", requirements: "Vyžaduje macOS 14 Sonoma nebo novější. Apple silicon i Intel.",
        faqTitle: "Otázky",
        faq: [("Je to jako Total Commander?", "Ano, duchem: dva panely, funkční klávesy a stejná logika. Většina kláves je shodná a můžete naimportovat svůj wincmd.ini."),
              ("Shromažďuje nějaká data?", "Ne. Žádné účty, analytika ani sledování. Viz zásady ochrany soukromí."),
              ("Jaké verze macOS jsou podporované?", "macOS 14 Sonoma a novější, na Macích s Apple silicon i Intel.")],
        downloadTitle: "Získejte TCommander", githubEditionTitle: "Edice z GitHubu", githubEditionText: "Bezplatné stažení se všemi funkcemi: univerzální obraz disku nebo zip pro macOS 14 a novější. Při prvním spuštění klepněte na aplikaci pravým tlačítkem a zvolte Otevřít.",
        storeEditionTitle: "Edice z Mac App Store", storeEditionText: "Instaluje se a aktualizuje automaticky. Běží v App Sandboxu, takže své složky povolíte jednou. SFTP, pluginy a diagramy PlantUML v ní nejsou.",
        yes: "Ano", no: "Ne", allScreenshots: "Zobrazit všechny snímky",
        switchTitle: "Přicházíte z Total Commanderu?",
        switchItems: [("Stejné klávesy", "F3 prohlížet, F4 upravit, F5 kopírovat, F6 přesunout, F7 nová složka, F8 smazat: prsty je už znají."),
                      ("Přeneste si nastavení", "Naimportujte svůj wincmd.ini: zkratky, tlačítková lišta i menu Start se převedou."),
                      ("Stvořený pro Mac", "Retina a tmavý vzhled, Quick View, Klíčenka, klonování na APFS a skutečný terminál.")],
        notFoundText: "Tato stránka neexistuje. Přejděte na úvodní stránku nebo hledejte v příručce.")
}
