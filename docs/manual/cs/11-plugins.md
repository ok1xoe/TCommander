# Pluginy

*Pluginy jsou jen v edici z GitHubu.* Edice z App Store nespouští kód z vnějšku aplikace.

Plugin je **složka** v `~/Library/Application Support/TCommander/PlugIns/` s `plugin.json` a spustitelným souborem (v libovolném jazyce: Python, shell, Swift, Go, …). S TCommanderem komunikuje přes argumenty příkazové řádky, standardní vstup a JSON na standardním výstupu. Po přidání pluginu zvolte *Nastavení ▸ Pluginy ▸ Znovu načíst*.

Plugin může přidat:

| Schopnost | Přidává | Obdoba v Total Commanderu |
|---|---|---|
| **Sloupce** | nové sloupce v seznamu souborů | obsahové pluginy (WDX) |
| **Prohlížeč** | další záložku v Listeru (F3) | pluginy Listeru (WLX) |
| **Archiv** | nový formát archivu, do kterého lze vstoupit jako do složky | pluginy balení (WCX) |
| **Souborový systém** | nový druh připojení v *Připojit k serveru* | pluginy souborových systémů (WFX) |

## Ukázkové pluginy

S aplikací se dodává deset funkčních pluginů. Nainstalujete je tlačítkem **Nastavení ▸ Pluginy ▸ Nainstalovat ukázkové pluginy** (existující složky se nikdy nepřepíšou).

| Plugin | Dělá |
|---|---|
| `adifview` | radioamatérské deníky **ADIF/ADI** jako tabulka spojení se souhrnem podle pásem a módů |
| `filehash` | sloupce MD5, SHA-1 a SHA-256 |
| `photoinfo` | sloupce fotoaparát, datum pořízení a DPI u fotografií |
| `structview` | JSON a plist (i binární) přehledně odsazené |
| `macpackages` | obsah instalátorů `.pkg` a obrazů disků `.dmg` jako složky |
| `httpindex` | webové výpisy adresářů (Apache, nginx, `python -m http.server`) jako souborový systém jen pro čtení |
| `wordcount`, `csvview`, `demozip`, `memfs` | nejjednodušší příklady jednotlivých schopností |

U souborů, které TCommander umí zvýraznit, zůstává v Listeru první záložkou zvýrazněný text a plugin je další záložka vedle *Text* a *Hex*.

## Vlastní pluginy

Úplná specifikace s formátem manifestu, způsobem volání a příklady je v repozitáři: [docs/plugins.md](https://github.com/ok1xoe/TCommander/blob/main/docs/plugins.md). Dobrým základem jsou ukázkové pluginy v `docs/plugin-examples`: každý je jeden krátký soubor v Pythonu.
