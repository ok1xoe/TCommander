# Označování a hledání

## Označování souborů

Označené soubory jsou červené. Většina příkazů pracuje s označenými soubory, nebo se souborem pod kurzorem, pokud nic označeno není.

| Akce | Výsledek |
|---|---|
| **Mezerník** nebo **Insert** | označí nebo odznačí soubor pod kurzorem a posune se dolů (mezerník na složce spočítá i její velikost) |
| **⌘A** / **⇧⌘A** | označit vše / zrušit označení |
| Numerické **+** / **−** | označit nebo odznačit podle masky, např. `*.jpg;*.png` |
| Numerická **\*** | invertovat označení |
| *Označit ▸ Označit stejnou příponu* | označí všechny soubory s příponou aktuálního souboru |
| *Uložit výběr / Obnovit výběr* | zapamatuje označení a později ho vrátí |

Masky používají `*` a `?` a lze je spojovat pomocí `;` nebo mezery.

## Rychlý filtr

Stiskněte **Ctrl+S** (nebo **⌘F**) a pište: v panelu zůstanou jen odpovídající názvy. Esc filtr zruší.

## Hledání souborů (Alt+F7)

Dialog hledání je stejně silný jako v Total Commanderu:

- **Kde**: libovolná složka, volitelně s podsložkami; hledat lze i v archivech.
- **Co**: masky názvů (`*.txt;*.md`), vyloučené názvy, text uvnitř souborů (s ohledem na velikost písmen, regulární výraz, celá slova) a binární posloupnosti bajtů, např. `4D 5A`.
- **Filtry**: velikost, rozsah dat („změněno za posledních N dnů“) a atributy.
- **Šablony**: hledání uložíte pod názvem a později znovu spustíte.

Výsledky se zobrazí v seznamu. Dvojklikem nebo Returnem přejdete na soubor, **F3** ho zobrazí a **Výsledky do panelu** ukáže nalezené soubory jako virtuální složku v panelu, kde je můžete kopírovat, přesouvat nebo mazat jako jiné soubory.

## Branch view

*Zobrazení ▸ Branch view* vypíše všechny soubory aktuální složky a jejích podsložek do jednoho plochého seznamu: ideální pro práci se „vším pod touto složkou“ bez hledání.
