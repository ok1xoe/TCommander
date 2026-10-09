# Verze z Mac App Store

Mac App Store vyžaduje, aby každá aplikace běžela v **App Sandboxu**, ochraně zabudované v macOS, která drží aplikaci mimo vaše soubory, dokud jí je nepovolíte. TCommander v něm funguje plně, s těmito rozdíly.

## Povolení přístupu k souborům

- Při prvním spuštění vás TCommander požádá o výběr složky. **Vyberte svou domovskou složku** (nebo jakoukoli jinou): TCommander pak může otevřít tu složku i vše v ní.
- Když později otevřete místo, které ještě není pokryté (např. jiný disk v `/Volumes` nebo složku mimo domov), objeví se stejný dialog pro ně. Můžete vybrat celý disk a povolit ho celý.
- Vaše volby se pamatují; znovu se neptá.
- Můžete také **přetáhnout složku na ikonu TCommanderu** v Docku nebo použít *Otevřít v ▸ TCommander* ve Finderu, čímž složku povolíte.
- Přetažení souborů z Finderu do panelu funguje bez jakéhokoli dotazu.

Dialog zobrazuje samotný macOS, takže TCommander nikdy nevidí nic mimo složky, které vyberete.

## Kterou edici zvolit?

TCommander je **jedna aplikace ve dvou edicích**, které sdílejí stejný kód, stejný vzhled i stejnou příručku. Liší se jen tam, kde pravidla Applu pro Mac App Store nějakou funkci nepovolují.

- **Edice z GitHubu**: bezplatné stažení s plným přístupem k disku. Zvolte ji, pokud potřebujete SFTP, pluginy nebo diagramy PlantUML, nebo si aplikace raději instalujete sami.
- **Edice z Mac App Store**: instaluje a aktualizuje ji automaticky App Store. Zvolte ji, pokud chcete nejjednodušší instalaci a tři funkce níže nepotřebujete.

## Rozdíly mezi edicemi

| Funkce | Edice z GitHubu | Edice z Mac App Store | Proč |
|---|---|---|---|
| Správce souborů, prohlížeč, editor, hledání, porovnání, synchronizace, archivy | ✓ | ✓ | |
| FTP, FTPS, SMB, WebDAV | ✓ | ✓ | |
| Vestavěný terminál | ✓ | ✓ | V edici z App Store dosáhne shell jen na složky, které jste povolili. |
| SFTP | ✓ | ✗ | Potřebuje systémový `ssh` a vaše klíče, které sandbox blokuje. |
| Pluginy | ✓ | ✗ | Apple nepovoluje aplikacím spouštět stažený kód. |
| Diagramy PlantUML | ✓ | ✗ | Potřebují Javu a externí program. Zdroj diagramu se dál zobrazí jako text. |
| Přístup k souborům | celý disk (macOS se zeptá jednou u každé chráněné složky, např. Dokumenty) | jen složky, které jednou vyberete | App Sandbox je u každé aplikace v obchodě povinný. |
| Aktualizace | stáhnete novou verzi | automaticky přes App Store | |

✓ znamená, že funkce je k dispozici, ✗ že v dané edici není.

**Nastavení se mezi edicemi nesdílí.** Obě používají stejný formát souborů, ale každá je ukládá na jiné místo (edice z GitHubu do `~/Library/Application Support/TCommander/`, edice z App Store do své sandboxové složky). Při přechodu mezi edicemi můžete nastavení, zkratky a oblíbené zkopírovat nebo exportovat a importovat.

## Soukromí

TCommander nemá účty, žádnou analytiku ani sledování. Viz [Zásady ochrany soukromí](privacy.html).
