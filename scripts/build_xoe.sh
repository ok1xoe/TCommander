#!/bin/bash
# Vygeneruje příručku a obrázky pro web OK1XOE.dev (repozitář xoe-web): <xoe-web>/tcommander/manual, assets a img.
# Produktová stránka, Support a Privacy jsou psané ručně přímo v xoe-web (tcommander/index.html, support/, privacy/, page.css),
# aby odpovídaly ostatním aplikacím (RYRY, Antenna Rotator Controller).
#   scripts/build_xoe.sh ~/EngetoAcademy/xoe-web
set -euo pipefail
cd "$(dirname "$0")/.."
dest="${1:?Použití: scripts/build_xoe.sh <cesta k xoe-web>}/tcommander"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
swift run -c release DocsBuilder --version "${VERSION:-1.0.0}" --site-url https://ok1xoe.dev/tcommander --docs-dir manual --home-url /tcommander/ --guide-only 1 --out "$tmp"
mkdir -p "$dest"
rsync -a --delete "$tmp/manual/" "$dest/manual/"
rsync -a --delete --exclude "screenshot-*" "$tmp/assets/" "$dest/assets/"
mkdir -p "$dest/img"
rsync -a docs/web/img/ "$dest/img/"
echo "Hotovo: $dest"
