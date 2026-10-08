# Vydávání verzí

## Jak vydat verzi

```bash
git tag v0.2.0
git push origin v0.2.0
```

Tag spustí workflow `.github/workflows/release.yml`: spustí testy, sestaví univerzální aplikaci (arm64 + x86_64), podepíše ji, vytvoří `TCommander-<verze>.zip`, `TCommander-<verze>.dmg` a `SHA256SUMS.txt` a založí GitHub Release.
Průběžné sestavení a testy na každém pushi a pull requestu dělá `.github/workflows/ci.yml`.

Stejný balíček se dá sestavit lokálně: `VERSION=0.2.0 scripts/package.sh` (výstup v `dist/`).

## Podpis

Bez nastavení se aplikace podepíše **ad-hoc** (`codesign -s -`). Běží na každém Macu, ale protože není podepsaná certifikátem Apple Developer ID a notarizovaná, Gatekeeper ji po stažení z internetu zablokuje. Uživatel ji otevře pravým tlačítkem › Otevřít, nebo příkazem
`xattr -dr com.apple.quarantine /Applications/TCommander.app`.

Aby se aplikace instalovala bez upozornění, je potřeba placený účet Apple Developer Program a certifikát **Developer ID Application** (certifikát „Apple Development“ ani „Apple Distribution“ k tomu nestačí). Pak v nastavení repozitáře (Settings › Secrets and variables › Actions) vytvořte secrets:

| Secret | Obsah |
|---|---|
| `MACOS_CERTIFICATE` | certifikát Developer ID Application s privátním klíčem exportovaný z Klíčenky jako `.p12`, zakódovaný `base64 -i certifikat.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | heslo zadané při exportu `.p12` |
| `MACOS_SIGNING_IDENTITY` | např. `Developer ID Application: Jméno Příjmení (TEAMID)` |
| `NOTARY_APPLE_ID` | Apple ID |
| `NOTARY_PASSWORD` | heslo specifické pro aplikaci (appleid.apple.com › Přihlášení a zabezpečení) |
| `NOTARY_TEAM_ID` | Team ID (10 znaků) |

Pokud jsou nastavené, workflow podepíše aplikaci s hardened runtime, notarizuje ji (`notarytool`) a připne razítko (`stapler`).

## Web, příručka a App Store

- **Web a příručka** (`docs/manual`, `docs/web`, generátor `Sources/DocsBuilder`) se sestavují skriptem `scripts/build_site.sh` do složky `site/`. Workflow `.github/workflows/pages.yml` je při změně nasadí na GitHub Pages (`https://ok1xoe.github.io/TCommander/`); v nastavení repozitáře musí být *Pages › Source: GitHub Actions*. Stejná příručka se vkládá do aplikace (menu Nápověda); skripty `package.sh`, `appstore.sh` a `bundle.sh` ji sestaví automaticky.
- **Mac App Store**: viz [appstore.md](appstore.md) (`scripts/appstore.sh`, texty v `appstore/metadata`, snímky v `appstore/screenshots`).
- Verze se zadává proměnnou `VERSION` (výchozí 1.0.0); tag `v1.0.0` spustí workflow Release.
