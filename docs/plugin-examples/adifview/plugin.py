#!/usr/bin/env python3
"""Prohlížeč deníků ADIF/ADI: tabulka spojení (QSO) a souhrn podle pásem a módů.

Volání: plugin.py view <soubor.adi>   →   JSON {"kind": "html", "content": "..."}
Délky polí jsou v ADI v bajtech, proto se soubor čte jako bajty a hodnoty se dekódují jako UTF-8.
"""
import sys, re, json, html
from collections import Counter

FIELD = re.compile(rb"<([A-Za-z0-9_]+)(?::(\d+))?(?::[A-Za-z])?>", re.I)
MAX_ROWS = 5000


def parse(data):
    """Vrací (pole hlavičky, seznam záznamů); záznam je slovník NÁZEV → hodnota."""
    header, records, current, in_header = {}, [], {}, not data.lstrip().startswith(b"<")
    pos = 0
    while True:
        m = FIELD.search(data, pos)
        if not m:
            break
        name = m.group(1).decode("ascii").upper()
        if name == "EOH":
            in_header = False; pos = m.end(); continue
        if name == "EOR":
            if current: records.append(current)
            current = {}; pos = m.end(); continue
        length = int(m.group(2) or 0)
        end = m.end() + length
        if end < len(data) and data[end:end + 1] not in (b" ", b"\t", b"\r", b"\n", b"<"):
            nxt = data.find(b"<", end)                              # délka byla ve znacích, ne v bajtech: hodnotu prodluž
            end = nxt if nxt != -1 else len(data)
        value = data[m.end():end]
        nxt = FIELD.search(value)                                   # naopak neuřízni další pole, pokud je délka větší než hodnota
        if nxt and nxt.start() < len(value): value = value[:nxt.start()]
        text = value.decode("utf-8", "replace").strip()
        (header if in_header else current)[name] = text
        pos = m.end() + len(value)
    if current: records.append(current)
    return header, records


def fmt_date(d):
    return "%s-%s-%s" % (d[:4], d[4:6], d[6:8]) if len(d) == 8 and d.isdigit() else d


def fmt_time(t):
    t = t.ljust(4, "0")
    return "%s:%s" % (t[:2], t[2:4]) if t[:4].isdigit() else t


def render(path):
    header, records = parse(open(path, "rb").read())
    records.sort(key=lambda r: (r.get("QSO_DATE", ""), r.get("TIME_ON", "")))
    bands = Counter(r.get("BAND", "?").lower() for r in records)
    modes = Counter(r.get("MODE", "?").upper() for r in records)
    calls = {r.get("CALL", "").upper() for r in records if r.get("CALL")}
    e = html.escape
    first = fmt_date(records[0].get("QSO_DATE", "")) if records else "–"
    last = fmt_date(records[-1].get("QSO_DATE", "")) if records else "–"

    def chips(counter):
        return " ".join("<span class=chip>%s <b>%d</b></span>" % (e(k), v) for k, v in counter.most_common())

    rows = []
    for r in records[:MAX_ROWS]:
        rst = "/".join(x for x in (r.get("RST_SENT", ""), r.get("RST_RCVD", "")) if x)
        rows.append("<tr><td>%s</td><td>%s</td><td class=call>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>" % (
            e(fmt_date(r.get("QSO_DATE", ""))), e(fmt_time(r.get("TIME_ON", ""))), e(r.get("CALL", "")),
            e(r.get("BAND", "") or r.get("FREQ", "")), e(r.get("MODE", "")), e(rst),
            e(r.get("QTH", "") or r.get("GRIDSQUARE", "")), e(r.get("COMMENT", "") or r.get("NAME", ""))))
    note = "<p class=note>Zobrazeno prvních %d spojení z %d.</p>" % (MAX_ROWS, len(records)) if len(records) > MAX_ROWS else ""
    program = header.get("PROGRAMID", "")
    title = "Deník ADIF" + (" (%s)" % e(program) if program else "")
    body = """<!doctype html><meta charset=utf-8><style>
    :root{color-scheme:light dark} body{font:14px -apple-system,sans-serif;margin:20px} h1{font-size:20px;margin:0 0 4px}
    .sum{margin:8px 0 16px;color:#666} .chip{display:inline-block;border:1px solid #8884;border-radius:10px;padding:1px 8px;margin:2px}
    table{border-collapse:collapse;width:100%%} th,td{text-align:left;padding:4px 10px;border-bottom:1px solid #8883}
    th{position:sticky;top:0;background:Canvas} td.call{font-weight:600} .note{color:#a60}
    </style><h1>%s</h1><div class=sum>%d spojení · %d různých značek · %s – %s</div>
    <div>Pásma: %s</div><div>Módy: %s</div><br><table><tr><th>Datum</th><th>UTC</th><th>Značka</th><th>Pásmo</th><th>Mód</th><th>RST</th><th>QTH</th><th>Poznámka</th></tr>%s</table>%s""" % (
        title, len(records), len(calls), e(first), e(last), chips(bands) or "–", chips(modes) or "–", "".join(rows), note)
    return {"kind": "html", "content": body}


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "view":
        print(json.dumps(render(sys.argv[2])))
    else:
        sys.stderr.write("použití: plugin.py view <soubor>\n"); sys.exit(2)
