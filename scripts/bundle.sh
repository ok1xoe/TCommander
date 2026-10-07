#!/bin/bash
# Složí dist/TCommander.app z release buildu (bez Xcode; ad-hoc podpis).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | grep -v "ld: warning" || true
BIN="$(swift build -c release --show-bin-path 2>/dev/null)/TCommander"
APP="dist/TCommander.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TCommander"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>TCommander</string>
  <key>CFBundleDisplayName</key><string>TCommander</string>
  <key>CFBundleIdentifier</key><string>cz.ok1xoe.TCommander</string>
  <key>CFBundleExecutable</key><string>TCommander</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Hotovo: $APP"
