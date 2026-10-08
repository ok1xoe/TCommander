# Porovnání, synchronizace, přejmenování

## Porovnání souborů podle obsahu

Označte dva soubory (nebo dejte kurzor na soubor v každém panelu) a vyberte *Porovnání ▸ Porovnat soubory podle obsahu*. Oba soubory se zobrazí vedle sebe se zvýrazněnými rozdíly (změněné řádky žlutě, jen vlevo červeně, jen vpravo zeleně).

- **◀ Předchozí rozdíl / Další rozdíl ▶** přeskakují mezi bloky.
- **Blok → doprava / ← Blok doleva** zkopírují blok pod kurzorem do druhého souboru.
- **Upravit text** umožní psát přímo v obou souborech; po stisku **Hotovo** se rozdíly přepočítají.
- **Uložit levý / Uložit pravý** zapíší soubory v původním kódování.
- Binární soubory se porovnávají bajt po bajtu a vypíší se odlišné řádky.

## Porovnání složek

*Porovnání ▸ Porovnat adresáře (označit rozdíly)* označí v obou panelech soubory, které jsou jen na jedné straně nebo jsou odlišné či novější. Označené soubory pak zkopírujete klávesou F5.

## Synchronizace složek

*Porovnání ▸ Synchronizovat adresáře…* ukáže tabulku obou složek s navrženou akcí pro každou položku.

- Směr: zleva doprava, zprava doleva, **obousměrně** (novější soubor vyhrává), nebo **zrcadlení** (nadbytečné soubory v cíli se smažou).
- Filtry: jen odlišné soubory, zobrazit shodné, ignorované masky např. `*.tmp;.DS_Store`.
- Jednotlivé položky lze vybrat či odznačit; prohlédněte si náhled s počty kopií a mazání a spusťte.
- Archivy jako zip nebo tar mohou být jednou stranou synchronizace; archiv se poté znovu vytvoří.

## Hromadné přejmenování

*Nástroje ▸ Hromadné přejmenování* (**Ctrl+M**) přejmenuje označené soubory podle vzoru, s živým náhledem a upozorněním na duplicitní nebo neplatné názvy.

| Zástupný znak | Význam |
|---|---|
| `[N]` / `[E]` | název / přípona |
| `[N1-3]`, `[N2,5]` | znaky 1 až 3 názvu; 5 znaků od pozice 2 |
| `[C]`, `[C10+5:3]` | počítadlo; začátek 10, krok 5, 3 číslice |
| `[P]` | název nadřazené složky |
| `[Y] [M] [D] [h] [m] [s]` | datum a čas změny |

Dále **hledání a nahrazení** (i regulárním výrazem), **velikost písmen** (VELKÁ, malá, První velké, Každé Slovo Velké) a **předvolby**, které můžete uložit pod názvem. Přejmenování lze hned poté vrátit zpět.
