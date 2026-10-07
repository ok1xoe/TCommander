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
| 2 – fronta, Lister, hledání, nástroje | 10:01:27 – otevření PR 2f | 39 | 78 | 110 920 | 8 516 701 | 90 868 | 8 718 567 |
| 3 – Multi-Rename, porovnání, sync | | | | | | | |
| 4 – archivy | | | | | | | |
| 5 – síť | | | | | | | |
| 6 – pluginy, button bar, nastavení | | | | | | | |

Poznámka: původní hodnota fáze 1 (2 747 398) byla změřena před kroky PR/sloučení; zde je opravená hodnota za celé okno fáze.

Autoritativní kontrola: `/cost` v Claude Code (měla by se shodovat se součtem celého sezení).
