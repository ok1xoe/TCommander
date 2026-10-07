# Evidence spotřeby tokenů po fázích

**Zdroj:** přepisy Claude Code (`~/.claude/projects/.../*.jsonl`, pole `usage` u každé odpovědi, včetně subagentů),
zpracované skriptem `scripts/token_usage.py` (deduplikace podle `message.id`). Žádné odhady.
Počítadlo `<total_tokens>` v kontextu se nepoužívá (není kumulativní).

```bash
scripts/token_usage.py --since <ISO UTC> --until <ISO UTC>
```

Sloupce: **input** = necachovaný vstup, **cache zápis** = poprvé zapsaný kontext, **cache čtení** = opakovaně čtený kontext
(při každém volání se znovu čte celá konverzace, proto je tento sloupec největší a „CELKEM“ vypadá vysoko),
**output** = vygenerované tokeny. Pro cenu mají tyto druhy různé sazby – proto jsou odděleně.

| Fáze | Okno (UTC) | Volání | input | cache zápis | cache čtení | output | CELKEM |
|---|---|---:|---:|---:|---:|---:|---:|
| 0 – průzkum a návrh | start – 2026-10-07T09:44 | 9 | 18 | 39 530 | 533 596 | 9 064 | 582 208 |
| 1 – panely a základní operace | 09:44 – 10:01:27 (sloučení PR #1) | 26 | 52 | 92 765 | 3 067 722 | 76 954 | 3 237 493 |
| 2 – fronta, Lister, hledání, nástroje | 10:01:27 – 10:33:41 (sloučení PR #7) | 41 | 82 | 113 116 | 9 067 468 | 93 127 | 9 273 793 |
| 3 – Multi-Rename, porovnání, sync, duplicity | 10:33:41 – 10:46:33 (sloučení PR #10) | 14 | 28 | 54 582 | 4 257 286 | 52 593 | 4 364 489 |
| 4 – archivy | 10:46:33 – 11:06:56 (sloučení PR #12) | 24 | 48 | 73 697 | 8 779 513 | 66 180 | 8 919 438 |
| 5 – síť | 11:06:56 – 11:33:43 (sloučení PR #15) | 30 | 60 | 122 438 | 14 233 788 | 112 195 | 14 468 481 |
| 6 – příkazy, nastavení, vzhled, pluginy, terminál, editor | 11:33:43 – závěr | 58 | 116 | 238 268 | 37 846 210 | 195 893 | 38 280 487 |
| **Celkem** | 09:37 – závěr | 202 | 404 | 734 396 | 77 785 583 | 606 006 | 79 126 389 |

Poznámka: hodnoty fází 1 a 2 byly původně změřeny před kroky PR/sloučení a jsou opraveny na celé okno fáze (konec = sloučení posledního PR fáze). Původní hodnota fáze 1 (2 747 398) byla změřena před kroky PR/sloučení; zde je opravená hodnota za celé okno fáze.

Autoritativní kontrola: `/cost` v Claude Code (měla by se shodovat se součtem celého sezení).

## Jak číst „celkem“

Sloupec **cache čtení** při každém volání znovu započítává celou dosavadní konverzaci, proto je největší a součet „CELKEM“ vypadá vysoko.
Skutečně nově zpracované tokeny za celý vývoj: **input 404 + cache zápis 734 396 + output 606 006 = 1 340 806**.
Cache čtení se obvykle účtuje se silnou slevou, takže pro cenu je důležité sledovat druhy zvlášť (cenu odvodíte z aktuálního ceníku).
Hodnoty se dají kdykoli přepočítat: `scripts/token_usage.py --since <ISO UTC> --until <ISO UTC>`; autoritativní kontrola je `/cost`.
