import sys, json
if sys.argv[1] == "columns":
    paths = json.load(sys.stdin)
    out = {}
    for p in paths:
        try:
            t = open(p, encoding="utf-8").read()
            out[p] = str(len(t.split())) if sys.argv[2] == "words" else str(len(t))
        except Exception:
            pass
    print(json.dumps(out))
