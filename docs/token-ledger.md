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
| 7 – SMB  dokončení rozpracovaných funkcí (7a) | 12:44:10 – 13:07:24 (sloučení PR #24) | 17 | 34 | 66 418 | 13 552 621 | 47 837 | 13 666 910 |
| 7b – terminál a Lister | 13:07:24 – 13:20:59 (PR #25) | 19 | 38 | 60 714 | 16 387 923 | 29 612 | 16 478 287 |
| 7c – angličtina oken a dialogů | 13:20:59 – 13:35:19 (PR #26) | 12 | 24 | 60 795 | 11 092 283 | 29 440 | 11 182 542 |
| 7d – ověření proxy | 13:35:19 – 13:38:19 (PR #27) | 7 | 14 | 84 915 | 1 529 490 | 9 116 | 1 623 535 |
| 8 – zvýrazňování syntaxe | 13:38:19 – 13:45:47 (PR #28) | 8 | 16 | 20 898 | 939 755 | 12 736 | 973 405 |
| 8b – úpravy v okně porovnání | 13:45:47 – 13:49:38 (PR #29) | 9 | 18 | 21 978 | 1 273 762 | 8 419 | 1 304 177 |
| 9 – celoobrazovkový terminál | 13:49:38 – 14:00:14 (PR #31) | 21 | 42 | 52 224 | 3 705 839 | 26 977 | 3 785 082 |
| 9b – ověření WebDAV | 14:00:14 – 14:04:01 (PR #32) | 7 | 14 | 5 640 | 1 452 035 | 3 933 | 1 461 622 |
| 10 – konfigurovatelné hlavní menu | 14:04:01 – 14:12:45 (PR #33) | 15 | 30 | 42 448 | 3 488 459 | 21 872 | 3 552 809 |
| 11 – PlantUML, ADIF, YAML, SQL dialekty | 14:12:45 – 14:38:12 (PR #35) | 28 | 56 | 71 275 | 7 928 036 | 46 777 | 8 046 144 |
| 12 – oprava PageUp/PageDown | 14:38:12 – 15:03:00 (PR #37) | 23 | 46 | 28 543 | 7 793 573 | 15 816 | 7 837 978 |
| 12b – release: balíčky, Actions, v0.1.0 | 15:03:00 – 17:05:58 (PR #40) | 74 | 148 | 63 895 | 29 012 984 | 39 559 | 29 116 586 |
| 12c – dlouhé podržení pravého tlačítka, nápady na název | 17:05:58 – 20:39:25 (PR #41) | 20 | 40 | 437 948 | 8 312 147 | 32 760 | 8 782 895 |
| 12d – čtečka Markdownu, F4 se zvýrazněním | 20:39:25 – 20:58:38 (PR #42) | 21 | 42 | 41 912 | 10 086 768 | 29 077 | 10 157 799 |
| 12e – přejmenování na TCommander | 20:58:38 – 21:04:40 (PR #43) | 8 | 16 | 15 230 | 4 095 400 | 10 175 | 4 120 821 |
| 12f – ukázkové pluginy | 21:04:40 – 21:22:56 (PR #44) | 28 | 56 | 72 660 | 15 519 128 | 44 889 | 15 636 733 |
| **Celkem** | 09:37 – 21:22:56 (PR #44) | 519 | 1038 | 1 881 889 | 213 955 786 | 1 015 001 | 216 853 714 |

Poznámka: hodnoty fází 1 a 2 byly původně změřeny před kroky PR/sloučení a jsou opraveny na celé okno fáze (konec = sloučení posledního PR fáze). Původní hodnota fáze 1 (2 747 398) byla změřena před kroky PR/sloučení; zde je opravená hodnota za celé okno fáze.

Autoritativní kontrola: `/cost` v Claude Code (měla by se shodovat se součtem celého sezení).

## Jak číst „celkem“

Sloupec **cache čtení** při každém volání znovu započítává celou dosavadní konverzaci, proto je největší a součet „CELKEM“ vypadá vysoko.
Skutečně nově zpracované tokeny za celý vývoj (do PR #44): **input 1038 + cache zápis 1 881 889 + output 1 015 001 = 2 897 928**.
Cache čtení se obvykle účtuje se silnou slevou, takže pro cenu je důležité sledovat druhy zvlášť (cenu odvodíte z aktuálního ceníku).
Hodnoty se dají kdykoli přepočítat: `scripts/token_usage.py --since <ISO UTC> --until <ISO UTC>`; autoritativní kontrola je `/cost`.
