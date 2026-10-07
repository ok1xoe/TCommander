#!/usr/bin/env python3
"""Vygeneruje docs/index.html z docs/features.txt (soupis funkcí TC a stav implementace)."""
import html, os, subprocess, datetime
from collections import OrderedDict

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
phases, cats = [], OrderedDict()
for raw in open(os.path.join(root, "docs/features.txt"), encoding="utf-8"):
    line = raw.rstrip("\n")
    if not line.strip() or line.startswith("#"): continue
    parts = [p.strip() for p in line.split("|")]
    if parts[0] == "@phase":
        phases.append(dict(n=parts[1], name=parts[2], state=parts[3], tokens=parts[4]))
    else:
        cats.setdefault(parts[0], []).append(dict(name=parts[1], st=parts[2], phase=parts[3], note=parts[4] if len(parts) > 4 else "", miss=parts[5] if len(parts) > 5 else ""))

LABEL = {"D": "Hotovo", "P": "Částečně", "T": "Plánováno", "X": "Nepřenáší se"}
allf = [f for fs in cats.values() for f in fs]
counts = {k: sum(1 for f in allf if f["st"] == k) for k in LABEL}
scope = len(allf) - counts["X"]
done_pct = round(100 * (counts["D"] + 0.5 * counts["P"]) / scope) if scope else 0
esc = html.escape
try:
    commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=root, text=True).strip()
except Exception:
    commit = "?"

def detail(f):
    if f["st"] == "P" and (f["note"] or f["miss"]):
        out = ""
        if f["note"]: out += '<div class="note ok"><b>✔ Hotovo:</b> ' + inline(f["note"]) + "</div>"
        if f["miss"]: out += '<div class="note miss"><b>✘ Chybí:</b> ' + inline(f["miss"]) + "</div>"
        return out
    return "<div class=note>" + inline(f["note"]) + "</div>" if f["note"] else ""

def inline(s):
    out, tick = "", False
    for chunk in s.split("`"):
        out += (f"<code>{esc(chunk)}</code>" if tick else esc(chunk)); tick = not tick
    return out

phase_rows = ""
for p in phases:
    fs = [f for f in allf if f["phase"] == p["n"]]
    d = sum(1 for f in fs if f["st"] == "D"); pa = sum(1 for f in fs if f["st"] == "P")
    pct = round(100 * (d + 0.5 * pa) / len(fs)) if fs else 100
    phase_rows += (f'<tr><td>{esc(p["n"])}</td><td>{esc(p["name"])}</td><td><span class="pill {esc(p["state"])}">{esc(p["state"])}</span></td>'
                   f'<td><div class="bar"><i style="width:{pct}%"></i></div></td><td class="num">{d}/{len(fs)}</td><td class="num">{esc(p["tokens"])}</td></tr>') if fs or p["n"] == "0" else ""

sections = ""
for cat, fs in cats.items():
    d = sum(1 for f in fs if f["st"] == "D")
    rows = "".join(
        f'<tr data-st="{f["st"]}"><td>{inline(f["name"])}'
        f'{detail(f)}</td>'
        f'<td><span class="tag {f["st"]}">{LABEL[f["st"]]}</span></td><td class="num">{esc(f["phase"])}</td></tr>' for f in fs)
    sections += f'<section><h2>{esc(cat)} <small>{d}/{len(fs)}</small></h2><table>{rows}</table></section>'

