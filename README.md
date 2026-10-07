# macTC

Nativní správce souborů pro macOS inspirovaný Total Commanderem. Swift 6, SwiftUI + AppKit, Swift Package (bez Xcode projektu).

## Spuštění

```bash
scripts/bundle.sh        # složí dist/macTC.app (release build, ad-hoc podpis)
open dist/macTC.app
swift run macTC          # nebo přímo z balíčku
scripts/test.sh          # testy (swift test + cesta k pluginu Swift Testing pro Command Line Tools)
```

Požadavky: macOS 14+, Swift 6 (stačí Command Line Tools). Aplikace není v App Store sandboxu (potřebuje plný přístup k disku); při prvním spuštění může být nutné povolit ji v Systémové nastavení › Soukromí a zabezpečení.

## Co umí

Dva panely s kartami, režimy Plný / Stručný / Náhledy / Strom, vlastní sloupce, barvy souborů, lišta disků, fronta operací s průběhem a pauzou,
kopírování s ověřením, Lister (text, hex, obrázky, PDF, média, HTML), hledání (i uvnitř archivů a podle obsahu), Multi-Rename,
porovnání a synchronizace adresářů (i s archivy), kontrolní součty, rozdělení a spojení souborů, archivy jako adresáře (zip, tar.*, 7z, rar, …),
FTP/FTPS, SFTP, SMB a WebDAV, terminál, vestavěný editor, příkazy a konfigurovatelné zkratky, tlačítková lišta, pluginy, import z Total Commanderu, čeština a angličtina.

**Přesný soupis všech funkcí TC a stav implementace (včetně toho, co je u částečných funkcí hotové a co chybí):** [docs/index.html](docs/index.html)
(generuje se příkazem `python3 scripts/build_docs.py` ze souboru [docs/features.txt](docs/features.txt)).

## Dokumentace

- [docs/spec.md](docs/spec.md) – návrh a architektura
- [docs/plugins.md](docs/plugins.md) – pluginy (sloupce, prohlížeče, archivy, souborové systémy), ukázky v `docs/plugin-examples/`
- [docs/token-ledger.md](docs/token-ledger.md) – evidence spotřeby tokenů po fázích (`scripts/token_usage.py`)

## Architektura

- `TCCore` – logika bez UI: virtuální souborové systémy (lokální, archiv, FTP, SFTP, plugin), souborové operace, hledání, synchronizace, přejmenování, příkazy, pluginy. Pokrytá automatickými testy.
- `TCApp` – SwiftUI/AppKit rozhraní.
- `CArchive`, `CCurl` – tenké vazby na systémové knihovny libarchive a libcurl.

## Známá omezení

Nastavení uložené v `~/Library/Application Support/macTC/`. SMB, WebDAV, TLS u FTP, SOCKS proxy a přihlášení heslem u SFTP jsou implementované, ale nebyly ověřeny proti skutečné službě.
Většina oken a dialogů je ověřená spuštěním a snímky, nikoli automatizovanými UI testy; automaticky testovaná je logika.
