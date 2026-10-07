#!/usr/bin/env python3
"""Sečte tokeny z přepisů Claude Code (~/.claude/projects/<projekt>/*.jsonl) včetně subagentů.

Použití:
  scripts/token_usage.py                      # celé sezení/sezení projektu
  scripts/token_usage.py --since 2026-10-07T09:44:00Z --until 2026-10-07T12:00:00Z
Odpovědi se dedupují podle message.id (jedna odpověď je v přepisu uložena po blocích).
"""
import argparse, glob, json, os, sys
from collections import defaultdict

FIELDS = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]

def project_dir(cwd):
    return os.path.expanduser("~/.claude/projects/" + cwd.replace("/", "-").replace(".", "-"))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since"); ap.add_argument("--until"); ap.add_argument("--dir")
    a = ap.parse_args()
    d = a.dir or project_dir(os.getcwd())
    files = glob.glob(os.path.join(d, "**", "*.jsonl"), recursive=True)
    if not files:
        sys.exit(f"Žádné přepisy v {d}")
    msgs = {}  # message id -> (timestamp, usage maxima)
    for f in files:
        for line in open(f, errors="ignore"):
            try: r = json.loads(line)
            except ValueError: continue
            m = r.get("message") or {}
            u = m.get("usage")
            if not u or not m.get("id"): continue
            ts = r.get("timestamp", "")
            cur = msgs.setdefault(m["id"], [ts, defaultdict(int)])
            cur[0] = min(cur[0], ts) if cur[0] else ts
            for k in FIELDS: cur[1][k] = max(cur[1][k], u.get(k) or 0)
    tot = defaultdict(int); n = 0
    for ts, u in msgs.values():
        if a.since and ts < a.since: continue
        if a.until and ts >= a.until: continue
        n += 1
        for k in FIELDS: tot[k] += u[k]
    print(f"odpovědí (API volání): {n}")
    print(f"input (necachované):     {tot['input_tokens']:>14,}")
    print(f"cache zápis:             {tot['cache_creation_input_tokens']:>14,}")
    print(f"cache čtení:             {tot['cache_read_input_tokens']:>14,}")
    print(f"output:                  {tot['output_tokens']:>14,}")
    print(f"CELKEM (součet všech):   {sum(tot.values()):>14,}")

main()
