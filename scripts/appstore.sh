#!/bin/bash
# Mac App Store: sestaví univerzální aplikaci v App Sandboxu, podepíše ji a vytvoří instalační balíček .pkg pro nahrání do App Store Connect.
#
# Použití:  scripts/appstore.sh            (potřebuje podpisové identity a provisioning profil, viz docs/appstore.md)
#           DRY_RUN=1 scripts/appstore.sh  (zkušební sestavení s ad-hoc podpisem a nepodepsaným balíčkem, bez identit)
#
# Proměnné prostředí (všechny volitelné):
#   VERSION                verze aplikace (výchozí 1.0.0)           BUILD_NUMBER   číslo sestavení (výchozí 1; při každém nahrání větší)
#   APP_IDENTITY           např. "Apple Distribution: Jméno (TEAMID)" (výchozí: nalezne se v Klíčence)
#   INSTALLER_IDENTITY     např. "3rd Party Mac Developer Installer: Jméno (TEAMID)" (výchozí: nalezne se v Klíčence)
#   PROVISIONING_PROFILE   cesta k profilu „Mac App Store“ (.provisionprofile) pro cz.ok1xoe.TCommander (bez něj App Store balíček nepřijme)
#   TEAM_ID                10znakové Team ID (výchozí: odvodí se z identity)
#   ASC_KEY_ID, ASC_ISSUER_ID   klíč App Store Connect API (soubor ~/.private_keys/AuthKey_<ASC_KEY_ID>.p8); s UPLOAD=1 se balíček ověří a nahraje
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD_NUMBER:-1}"
DRY="${DRY_RUN:-0}"
OUT="dist-appstore"
APP="$OUT/TCommander.app"
PKG="$OUT/TCommander-$VERSION.pkg"

find_identity() { security find-identity -v -p "$1" 2>/dev/null | sed -n "s/.*\"\\($2[^\"]*\\)\".*/\\1/p" | head -1; }
if [ "$DRY" = "1" ]; then
  APP_IDENTITY="-"; INSTALLER_IDENTITY=""
else
  APP_IDENTITY="${APP_IDENTITY:-$(find_identity codesigning "Apple Distribution")}"
  INSTALLER_IDENTITY="${INSTALLER_IDENTITY:-$(find_identity basic "3rd Party Mac Developer Installer")}"
  [ -n "$APP_IDENTITY" ] || { echo "Chybí identita „Apple Distribution“ (nastavte APP_IDENTITY nebo ji nainstalujte do Klíčenky)." >&2; exit 1; }
  [ -n "$INSTALLER_IDENTITY" ] || { echo "Chybí identita „3rd Party Mac Developer Installer“ (nastavte INSTALLER_IDENTITY)." >&2; exit 1; }
fi
TEAM_ID="${TEAM_ID:-$(echo "$APP_IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p')}"
[ "$DRY" = "1" ] || [ -n "$TEAM_ID" ] || { echo "Nelze zjistit TEAM_ID; nastavte ho proměnnou TEAM_ID." >&2; exit 1; }

echo "==> Sestavení (arm64 + x86_64)"
BIN="$(scripts/build_universal.sh | tail -1)"

echo "==> Složení $APP"
rm -rf "$OUT"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TCommander"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" appstore/Info.plist.in > "$APP/Contents/Info.plist"
cp appstore/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp appstore/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
echo "==> Příručka (nápověda v aplikaci)"
VERSION="$VERSION" scripts/build_site.sh >&2
mkdir -p "$APP/Contents/Resources/Help"
cp -R site/docs site/assets "$APP/Contents/Resources/Help/"

echo "==> Entitlements"
ENT="$OUT/entitlements.plist"
cp appstore/TCommander.entitlements "$ENT"
if [ -n "$TEAM_ID" ]; then
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.cz.ok1xoe.TCommander" "$ENT"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$ENT"
fi
if [ -n "${PROVISIONING_PROFILE:-}" ]; then
  cp "$PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"
elif [ "$DRY" != "1" ]; then
  echo "VAROVÁNÍ: PROVISIONING_PROFILE není nastaven; balíček bude podepsaný, ale App Store ho bez profilu nepřijme." >&2
fi

echo "==> Podpis (${APP_IDENTITY/#-/ad-hoc})"
if [ "$APP_IDENTITY" = "-" ]; then codesign --force --sign - --entitlements "$ENT" "$APP"
else codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" --entitlements "$ENT" "$APP"; fi
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "com.apple.security.app-sandbox" || { echo "CHYBA: aplikace nemá zapnutý App Sandbox." >&2; exit 1; }

echo "==> Balíček $PKG"
if [ -n "$INSTALLER_IDENTITY" ]; then productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$PKG"
else productbuild --component "$APP" /Applications "$PKG"; echo "(nepodepsaný balíček – jen zkušební)"; fi
pkgutil --check-signature "$PKG" 2>&1 | head -3 || true
(cd "$OUT" && shasum -a 256 "TCommander-$VERSION.pkg" > SHA256SUMS.txt)

if [ "${UPLOAD:-0}" = "1" ]; then
  [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ] || { echo "Pro UPLOAD=1 nastavte ASC_KEY_ID a ASC_ISSUER_ID." >&2; exit 1; }
  xcrun altool --validate-app -f "$PKG" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  xcrun altool --upload-app -f "$PKG" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
else
  echo "Nahrání: aplikace Transporter (Mac App Store) – přetáhněte $PKG, nebo spusťte s UPLOAD=1 (potřebuje Xcode a klíč App Store Connect API)."
fi
echo "Hotovo: $APP, $PKG"
