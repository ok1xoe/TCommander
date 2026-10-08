# Vydání v Mac App Store

Tento dokument popisuje, co je pro App Store připravené a **co musíte udělat vy** (účet Apple, App Store Connect, podpisové profily). Kód, sestavení, ikona, texty a snímky jsou hotové.

## Co je hotové

| Oblast | Stav | Kde |
|---|---|---|
| App Sandbox | aplikace v něm plně funguje (povolení složek přes dialog, bookmarky) | `Sources/TCCore/Sandbox.swift`, `Sources/TCApp/AccessPrompt.swift` |
| Entitlements | sandbox, síťový klient, uživatelem vybrané soubory, bookmarky | `appstore/TCommander.entitlements` |
| Funkce, které sandbox nedovolí | SFTP, pluginy a PlantUML se v edici z App Store vypínají samy | `Sandbox.isSandboxed` |
| Ikona | `AppIcon.icns` (generuje `scripts/make_icon.swift`) | `appstore/` |
| `Info.plist` | kategorie, šifrování (`ITSAppUsesNonExemptEncryption = NO`), lokalizace en/cs, verze | `appstore/Info.plist.in` |
| Privacy manifest | žádná sbíraná data, deklarované „required reason“ API | `appstore/PrivacyInfo.xcprivacy` |
| Sestavení balíčku | univerzální binárka, podpis, `.pkg` | `scripts/appstore.sh` |
| Texty obchodu | angličtina a čeština, kontrola limitů testem | `appstore/metadata/` |
| Snímky obrazovky | 5 snímků 2880×1800 | `appstore/screenshots/` |
| Zásady ochrany soukromí | web a v aplikaci | [docs/manual/en/privacy.md](manual/en/privacy.md) |
| Uživatelská příručka | v aplikaci (Nápověda) i na webu | `docs/manual/`, `scripts/build_site.sh` |

## Co musíte udělat vy

### 1. Certifikáty a profil (developer.apple.com › Certificates, Identifiers & Profiles)

- Certifikáty **Apple Distribution** a **3rd Party Mac Developer Installer** (instalační) už v Klíčence máte.
- **Identifiers › App IDs › +**: *App*, popis „TCommander“, **Bundle ID (explicit) `cz.ok1xoe.TCommander`**. Capabilities nejsou potřeba (sandbox se zapíná v entitlements).
- **Profiles › +**: typ **Mac App Store Connect** (distribuce), vyberte App ID `cz.ok1xoe.TCommander` a certifikát Apple Distribution. Stáhněte `.provisionprofile` a uložte ho někam bokem (neukládejte do repozitáře).

### 2. App Store Connect (appstoreconnect.apple.com › Apps › +)

1. **Nová aplikace**: platforma macOS, název **TCommander** (viz „Název a ochranná známka“ níže), primární jazyk English (U.S.), Bundle ID `cz.ok1xoe.TCommander`, SKU libovolné (např. `tcommander`).
2. **Cena a dostupnost**: například cena 1,99 USD. Zvažte *App Store Small Business Program* (provize 15 % místo 30 %).
3. **Soukromí aplikace**: *Data Not Collected* (nic nesbíráme). **URL zásad ochrany soukromí**: `https://ok1xoe.github.io/TCommander/docs/en/privacy.html` (po zapnutí GitHub Pages; česky `…/docs/cs/privacy.html`).
4. **Kategorie**: primární *Utilities*, sekundární *Productivity*.
5. **Věkové hodnocení**: u všech otázek „žádný / ne“ (aplikace nemá obsah, který by hodnocení zvyšoval); vyjde 4+.
6. **Šifrování (export compliance)**: klíč `ITSAppUsesNonExemptEncryption = NO` je v `Info.plist`; aplikace používá jen šifrování z operačního systému (TLS, hashování). Při dotazu odpovězte, že použité šifrování je osvobozené.
7. **Informace pro verzi**: texty zkopírujte ze složky `appstore/metadata/en-US` a `appstore/metadata/cs` (pole *Name*, *Subtitle*, *Promotional Text*, *Description*, *Keywords*, *What’s New*), URL podpory `https://github.com/ok1xoe/TCommander/issues`, URL marketingu `https://ok1xoe.github.io/TCommander/`.
8. **Snímky**: nahrajte soubory z `appstore/screenshots/` (viz „Snímky obrazovky“).
9. **Informace pro App Review**: přihlášení není potřeba. Poznámka pro recenzenta:

