#!/bin/bash
# Vygeneruje web a příručku (docs/manual + docs/web → site/): úvodní stránky, příručka v angličtině a češtině, vyhledávání, mapa webu.
#   VERSION=1.0.0 APPSTORE_URL=https://apps.apple.com/… SITE_URL=https://ok1xoe.github.io/TCommander CUSTOM_DOMAIN=tcommander.example.com scripts/build_site.sh
# Výsledek: site/ (nasazuje ho workflow Pages) a site/docs + site/assets (nápověda v aplikaci, viz menu Nápověda).
set -euo pipefail
cd "$(dirname "$0")/.."
args=(--version "${VERSION:-1.0.0}")
# adresa webu: SITE_URL, jinak https://$CUSTOM_DOMAIN, jinak GitHub Pages; CUSTOM_DOMAIN navíc vytvoří soubor CNAME
if [ -n "${CUSTOM_DOMAIN:-}" ]; then args+=(--custom-domain "$CUSTOM_DOMAIN"); [ -n "${SITE_URL:-}" ] || SITE_URL="https://$CUSTOM_DOMAIN"; fi
[ -n "${SITE_URL:-}" ] && args+=(--site-url "$SITE_URL")
[ -n "${APPSTORE_URL:-}" ] && args+=(--appstore-url "$APPSTORE_URL")
swift run -c release DocsBuilder "${args[@]}"
