# Prohlížeč a editor

## Lister (F3)

**F3** otevře Lister pro soubor pod kurzorem. Záložky nahoře přepínají dostupné pohledy; **Esc** okno zavře a **N** / **P** přejdou na další a předchozí soubor panelu.

| Pohled | Pro |
|---|---|
| **Text** | jakýkoli text; zvolte **kódování** (UTF-8, UTF-16, Windows-1250, ISO-8859-2, …) nebo nechte Automaticky; zalamování řádků; velmi velké soubory se zobrazují po stránkách; hledání pomocí **⌘F** |
| **Hex** | hexadecimální výpis libovolného souboru libovolné velikosti; hledání textu nebo bajtů, přechod na offset |
| **Obrázek** | přiblížení, oddálení, 100 %, přizpůsobení oknu, otočení; PNG, JPEG, HEIC, TIFF, GIF, WebP a další |
| **PDF** | čtení dokumentů PDF |
| **Přehrávač** | zvuk a video |
| **HTML** | webové stránky (se správnou znakovou sadou) |
| **Markdown** | vykreslená stránka pro soubory `.md` |
| **Diagram** | vykreslené diagramy PlantUML *(edice z GitHubu)* |

Dokumenty jako Word, Pages nebo Excel se otevřou v systémovém **Quick Look**.

### Čtečka Markdownu

U souborů `.md`, `.markdown`, `.mdown` a `.mkd` ukáže F3 vykreslený dokument: nadpisy, seznamy (i vnořené a s úkoly), tabulky, citace, odkazy, obrázky (i relativní), bloky kódu se zvýrazněním syntaxe, přeškrtnutí. Odkazy na weby se otevřou v prohlížeči, odkazy na jiné soubory v Listeru. Zdroj je na záložce **Text**. Skripty v dokumentu se nikdy nespouštějí.

### Diagramy PlantUML *(edice z GitHubu)*

F3 na souboru `.puml`, `.plantuml`, `.pu`, `.wsd` nebo `.iuml` diagram nakreslí. Soubory s více diagramy mají tlačítka **◀ Diagram / Diagram ▶**. Potřebujete PlantUML a Javu: `brew install plantuml`, nebo dejte `plantuml.jar` do `~/Library/Application Support/TCommander/`, případně zadejte jeho cestu v *Nastavení ▸ Obecné*.

## Zvýrazňování syntaxe

Zdrojový kód je barevný v Listeru, v editoru i v okně porovnání. Podporované jazyky: Swift, C, C++, Objective-C, Java, C#, Kotlin, JavaScript, TypeScript, Python, Ruby, shell, Go, Rust, PHP, SQL (PostgreSQL, MySQL, T-SQL, PL/SQL), Lua, JSON, YAML, TOML, INI, CSS, HTML, XML, Makefile, Markdown, PlantUML a radioamatérské deníky ADIF. Podporován je světlý i tmavý vzhled. Soubory nad 2 MB se kvůli plynulosti neobarvují.

## Editor (F4)

**F4** edituje soubor pod kurzorem. U textových a zdrojových souborů, které TCommander umí zvýraznit, otevře **vestavěný editor**: zvýrazňování syntaxe při psaní, lišta hledání (**⌘F**), zpět, uložení ve stejném kódování (**⌘S**; pokud text v tomto kódování nejde zapsat, nabídne se UTF-8). Ostatní textové soubory se otevřou v editoru zvoleném v *Nastavení ▸ Obecné* (výchozí je TextEdit), pokud nezapnete *Textové soubory (F4) otevírat ve vestavěném editoru*. Soubory jiných typů se otevřou ve své výchozí aplikaci. Vlastní programy typům souborů přiřadíte v *Nastavení ▸ Přidružení souborů*.

## Přidružení souborů

*Nastavení ▸ Přidružení souborů* přiřadí příponám program nebo příkaz pro **Return**, **F3** a **F4**. Bez přidružení vybere TCommander podle typu souboru: Lister pro text, obrázky, PDF a média; Quick Look pro dokumenty; výchozí aplikaci pro vše ostatní.
