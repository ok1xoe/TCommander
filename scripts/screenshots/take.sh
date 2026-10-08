#!/bin/bash
# Pořídí snímky obrazovky pro App Store (a web) z demonstračních dat (scripts/screenshots/make_demo_data.py), vždy v angličtině.
# Výsledek: appstore/screenshots/*.png (2880×1800 = formát App Store pro Mac) a docs/web/img/screenshot-*.jpg (zmenšené pro web).
# Aplikace se spouští jako balíček přes `open -n`, aby byla aktivní (barevná tlačítka okna); potřebuje dist/TCommander.app (scripts/bundle.sh).
set -euo pipefail
cd "$(dirname "$0")/../.."
APP="${APP:-dist/TCommander.app}"
D="${DEMO:-/Users/Shared/Demo}"
OUT="appstore/screenshots"; WEB="docs/web/img"
mkdir -p "$OUT" "$WEB"
python3 scripts/screenshots/make_demo_data.py "$D" >/dev/null

# jazyk rozhraní: angličtina (nastavení uživatele se na dobu snímání dočasně zálohuje a pak vrátí)
SETTINGS="$HOME/Library/Application Support/TCommander/settings.json"
BACKUP="$(mktemp)"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$BACKUP" || : > "$BACKUP"
restore() { if [ -s "$BACKUP" ]; then cp "$BACKUP" "$SETTINGS"; else rm -f "$SETTINGS"; fi; }
trap restore EXIT
python3 - "$SETTINGS" <<'PY'
import json, sys, os
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) and os.path.getsize(p) else {}
d["language"] = "en"
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
PY

# pomocný nástroj: vypíše id oken procesu TCommander (nejvyšší první)
HELPER="$(mktemp -d)/winid"
cat > "$HELPER.swift" <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == "TCommander" {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print(w[kCGWindowNumber as String] as? Int ?? 0, Int(b["Width"] as? Double ?? 0), Int(b["Height"] as? Double ?? 0))
}
SWIFT
swiftc -O -o "$HELPER" "$HELPER.swift"

shot() {   # shot <název> <čekání s> <argumenty aplikace…>
  local name="$1" wait="$2"; shift 2
  pkill -x TCommander 2>/dev/null || true; sleep 1.5
  open -n "$APP" --args --screenshot "$@"
  sleep "$wait"
  local id; id="$("$HELPER" | awk '$2==1440 && $3==900 {print $1; exit}')"
  [ -n "$id" ] || { echo "okno 1440×900 pro $name nenalezeno" >&2; pkill -x TCommander || true; return 1; }
  screencapture -x -o -l "$id" "$OUT/$name.png"
  sips -s format jpeg -s formatOptions 80 -Z 1600 "$OUT/$name.png" --out "$WEB/screenshot-$name.jpg" >/dev/null
  pkill -x TCommander || true
  echo "$name: $(sips -g pixelWidth -g pixelHeight "$OUT/$name.png" | tail -2 | awk '{print $2}' | tr '\n' 'x')"
}

SIZE=(--window-size 1440x900)
shot 01-two-panels 10 --panel-left "$D/Projects/website:$D/Projects/api:$D/Documents" --panel-right "$D/Photos/Summer" --mode-right thumbnails --mark "*.js;*.html;*.css" "${SIZE[@]}"
shot 02-syntax-highlighting 9 --lister "$D/Projects/mobile-app/Sources/main.swift" "${SIZE[@]}"
shot 03-markdown-reader 10 --lister "$D/Projects/website/README.md" "${SIZE[@]}"
shot 04-compare-files 9 --compare "$D/Projects/website/style.css" "$D/Backup/website/style.css" "${SIZE[@]}"
shot 05-synchronize 9 --sync "$D/Projects/website" "$D/Backup/website" "${SIZE[@]}"
shot 06-find-files 11 --panel-left "$D/Projects" --search-run "*" "Espresso" "${SIZE[@]}"
shot 07-multi-rename 11 --panel-left "$D/Photos/Summer" --mark "*.png" --multirename "Summer-[C]" 2 "${SIZE[@]}"
shot 08-terminal 11 --terminal-cmd "vim -n -u NONE -c 'syntax on' server.py" --terminal-dir "$D/Projects/api" "${SIZE[@]}"
if [ "${DIAGRAM:-0}" = "1" ]; then (OUT="$(mktemp -d)"; shot 09-plantuml-diagram 22 --lister "$D/Documents/diagram.puml" "${SIZE[@]}"); fi
echo "Hotovo: $OUT, $WEB"
