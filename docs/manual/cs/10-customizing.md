# Přizpůsobení

**Nastavení** otevřete klávesou **⌘,** (*Nástroje ▸ Nastavení…*). Má jednu záložku pro každou oblast.

## Obecné

Externí editor a aplikace terminálu, zda mazat do Koše, ověřovat kopie, zobrazovat skryté soubory, dávat panely nad sebe, velikost písma a výška řádků v seznamech, **jazyk** (English nebo Čeština; projeví se po restartu) a v edici z GitHubu cesta k PlantUML.

## Klávesové zkratky

Každý příkaz má název jako `cm_copy`. Záložka **Zkratky** je vypisuje všechny s jejich klávesami. Klepněte do buňky s klávesou a napište požadovanou zkratku (například `ctrl+shift+c` nebo `f9`), případně několik oddělených čárkou. Konflikty se hlásí. *Obnovit výchozí zkratky* vrátí vše. Výchozí zkratky viz [Klávesové zkratky](12-shortcuts.html).

## Tlačítková lišta a menu Start

**Tlačítková lišta** nahoře a **menu Start** jsou seznamy položek. Každá má název, ikonu (název ze SF Symbols, např. `star`), **příkaz** a parametry. Příkazem může být:

- interní příkaz jako `cm_copy` nebo `cm_search`;
- uživatelský příkaz (`em_…`, viz níže);
- libovolný program nebo příkaz shellu.

Tlačítky + a − položky přidáváte a odebíráte, ↑ ↓ mění pořadí.

## Uživatelské příkazy

Na záložce **Uživatelské příkazy** definujete vlastní příkazy pojmenované `em_neco` s programem, parametry, startovní složkou, ikonou a volbou, zda se mají spustit v Terminálu. V parametrech lze použít tyto zástupné znaky:

| Zástupný znak | Nahradí se |
|---|---|
| `%P` | zdrojová složka (s lomítkem na konci) |
| `%N` | název souboru pod kurzorem |
| `%S` | názvy označených souborů |
| `%T` | cílová složka |
| `%F` | úplná cesta k souboru pod kurzorem |
| `%L` | soubor se seznamem označených cest |

Názvy se bezpečně uvozují, takže mezery a speciální znaky příkaz nerozbijí.

## Hlavní menu

Záložka **Hlavní menu** umožní skrýt libovolnou vestavěnou položku menu (skrytá položka přijde i o svou zkratku) a sestavit **vlastní menu** s vlastním názvem. Položky mohou mít podmenu (napište název jako `Podmenu/Položka`), oddělovače (samotná `-`) a klávesové zkratky. Pořadí vestavěných položek je pevné; vlastní uspořádání vytvoříte ve vlastním menu.

## Přidružení souborů

Přiřaďte příponám program nebo příkaz pro **Return**, **F3** a **F4**; viz [Prohlížeč a editor](05-viewer-editor.html#pridruzeni-souboru).

## Sloupce

Pro plný režim definujte pojmenované **sady sloupců** („pohledy“), například *Název, Velikost, Datum* nebo *Název, Rozměry, Délka*, a vybírejte je v menu *Zobrazení ▸ Sloupce*. K dispozici jsou sloupce název, přípona, velikost, datum, atributy, druh, vlastník a (z vestavěných zdrojů) rozměry obrázků, délka zvuku a videa, strany PDF a řádky textu. Další mohou přidat pluginy.

## Barvy

Barvy názvů souborů podle **masek**: například `*.zip;*.7z` červeně. Platí první odpovídající pravidlo. Složky a označené soubory mají vlastní barvy.

## Import z Total Commanderu

*Nástroje ▸ Importovat nastavení z Total Commanderu…* přečte soubor `wincmd.ini` (a `usercmd.ini` vedle něj) a převede, co jde: tlačítkovou lištu, menu Start, uživatelské příkazy, oblíbené složky a klávesové zkratky. Zpráva uvede, co se přeskočilo. Příkazy, které existují jen ve Windows, se vynechají.

## Kde jsou uložená nastavení

Edice z GitHubu ukládá soubory do `~/Library/Application Support/TCommander/` (nastavení, zkratky, tlačítka, oblíbené, spojení bez hesel, pluginy). Edice z App Store je ukládá do kontejneru svého sandboxu. Hesla jsou v Klíčence macOS.
