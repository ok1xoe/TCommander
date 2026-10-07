#!/bin/bash
# Release balíček: univerzální macTC.app (arm64 + x86_64), podpis, volitelná notarizace, zip, dmg a kontrolní součty v dist/.
#
# Proměnné prostředí (všechny volitelné):
#   VERSION             verze aplikace (výchozí 0.1.0)
#   BUILD_NUMBER        číslo sestavení (výchozí 1)
#   CODESIGN_IDENTITY   název podpisové identity (např. "Developer ID Application: Jméno (TEAMID)");
#                       výchozí „-“ = ad-hoc podpis (aplikace běží, ale Gatekeeper po stažení z internetu zobrazí upozornění)
#   NOTARY_APPLE_ID, NOTARY_PASSWORD, NOTARY_TEAM_ID
#                       přihlašovací údaje pro notarizaci (heslo specifické pro aplikaci); použijí se jen s reálnou identitou
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD_NUMBER:-1}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="dist/macTC.app"
ZIP="dist/macTC-$VERSION.zip"
DMG="dist/macTC-$VERSION.dmg"

echo "==> Sestavení (release, arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/macTC"
lipo -info "$BIN"

echo "==> Složení $APP"
rm -rf dist; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/macTC"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>macTC</string>
  <key>CFBundleDisplayName</key><string>macTC</string>
  <key>CFBundleIdentifier</key><string>cz.ok1xoe.macTC</string>
  <key>CFBundleExecutable</key><string>macTC</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>macTC – správce souborů se dvěma panely</string>
</dict></plist>
PLIST

sign() {
  if [ "$IDENTITY" = "-" ]; then codesign --force --sign - "$@"
  else codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"; fi
}

echo "==> Podpis (${IDENTITY/#-/ad-hoc})"
sign "$APP"
codesign --verify --strict --verbose=2 "$APP"

if [ "$IDENTITY" != "-" ] && [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ]; then
  echo "==> Notarizace"
  ditto -c -k --keepParent "$APP" dist/notarize.zip
  xcrun notarytool submit dist/notarize.zip --apple-id "$NOTARY_APPLE_ID" --password "$NOTARY_PASSWORD" --team-id "$NOTARY_TEAM_ID" --wait
  xcrun stapler staple "$APP"
  rm -f dist/notarize.zip
else
  echo "==> Notarizace přeskočena (bez Developer ID identity a údajů NOTARY_*)"
fi

echo "==> Balíčky"
ditto -c -k --keepParent "$APP" "$ZIP"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "macTC $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
if [ "$IDENTITY" != "-" ]; then sign "$DMG"; fi
(cd dist && shasum -a 256 "macTC-$VERSION.zip" "macTC-$VERSION.dmg" > SHA256SUMS.txt && cat SHA256SUMS.txt)
echo "Hotovo: $APP, $ZIP, $DMG"
