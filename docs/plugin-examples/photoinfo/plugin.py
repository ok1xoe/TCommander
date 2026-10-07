#!/usr/bin/env python3
"""Sloupce s údaji o fotografiích; čte je systémový nástroj `sips` (nic se neinstaluje).

Volání: plugin.py columns <camera|taken|dpi>; vstup JSON pole cest, výstup JSON {"cesta": "hodnota"}.
"""
import sys, json, subprocess, re

KEYS = ["make", "model", "creation", "dpiWidth"]


def read(path):
    args = ["/usr/bin/sips"] + [a for k in KEYS for a in ("-g", k)] + [path]
    r = subprocess.run(args, capture_output=True, text=True, timeout=15)
    info = {}
    for line in r.stdout.splitlines()[1:]:
        key, _, value = line.strip().partition(": ")
        if value and value != "<nil>": info[key] = value
    return info


def camera(info):
    make, model = info.get("make", ""), info.get("model", "")
    return model if make and model.lower().startswith(make.lower().split()[0]) else (make + " " + model).strip()


def taken(info):
    m = re.match(r"(\d{4}):(\d{2}):(\d{2}) (\d{2}:\d{2})", info.get("creation", ""))
    return "%s-%s-%s %s" % m.groups() if m else ""


def dpi(info):
    try: return str(round(float(info.get("dpiWidth", ""))))
    except ValueError: return ""


if __name__ == "__main__" and len(sys.argv) >= 3 and sys.argv[1] == "columns":
    pick = {"camera": camera, "taken": taken, "dpi": dpi}.get(sys.argv[2])
    if not pick: sys.exit(2)
    out = {}
    for p in json.load(sys.stdin):
        try:
            value = pick(read(p))
            if value: out[p] = value
        except Exception:
            pass
    print(json.dumps(out))
else:
    sys.stderr.write("použití: plugin.py columns <camera|taken|dpi>\n"); sys.exit(2)
