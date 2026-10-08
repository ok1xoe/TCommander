# Archivy

Archivy se chovají jako složky. **Return** na archivu do něj vstoupí; ven se vrátíte klávesou Backspace.

| Formát | Procházení | Rozbalení | Změny obsahu |
|---|---|---|---|
| zip, tar, tar.gz, tar.bz2, tar.xz, 7z | ano | ano | ano |
| rar, iso, cab a další podporované knihovnou libarchive | ano | ano | jen čtení |

## Práce v archivu

- **F5** z archivu soubory vybalí, **F5** do archivu je přidá. **F6** z archivu není možné (archiv lze jen číst); **F8**, **F2** a **F7** mění obsah zapisovatelných archivů. TCommander archiv přepíše bezpečně (starý soubor zůstane, dokud není nový kompletní).
- **F3** zobrazí soubor přímo z archivu.
- **Alt+F5** zabalí označené soubory do nového archivu (zvolíte formát a název), **Alt+F9** archiv rozbalí do složky; lze rozbalit i více archivů najednou, každý do vlastní složky.
- *Nástroje ▸ Otestovat archiv* ověří integritu archivu.
- Hledání (Alt+F7) umí prohledávat archivy a archivy se mohou účastnit [synchronizace](06-compare-sync-rename.html#synchronizace-slozek).

## Poznámky

- Archivy zpracovává systémová knihovna *libarchive*; nic se nikam nenahrává.
- Velké archivy se otevírají rychle, protože se čte jen jejich index.
