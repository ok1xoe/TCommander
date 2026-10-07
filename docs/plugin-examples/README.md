# Ukázkové pluginy

Všechny jsou v Pythonu 3 (stačí systémový `/usr/bin/python3`, bez dalších balíčků) a slouží zároveň jako předloha pro vlastní pluginy
(popis rozhraní je v [../plugins.md](../plugins.md)). Do aplikace se dají nainstalovat jedním tlačítkem:
**Nastavení › Pluginy › Nainstalovat ukázkové pluginy** (existující složky se nepřepíšou). Ručně stačí zkopírovat složku do
`~/Library/Application Support/TCommander/PlugIns/` a dát *Znovu načíst*.

| Plugin | Druh | Co dělá |
|---|---|---|
| `adifview` | prohlížeč (F3) | Deník ADIF/ADI jako tabulka spojení seřazená podle data, se souhrnem podle pásem a módů. Pozor: při instalaci nahradí v F3 zvýrazněný text těchto souborů; textový pohled zůstane v Listeru dostupný ze záložky *Text*, jen když plugin odebereš, vrátí se původní chování. |
| `filehash` | sloupce | Kontrolní součty MD5, SHA-1 a SHA-256 jako sloupce panelu (soubory do 256 MB). |
| `photoinfo` | sloupce | Fotoaparát, datum pořízení a DPI fotografií (přes systémový `sips`). |
| `structview` | prohlížeč (F3) | JSON (i na jeden řádek) a plist (XML i binární, `.mobileconfig`, `.entitlements`) jako odsazený text. |
| `macpackages` | archiv | Obsah instalačních balíčků `.pkg` (`pkgutil --expand-full`) a obrazů disků `.dmg` (`hdiutil`, jen pro čtení). |
| `httpindex` | souborový systém | Webové výpisy adresářů (Apache, nginx, `python -m http.server`) jako souborový systém jen pro čtení; stahování souborů i složek. Připojení: Síť › Připojit k serveru › Plugin, Server `http`, Cesta např. `http://localhost:8000/`. |
| `wordcount` | sloupce | Počet slov a znaků textových souborů (nejjednodušší ukázka sloupců). |
| `csvview` | prohlížeč (F3) | CSV jako HTML tabulka (nejjednodušší ukázka prohlížeče). |
| `demozip` | archiv | Vymyšlený formát `.dz` (nejjednodušší ukázka archivu). |
| `memfs` | souborový systém | Souborový systém nad adresářem na disku (nejjednodušší ukázka WFX, používá se v testech). |

Plugin musí skončit s kódem 0, výsledek patří na standardní výstup jako JSON a chyby na standardní chybový výstup; aplikace plugin po 30 s ukončí.
Všechny ukázky mají automatické testy (`Tests/TCCoreTests/ExamplePluginTests.swift`).
