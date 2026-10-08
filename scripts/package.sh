#!/bin/bash
# Release balíček: univerzální TCommander.app (arm64 + x86_64), podpis, volitelná notarizace, zip, dmg a kontrolní součty v dist/.
#
# Proměnné prostředí (všechny volitelné):
#   VERSION             verze aplikace (výchozí 1.0.0)
#   BUILD_NUMBER        číslo sestavení (výchozí 1)
#   CODESIGN_IDENTITY   název podpisové identity (např. "Developer ID Application: Jméno (TEAMID)");
#                       výchozí „-“ = ad-hoc podpis (aplikace běží, ale Gatekeeper po stažení z internetu zobrazí upozornění)
#   NOTARY_APPLE_ID, NOTARY_PASSWORD, NOTARY_TEAM_ID
#                       přihlašovací údaje pro notarizaci (heslo specifické pro aplikaci); použijí se jen s reálnou identitou
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD_NUMBER:-1}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="dist/TCommander.app"
ZIP="dist/TCommander-$VERSION.zip"
DMG="dist/TCommander-$VERSION.dmg"

echo "==> Sestavení (release, arm64 + x86_64)"
BIN="$(scripts/build_universal.sh | tail -1)"

echo "==> Složení $APP"
rm -rf dist; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TCommander"
mkdir -p "$APP/Contents/Resources/PluginExamples"
cp -R docs/plugin-examples/. "$APP/Contents/Resources/PluginExamples/"
find "$APP/Contents/Resources/PluginExamples" -name __pycache__ -type d -prune -exec rm -r {} +
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" appstore/Info.plist.in > "$APP/Contents/Info.plist"
cp appstore/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
echo "==> Příručka (nápověda v aplikaci)"
VERSION="$VERSION" scripts/build_site.sh >&2
mkdir -p "$APP/Contents/Resources/Help"
cp -R site/docs site/assets "$APP/Contents/Resources/Help/"

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
hdiutil create -volname "TCommander $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
if [ "$IDENTITY" != "-" ]; then sign "$DMG"; fi
(cd dist && shasum -a 256 "TCommander-$VERSION.zip" "TCommander-$VERSION.dmg" > SHA256SUMS.txt && cat SHA256SUMS.txt)
echo "Hotovo: $APP, $ZIP, $DMG"
