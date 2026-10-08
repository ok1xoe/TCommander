#!/bin/bash
# Složí dist/TCommander.app z release buildu (bez Xcode; ad-hoc podpis).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | grep -v "ld: warning" || true
BIN="$(swift build -c release --show-bin-path 2>/dev/null)/TCommander"
APP="dist/TCommander.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TCommander"
mkdir -p "$APP/Contents/Resources/PluginExamples"
cp -R docs/plugin-examples/. "$APP/Contents/Resources/PluginExamples/"
find "$APP/Contents/Resources/PluginExamples" -name __pycache__ -type d -prune -exec rm -r {} +
sed -e "s/@VERSION@/1.0.0/" -e "s/@BUILD@/1/" appstore/Info.plist.in > "$APP/Contents/Info.plist"
cp appstore/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
echo "==> Příručka (nápověda v aplikaci)"
scripts/build_site.sh >/dev/null 2>&1 || true
mkdir -p "$APP/Contents/Resources/Help"
cp -R site/docs site/assets "$APP/Contents/Resources/Help/"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Hotovo: $APP"
