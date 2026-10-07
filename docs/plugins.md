# Pluginy TCommander

Plugin je **složka** v `~/Library/Application Support/TCommander/PlugIns/` s manifestem `plugin.json` a spustitelným souborem.
Komunikuje s aplikací přes argumenty příkazové řádky, standardní vstup a **JSON na standardním výstupu**, takže
ho lze napsat v libovolném jazyce (Python, shell, Swift, Go, …). Obdoba pluginů WDX, WLX, WCX a WFX z Total Commanderu;
binární Windows pluginy se načíst nedají.

Po přidání pluginu: Nastavení › Pluginy › *Znovu načíst*.

## Manifest

```json
{
  "name": "wordcount",
  "version": "1.0",
  "description": "Počet slov",
  "executable": "plugin.py",
  "interpreter": "/usr/bin/python3",
  "capabilities": {
    "columns":    [{"id": "words", "title": "Slov", "width": 70, "align": "right", "extensions": ["txt", "md"]}],
    "viewer":     {"extensions": ["csv"]},
    "archive":    {"extensions": ["dz"]},
    "filesystem": {"scheme": "mem"}
  }
}
```

`interpreter` je volitelný (bez něj se spustí `executable` přímo, musí mít právo spuštění). Cesta `executable` je relativní
ke složce pluginu a nesmí obsahovat `..`. Proměnná prostředí `TCOMMANDER_PLUGIN_DIR` ukazuje na složku pluginu (starší název `MACTC_PLUGIN_DIR` zůstává kvůli kompatibilitě).
Plugin musí skončit s kódem 0; chybová zpráva patří na standardní chybový výstup.

## Obsahové sloupce (WDX)

Volání: `plugin columns <id sloupce>`; na vstup přijde JSON pole cest, na výstup patří JSON objekt `{"cesta": "hodnota"}`.
Chybějící cesta = bez hodnoty. Aplikace volá plugin pro celou dávku souborů najednou a výsledky ukládá do mezipaměti
(klíč: cesta + datum změny + velikost). Sloupec se v Nastavení › Sloupce zapisuje jako `plugin:<název pluginu>:<id>`.

## Prohlížeč (WLX)

Volání: `plugin view <cesta>`; výstup `{"kind": "text" | "html" | "image", "content": "..."}`.
U `image` je `content` cesta k obrázku. Soubory s uvedenými příponami se při F3 zobrazí pluginem
(zobrazí se jako záložka vedle Text a Hex v Listeru; u souborů, které umí Lister zvýraznit, zůstává výchozím zobrazením zvýrazněný text, u ostatních a binárních je záložka pluginu první). Limit 30 s.

## Archivy (WCX)

Volání: `plugin unpack <archiv> <cílová složka>`. Panel archiv rozbalí do dočasné složky a vstoupí do ní
(jen pro čtení; změny se do archivu nevrací).

## Souborový systém (WFX)

Připojení: Síť › Připojit k serveru › typ *Plugin*; do pole *Server* patří schéma pluginu a do pole *Cesta* řetězec připojení,
který plugin dostane jako první argument. Příkazy `plugin fs <připojení> …`:

| příkaz | význam | výstup |
|---|---|---|
| `list <cesta>` | obsah adresáře | JSON pole `[{"name","dir","size","mtime","mode"}]` (`mtime` v sekundách od 1970) |
| `get <vzdálená> <místní>` | stažení souboru | – |
| `put <místní> <vzdálená>` | nahrání souboru | – |
| `rm <cesta>` | smazání souboru nebo **prázdného** adresáře | – |
| `mkdir <cesta>` | vytvoření adresáře | – |
| `mv <z> <do>` | přejmenování / přesun | – |

Cesty jsou absolutní v rámci pluginu (`/` je kořen). Mazání adresářů s obsahem řeší aplikace rekurzivně.

## Ukázky

Deset funkčních pluginů je v [`docs/plugin-examples/`](plugin-examples) (popis každého v [README](plugin-examples/README.md)) a všechny se testují automaticky:
`adifview`, `filehash`, `photoinfo`, `structview`, `macpackages`, `httpindex` a nejjednodušší `wordcount`, `csvview`, `demozip`, `memfs`.
Instalace jedním tlačítkem: Nastavení › Pluginy › *Nainstalovat ukázkové pluginy*.

## Vestavěné sloupce

Bez pluginu jsou k dispozici sloupce `plugin:builtin:dimensions` (rozměry obrázku), `duration` (délka audia a videa),
`pages` (strany PDF) a `lines` (řádky textu); sada sloupců *Média* je předvolená.
