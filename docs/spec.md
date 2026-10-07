# macTC – návrh

Cíl: nativní macOS aplikace pokrývající funkce Total Commanderu (https://www.ghisler.com/featurel.htm). Distribuce mimo App Store (potřebuje plný přístup k disku). macOS 14+, Swift 6, bez Xcode projektu (jen SwiftPM).

## Architektura
- `TCCore` – bez UI: `VirtualFileSystem` protokol (list/stat/read/write/move/delete), lokální FS, fronta operací (actor), vyhledávání, synchronizace, přejmenování, archivy, síť.
- `TCApp` – SwiftUI/AppKit: okno se dvěma panely (`NSTableView` přes `NSViewRepresentable`), karty, dialogy, Lister.
- Příkazy jako `enum Command` + konfigurovatelné klávesové zkratky.

## Fáze (každá = větev, PR, merge)
1. Dva panely, navigace, výběr, F3–F8 základní operace, karty, klávesnice, příkazová řádka.
2. Fronta operací s progresem, filtry, hotlist, Lister (text/hex/obrázek), hledání (Alt+F7), kontrolní součty, rozdělení/spojení.
3. Multi-Rename Tool, porovnání souborů/adresářů, synchronizace adresářů.
4. Archivy jako adresáře (ZIP/TAR/GZ… přes libarchive), balení/rozbalení.
5. Síť: FTP/FTPS, SFTP, SMB, WebDAV přes VFS.
6. Plugin API (Swift protokoly), button bar, konfigurovatelné menu/zkratky, Branch view, nastavení.

## Vynecháno / nahrazeno
Paralelní port, Windows UAC, binární Windows pluginy (WCX/WFX/WLX/WDX) – nahrazeno vlastním Swift plugin API.