> TCommander is a file manager. Because of the App Sandbox it asks once, at first launch, for a folder it may use (please choose your home folder in the dialog). It remembers the choice using security-scoped bookmarks. You can also drop a folder on the app icon. All features are available without sign-in. Network features (FTP/FTPS/SMB/WebDAV) work with any server you enter; no server is needed to review the app. SFTP, plugins and PlantUML rendering are intentionally disabled in this edition because they require running other programs.

### 3. Sestavení a nahrání

```bash
PROVISIONING_PROFILE=~/cesta/TCommander_MAS.provisionprofile BUILD_NUMBER=1 scripts/appstore.sh
```

Skript sám najde identity v Klíčence, sestaví univerzální aplikaci, vloží ikonu, privacy manifest a příručku, podepíše ji s entitlements, ověří, že je zapnutý sandbox, a vytvoří `dist-appstore/TCommander-1.0.0.pkg`. `DRY_RUN=1 scripts/appstore.sh` vyzkouší sestavení bez identit.

Balíček nahrajte aplikací **Transporter** (zdarma v Mac App Store): přetáhněte do ní `.pkg` a klepněte na *Deliver*. (Alternativa: `UPLOAD=1` s klíčem App Store Connect API a nainstalovaným Xcode.) Po zpracování vyberte sestavení u verze v App Store Connect a odešlete k recenzi. Při každém dalším nahrání zvyšte `BUILD_NUMBER`.

### 4. Po schválení

Do repozitáře (*Settings › Secrets and variables › Actions › Variables*) přidejte proměnnou **`APPSTORE_URL`** s adresou aplikace v obchodě; web se přegeneruje a tlačítko „Mac App Store (coming soon)“ se změní na odkaz.

## Snímky obrazovky

App Store přijímá pro macOS rozlišení 1280×800, 1440×900, 2560×1600 a 2880×1800 (16:10); nahrajte 1 až 10 snímků. Hotové jsou v `appstore/screenshots/`, ve výchozím pořadí:

1. `01-two-panels.png`: dva panely, záložky a náhledy
2. `02-syntax-highlighting.png`: Lister se zvýrazněním syntaxe
3. `03-markdown-reader.png`: čtečka Markdownu
4. `04-compare-files.png`: porovnání souborů
5. `05-terminal.png`: terminál s vimem

Snímky vznikají skriptem `scripts/screenshots/take.sh` z demonstračních dat (`make_demo_data.py`); obsahují jen vymyšlené soubory. Snímek s diagramem PlantUML (jen pro web) edice z App Store nepoužívá, protože diagramy nekreslí.

## Název a ochranná známka

**Důležité:** „Commander“ a zkratka „TC“ jsou úzce spojené s **Total Commanderem** (Ghisler Software), který je ochrannou známkou. App Review může název odmítnout (pravidlo 5.2 – práva třetích stran), nebo se může ozvat držitel známky. Před odesláním doporučuji:

- vyhledat „Total Commander“ a „TCommander“ v databázích známek (EUIPO, USPTO, Úřad průmyslového vlastnictví, třída 9 – software);
- zvážit zcela odlišný název (viz původní návrhy: Panefold, Twinpanes, Twinfiles…), případně **App Store jméno odlišné** od názvu na GitHubu;
- aplikace i web už teď uvádějí, že jde o nezávislý projekt bez vazby na Total Commander.

Název v App Store Connect jde změnit do odeslání; v kódu je třeba přepsat `CFBundleName`/`CFBundleDisplayName` v `appstore/Info.plist.in` a texty.

## Co může recenzi zkomplikovat

- **Přístup k souborům.** Aplikace vysvětluje, proč žádá o složku, a při zamítnutí se nepřestane ptát znovu v rychlém sledu. Poznámka pro recenzenta to popisuje.
- **Terminál.** Vestavěný terminál spouští přihlašovací shell; v sandboxu dosáhne jen na povolené složky. Pokud by App Review chtěl terminál odebrat, stačí ho skrýt pod `Sandbox.isSandboxed`.
- **Spouštění cizího kódu** (pluginy, PlantUML) je v edici z App Store vypnuté, aby se neporušilo pravidlo 2.5.2.
- **Aktualizace** posílá jen App Store; aplikace sama nic nestahuje.

## Kontrola před odesláním

- [ ] `scripts/appstore.sh` doběhl bez varování a vytvořil `.pkg`
- [ ] Transporter balíček přijal (žádné chyby validace)
- [ ] V App Store Connect jsou texty, snímky, soukromí, cena, věkové hodnocení
- [ ] Název „TCommander“ je právně zkontrolovaný
- [ ] Web běží na GitHub Pages a odkazy na zásady soukromí a podporu fungují
