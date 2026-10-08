#!/bin/bash
# Pořídí snímky obrazovky pro web a App Store z demonstračních dat (scripts/screenshots/make_demo_data.py).
# Výsledek: appstore/screenshots/*.png (2880×1800) a docs/web/img/screenshot-*.jpg (zmenšené pro web).
# Potřebuje sestavenou aplikaci (.build/debug/TCommander nebo APP=cesta), pomocný nástroj `winid` (viz níže) a povolené nahrávání obrazovky pro Terminál.
set -euo pipefail
cd "$(dirname "$0")/../.."
APP="${APP:-.build/debug/TCommander}"
D="${DEMO:-/Users/Shared/Demo}"
OUT="appstore/screenshots"; WEB="docs/web/img"
mkdir -p "$OUT" "$WEB"
python3 scripts/screenshots/make_demo_data.py "$D" >/dev/null

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
  pkill -x TCommander 2>/dev/null || true; sleep 1
  TC_SCREENSHOT=1 "$APP" "$@" >/dev/null 2>&1 &
  sleep "$wait"
  local id; id="$("$HELPER" | awk '$2==1440 && $3==900 {print $1; exit}')"
  [ -n "$id" ] || { echo "okno 1440×900 pro $name nenalezeno" >&2; pkill -x TCommander || true; return 1; }
  screencapture -x -o -l "$id" "$OUT/$name.png"
  sips -s format jpeg -s formatOptions 80 -Z 1600 "$OUT/$name.png" --out "$WEB/screenshot-$name.jpg" >/dev/null
  pkill -x TCommander || true; sleep 1
  echo "$name: $(sips -g pixelWidth -g pixelHeight "$OUT/$name.png" | tail -2 | awk '{print $2}' | tr '\n' 'x')"
}

shot 01-two-panels 9 --panel-left "$D/Projects/website:$D/Projects/api:$D/Documents" --panel-right "$D/Photos/Summer" --mode-right thumbnails --window-size 1440x900
shot 02-syntax-highlighting 8 --lister "$D/Projects/mobile-app/Sources/main.swift" --window-size 1440x900
shot 03-markdown-reader 9 --lister "$D/Projects/website/README.md" --window-size 1440x900
shot 04-compare-files 8 --compare "$D/Projects/website/style.css" "$D/Backup/website/style.css" --window-size 1440x900
shot 05-terminal 9 --terminal-cmd "vim -n -u NONE -c 'syntax on' server.py" --terminal-dir "$D/Projects/api" --window-size 1440x900
# diagram jen pro web (edice z GitHubu); do App Store se nehodí, proto se PNG ukládá mimo appstore/screenshots
if [ "${DIAGRAM:-1}" = "1" ]; then (OUT="$(mktemp -d)"; shot 06-plantuml-diagram 20 --lister "$D/Documents/diagram.puml" --window-size 1440x900); fi
echo "Hotovo: $OUT, $WEB"
