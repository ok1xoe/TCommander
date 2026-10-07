#!/usr/bin/env python3
"""Prohlížeč strukturovaných souborů: JSON (i na jeden řádek) a plist (XML i binární) jako odsazený text.

Volání: plugin.py view <soubor>   →   JSON {"kind": "text", "content": "..."}
Při nevalidním obsahu skončí chybou, takže Lister zobrazí soubor jako běžný text.
"""
import sys, os, json, plistlib, base64, datetime

LIMIT = 8 * 1024 * 1024


def plain(value):
    """Převede hodnoty plistu na typy, které umí JSON (datum → ISO, data → base64 s délkou)."""
    if isinstance(value, dict):
        return {str(k): plain(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [plain(v) for v in value]
    if isinstance(value, (datetime.datetime, datetime.date)):
        return value.isoformat()
    if isinstance(value, (bytes, bytearray)):
        head = base64.b64encode(bytes(value[:48])).decode()
        return "<data %d B: %s%s>" % (len(value), head, "…" if len(value) > 48 else "")
    return value


def main():
    if len(sys.argv) < 3 or sys.argv[1] != "view":
        sys.stderr.write("použití: plugin.py view <soubor>\n"); sys.exit(2)
    path = sys.argv[2]
    if os.path.getsize(path) > LIMIT:
        sys.stderr.write("soubor je příliš velký\n"); sys.exit(1)
    data = open(path, "rb").read()
    ext = os.path.splitext(path)[1].lower()
    if ext == ".json":
        value = json.loads(data.decode("utf-8-sig"))
        kind = "JSON"
    else:
        value = plain(plistlib.loads(data))
        kind = "plist (binární)" if data.startswith(b"bplist") else "plist (XML)"
    text = json.dumps(value, indent=2, ensure_ascii=False, sort_keys=False)
    print(json.dumps({"kind": "text", "content": "// %s\n%s\n" % (kind, text)}))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, plistlib.InvalidFileException, OSError) as e:
        sys.stderr.write("%s\n" % e); sys.exit(1)
