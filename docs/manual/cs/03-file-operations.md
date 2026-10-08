# Kopírování, přesouvání a mazání

## Kopírování a přesun

Označte soubory (nebo nechte kurzor na jednom) a stiskněte **F5** pro kopírování nebo **F6** pro přesun. Cílem je složka ve druhém panelu; v dialogu ji můžete upravit.

- Operace běží ve **frontě** zobrazené dole. Klepnutím na úlohu vidíte podrobnosti, můžete ji pozastavit nebo zrušit. Ve frontě může čekat víc úloh.
- Na APFS jsou kopie v rámci jednoho svazku okamžité (používají klonování souborů) a nezabírají místo, dokud se soubor nezmění.
- **Ověřovat kopie (SHA-256)** v Nastavení porovná každý zkopírovaný soubor se zdrojem.
- Přerušené kopírování lze na FTP serverech navázat.
- Kopírování a přesun fungují i z archivů a serverů a do nich (viz [Archivy](07-archives.html) a [Síť](08-network.html)).

### Když soubor už existuje

| Volba | Význam |
|---|---|
| Přepsat | nahradí cílový soubor |
| Přepsat starší | nahradí, jen pokud je zdroj novější |
| Přeskočit | cíl nechá být |
| Ponechat obě | nový soubor dostane číslovaný název |
| … vše | použije stejnou volbu pro zbytek úlohy |

## Mazání

**F8** přesune označené soubory do **Koše**. **Shift+F8** je po potvrzení smaže trvale. Pokud v Nastavení vypnete „Mazat do koše“, F8 maže trvale.

## Vytváření a přejmenování

- **F7** vytvoří složku (napsáním `a/b/c` vytvoříte vnořené složky), **Shift+F4** vytvoří textový soubor.
- **F2** přejmenuje na místě, **Shift+F6** otevře dialog přejmenování. Pro mnoho souborů najednou slouží [Hromadné přejmenování](06-compare-sync-rename.html#hromadne-prejmenovani).
- **Alt+Return** otevře **Vlastnosti**: velikost, data, oprávnění (zadejte je osmičkově, volitelně pro vše uvnitř složky), příznaky souboru a vlastníka se skupinou (jejich změna vyžaduje práva správce a není dostupná).

## Odkazy

*Nástroje ▸ Symbolický odkaz / Pevný odkaz do druhého panelu* vytvoří odkaz na soubor pod kurzorem ve složce druhého panelu.

## Kontrolní součty, dělení, kódování

- **Kontrolní součty…** spočítají MD5, SHA-1 nebo SHA-256 označených souborů a zapíšou soubor se součty; *Ověřit kontrolní součty ze souboru* je později zkontroluje.
- **Rozdělit soubor / Spojit soubory** rozřežou velký soubor na části (`.001`, `.002`, …) a zase je spojí.
- **Kódovat / Dekódovat soubory** převádí do a z MIME (Base64), UUE a XXE.
- **Najít duplicitní soubory** hledá shodné soubory podle velikosti a obsahu a umožní vybrat nadbytečné kopie.