now = datetime.datetime.now().strftime("%-d. %-m. %Y %H:%M")
page = f"""<!doctype html>
<html lang="cs"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>TCommander – funkce a stav</title>
<style>
:root{{--bg:#fafaf9;--fg:#1c1917;--mut:#78716c;--card:#fff;--line:#e7e5e4;--acc:#2563eb;--d:#16a34a;--p:#d97706;--t:#78716c;--x:#a8a29e}}
@media(prefers-color-scheme:dark){{:root{{--bg:#141413;--fg:#f5f5f4;--mut:#a8a29e;--card:#1c1b1a;--line:#2e2c2a;--acc:#60a5fa;--d:#4ade80;--p:#fbbf24;--t:#a8a29e;--x:#78716c}}}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,system-ui,sans-serif}}
main{{max-width:980px;margin:0 auto;padding:32px 16px 64px}}
h1{{font-size:28px;margin:0 0 4px}}h2{{font-size:17px;margin:0 0 8px}}h2 small{{color:var(--mut);font-weight:400;margin-left:6px}}
.sub{{color:var(--mut);margin:0 0 24px}}.sub a{{color:var(--acc)}}
.cards{{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;margin-bottom:20px}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:12px 14px}}
.card b{{display:block;font-size:26px;line-height:1.1}}.card span{{color:var(--mut);font-size:13px}}
.bar{{height:8px;background:var(--line);border-radius:4px;overflow:hidden;min-width:90px}}.bar i{{display:block;height:100%;background:var(--d)}}
table{{width:100%;border-collapse:collapse;background:var(--card);border:1px solid var(--line);border-radius:10px;overflow:hidden}}
td,th{{padding:7px 12px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top}}tr:last-child td{{border-bottom:0}}
th{{font-size:12px;color:var(--mut);font-weight:600}}.num{{text-align:right;white-space:nowrap;font-variant-numeric:tabular-nums}}
.note{{color:var(--mut);font-size:12.5px}}.note.ok b{{color:var(--d)}}.note.miss b{{color:var(--p)}}code{{background:var(--line);padding:1px 5px;border-radius:4px;font-size:12.5px}}
.tag,.pill{{font-size:12px;padding:2px 8px;border-radius:99px;border:1px solid currentColor;white-space:nowrap}}
.tag.D,.pill.hotovo{{color:var(--d)}}.tag.P,.pill.probíhá{{color:var(--p)}}.tag.T,.pill.plán{{color:var(--t)}}.tag.X{{color:var(--x);text-decoration:line-through}}
section{{margin:26px 0}}.filters{{display:flex;gap:6px;flex-wrap:wrap;margin:18px 0 0}}
button{{font:inherit;font-size:13px;padding:4px 12px;border-radius:99px;border:1px solid var(--line);background:var(--card);color:var(--fg);cursor:pointer}}
button[aria-pressed=true]{{background:var(--acc);border-color:var(--acc);color:#fff}}
@media(max-width:600px){{td:nth-child(3),th:nth-child(3){{display:none}}}}
</style></head><body><main>
<h1>TCommander</h1>
<p class="sub">Nativní macOS správce souborů inspirovaný Total Commanderem · soupis funkcí TC a stav implementace ·
aktualizováno {now} · commit <code>{esc(commit)}</code> · zdroj: <a href="features.txt">features.txt</a>, <a href="token-ledger.md">evidence tokenů</a></p>
<div class="cards">
<div class="card"><b>{done_pct} %</b><span>celkový postup (hotovo + ½ částečně)</span></div>
<div class="card"><b style="color:var(--d)">{counts["D"]}</b><span>hotovo</span></div>
<div class="card"><b style="color:var(--p)">{counts["P"]}</b><span>částečně</span></div>
<div class="card"><b>{counts["T"]}</b><span>plánováno</span></div>
<div class="card"><b style="color:var(--x)">{counts["X"]}</b><span>nepřenáší se (Windows)</span></div>
</div>
<h2>Fáze vývoje</h2>
<table><tr><th>#</th><th>Fáze</th><th>Stav</th><th>Postup</th><th class="num">Funkcí</th><th class="num">Spotřeba tokenů</th></tr>{phase_rows}</table>
<div class="filters" id="f"><button data-f="" aria-pressed="true">Vše</button>
<button data-f="D" aria-pressed="false">Hotovo</button><button data-f="P" aria-pressed="false">Částečně</button>
<button data-f="T" aria-pressed="false">Plánováno</button><button data-f="X" aria-pressed="false">Nepřenáší se</button></div>
{sections}
<p class="sub">Tokeny: součet z přepisů Claude Code (vstup, cache zápis, cache čtení, výstup) bez odhadů; podrobnosti v evidenci.
Logika je pokrytá automatickými testy (<code>swift test</code>), uživatelské rozhraní je zatím ověřené ručním spuštěním.</p>
</main><script>
document.getElementById('f').onclick=e=>{{const b=e.target.closest('button');if(!b)return;
document.querySelectorAll('#f button').forEach(x=>x.setAttribute('aria-pressed',x===b));
document.querySelectorAll('tr[data-st]').forEach(r=>r.style.display=!b.dataset.f||r.dataset.st===b.dataset.f?'':'none');
document.querySelectorAll('section').forEach(s=>s.style.display=[...s.querySelectorAll('tr[data-st]')].some(r=>r.style.display!=='none')?'':'none')}};
</script></body></html>"""
open(os.path.join(root, "docs/index.html"), "w", encoding="utf-8").write(page)
print(f"docs/index.html: {len(allf)} funkcí, hotovo {counts['D']}, částečně {counts['P']}, postup {done_pct} %")
