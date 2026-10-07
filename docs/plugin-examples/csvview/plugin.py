import sys, json, csv
if sys.argv[1] == "view":
    rows = list(csv.reader(open(sys.argv[2], encoding="utf-8")))
    html = "<table>" + "".join("<tr>" + "".join("<td>%s</td>" % c for c in r) + "</tr>" for r in rows) + "</table>"
    print(json.dumps({"kind": "html", "content": html}))
