#!/usr/bin/env python3
"""Souborový systém nad webovým výpisem adresáře (jen pro čtení).

Připojení: Síť › Připojit k serveru › Plugin; Server = `http`, Cesta = adresa výpisu, např. `http://localhost:8000/` nebo `https://server/pub/`.
Volání: plugin.py fs <adresa> list <cesta> | get <vzdálená> <místní>; ostatní příkazy skončí chybou (server je jen pro čtení).
Rozpozná běžné výpisy Apache, nginx a `python -m http.server`; velikost a datum bere z výpisu, jinak z hlaviček HEAD (nejvýš 200 položek).
"""
import sys, re, json, html, calendar, time, shutil
from urllib.parse import urljoin, unquote, urlparse, quote
from urllib.request import Request, urlopen

TIMEOUT = 30
LINK = re.compile(r'<a\s+[^>]*href\s*=\s*"([^"]*)"[^>]*>(.*?)</a>(.*)', re.I)
DATE_FORMS = [("%Y-%m-%d %H:%M", re.compile(r"\d{4}-\d{2}-\d{2} \d{2}:\d{2}")), ("%d-%b-%Y %H:%M", re.compile(r"\d{2}-[A-Za-z]{3}-\d{4} \d{2}:\d{2}"))]
SIZE = re.compile(r"(?:^|\s)(\d+(?:\.\d+)?)([KMGT]?)\s*$")


def base_url(connection):
    c = connection.strip()
    if "://" not in c: c = "http://" + c
    return c if c.endswith("/") else c + "/"


def url_for(connection, path):
    return urljoin(base_url(connection), quote(path.lstrip("/")))


def fetch(url, method="GET"):
    return urlopen(Request(url, method=method, headers={"User-Agent": "TCommander-httpindex"}), timeout=TIMEOUT)


def parse_trailer(text):
    """Z textu za odkazem vytáhne datum (sekundy od 1970) a velikost v bajtech."""
    text = html.unescape(re.sub(r"<[^>]+>", " ", text)).strip()
    mtime = size = 0
    for form, regex in DATE_FORMS:
        m = regex.search(text)
        if m:
            try: mtime = calendar.timegm(time.strptime(m.group(0), form))
            except ValueError: pass
            text = text[:m.start()] + text[m.end():]
            break
    m = SIZE.search(text.strip())
    if m:
        size = int(float(m.group(1)) * {"": 1, "K": 1024, "M": 1024 ** 2, "G": 1024 ** 3, "T": 1024 ** 4}[m.group(2)])
    return mtime, size


def listing(connection, path):
    url = url_for(connection, path.rstrip("/") + "/" if path.strip("/") else "")
    page = fetch(url).read().decode("utf-8", "replace")
    base_path = urlparse(url).path
    entries, seen = [], set()
    for line in page.splitlines():
        for m in LINK.finditer(line):
            href, label, trailer = m.group(1), m.group(2), m.group(3)
            if not href or href.startswith(("?", "#")) or "://" in href or href.startswith("//"):
                continue
            target = urljoin(url, href)
            rel = urlparse(target).path
            if not rel.startswith(base_path) or rel == base_path or "/" in rel[len(base_path):].rstrip("/"):
                continue                                              # nadřazený adresář, jiný web nebo hlubší cesta
            name = unquote(rel[len(base_path):].rstrip("/"))
            if not name or name in seen: continue
            seen.add(name)
            mtime, size = parse_trailer(trailer)
            entries.append({"name": name, "dir": rel.endswith("/"), "size": 0 if rel.endswith("/") else size, "mtime": mtime, "mode": 0o755 if rel.endswith("/") else 0o644, "_url": target})
    if len(entries) <= 200:
        for e in entries:
            if not e["dir"] and (e["size"] == 0 or e["mtime"] == 0):
                try:
                    h = fetch(e["_url"], "HEAD").headers
                    if e["size"] == 0 and h.get("Content-Length"): e["size"] = int(h["Content-Length"])
                    if e["mtime"] == 0 and h.get("Last-Modified"):
                        e["mtime"] = calendar.timegm(time.strptime(h["Last-Modified"], "%a, %d %b %Y %H:%M:%S GMT"))
                except Exception:
                    pass
    for e in entries: e.pop("_url", None)
    return entries


def main():
    if len(sys.argv) < 4 or sys.argv[1] != "fs":
        sys.stderr.write("použití: plugin.py fs <adresa> <příkaz> …\n"); sys.exit(2)
    connection, cmd = sys.argv[2], sys.argv[3]
    if cmd == "list":
        print(json.dumps(listing(connection, sys.argv[4])))
    elif cmd == "get":
        with fetch(url_for(connection, sys.argv[4])) as r, open(sys.argv[5], "wb") as out:
            shutil.copyfileobj(r, out)
    else:
        sys.stderr.write("HTTP výpis je jen pro čtení (příkaz „%s“ není podporován)\n" % cmd); sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        sys.stderr.write("%s\n" % e); sys.exit(1)
