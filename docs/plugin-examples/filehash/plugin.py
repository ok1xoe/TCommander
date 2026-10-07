#!/usr/bin/env python3
"""Sloupce s kontrolními součty souborů (MD5, SHA-1, SHA-256).

Volání: plugin.py columns <md5|sha1|sha256>; na vstup přijde JSON pole cest, na výstup patří JSON {"cesta": "hodnota"}.
Adresáře a soubory větší než LIMIT se přeskočí (součet velkého souboru by zdržel zobrazení panelu).
"""
import sys, os, json, hashlib

LIMIT = 256 * 1024 * 1024


def digest(path, algorithm):
    h = hashlib.new(algorithm)
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


if __name__ == "__main__" and len(sys.argv) >= 3 and sys.argv[1] == "columns":
    algorithm = {"md5": "md5", "sha1": "sha1", "sha256": "sha256"}.get(sys.argv[2])
    if not algorithm:
        sys.exit(2)
    out = {}
    for p in json.load(sys.stdin):
        try:
            if os.path.isfile(p) and os.path.getsize(p) <= LIMIT:
                out[p] = digest(p, algorithm)
        except OSError:
            pass
    print(json.dumps(out))
else:
    sys.stderr.write("použití: plugin.py columns <md5|sha1|sha256>\n"); sys.exit(2)
