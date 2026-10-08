# Verze z Mac App Store

Mac App Store vyžaduje, aby každá aplikace běžela v **App Sandboxu**, ochraně zabudované v macOS, která drží aplikaci mimo vaše soubory, dokud jí je nepovolíte. TCommander v něm funguje plně, s těmito rozdíly.

## Povolení přístupu k souborům

- Při prvním spuštění vás TCommander požádá o výběr složky. **Vyberte svou domovskou složku** (nebo jakoukoli jinou): TCommander pak může otevřít tu složku i vše v ní.
- Když později otevřete místo, které ještě není pokryté (např. jiný disk v `/Volumes` nebo složku mimo domov), objeví se stejný dialog pro ně. Můžete vybrat celý disk a povolit ho celý.
- Vaše volby se pamatují; znovu se neptá.
- Můžete také **přetáhnout složku na ikonu TCommanderu** v Docku nebo použít *Otevřít v ▸ TCommander* ve Finderu, čímž složku povolíte.
- Přetažení souborů z Finderu do panelu funguje bez jakéhokoli dotazu.

Dialog zobrazuje samotný macOS, takže TCommander nikdy nevidí nic mimo složky, které vyberete.

## Rozdíly oproti edici z GitHubu

| Funkce | Edice z App Store |
|---|---|
| SFTP | není (potřebuje systémový `ssh` s vašimi klíči) |
| Pluginy | nejsou (Apple nepovoluje aplikacím spouštět stažený kód) |
| Diagramy PlantUML | nejsou (potřebují Javu); zdroj se zobrazí jako text |
| FTP, FTPS, SMB, WebDAV | jsou |
| Terminál | je; shell dosáhne jen na složky, které jste povolili |
| Vše ostatní | stejné |

Obě edice používají stejný formát nastavení i stejnou příručku.

## Soukromí

TCommander nemá účty, žádnou analytiku ani sledování. Viz [Zásady ochrany soukromí](privacy.html).
