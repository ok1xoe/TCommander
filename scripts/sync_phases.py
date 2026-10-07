#!/usr/bin/env python3
"""Doplní do docs/features.txt řádky @phase pro fáze 7 a dál z docs/token-ledger.md (součet řádků ledgeru se stejným číslem fáze)."""
import os, re
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = {
    7: "SMB, dokončení rozpracovaného, terminál a Lister, angličtina oken, proxy",
    8: "Zvýrazňování syntaxe, úpravy textu v okně porovnání",
    9: "Celoobrazovkový terminál, ověření WebDAV",
    10: "Konfigurovatelné hlavní menu",
    11: "PlantUML, další jazyky zvýrazňování (SQL, ADIF, YAML)",
    12: "Oprava PageUp/PageDown, release v0.1.0 a GitHub Actions, záložka z adresáře, čtečka Markdownu, F4 se zvýrazněním, přejmenování na TCommander, ukázkové pluginy",
}
total = {}
for line in open(os.path.join(root, "docs/token-ledger.md"), encoding="utf-8"):
    if not line.startswith("| ") or "Celkem" in line or "---" in line or "Fáze" in line: continue
    cols = [c.strip() for c in line.strip().strip("|").split("|")]
    m = re.match(r"(\d+)", cols[0])
    if not m or int(m.group(1)) < 7: continue
    nums = [int(c.replace(" ", "")) for c in cols[3:8]]            # input, cache zápis, cache čtení, output, celkem
    acc = total.setdefault(int(m.group(1)), [0] * 5)
    for i, v in enumerate(nums): acc[i] += v
f = lambda n: f"{n:,}".replace(",", " ")
lines = []
for n in sorted(total):
    i, cw, cr, o, t = total[n]
    lines.append(f"@phase | {n} | {NAMES.get(n, 'další vývoj')} | hotovo | {f(t)} (cache čtení {f(cr)}, output {f(o)})")
path = os.path.join(root, "docs/features.txt")
kept = [l for l in open(path, encoding="utf-8").read().split("\n") if not re.match(r"@phase \| (\d+) ", l) or int(re.match(r"@phase \| (\d+) ", l).group(1)) < 7]
last = max(i for i, l in enumerate(kept) if l.startswith("@phase"))
kept[last + 1:last + 1] = lines
open(path, "w", encoding="utf-8").write("\n".join(kept))
print("\n".join(lines))
