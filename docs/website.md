# Web aplikace: nasazení na vlastní doménu

Web (úvodní marketingová stránka, příručka v angličtině a češtině, zásady soukromí) se generuje z `docs/manual` a `docs/web` příkazem `scripts/build_site.sh` do složky `site/`. Je to **statický web bez závislostí**: všechny odkazy uvnitř jsou relativní, takže ho lze nasadit na libovolnou doménu i do podsložky jiného webu. Adresa je potřeba jen pro kanonické odkazy, mapu webu (`sitemap.xml`) a `robots.txt`.

Dnes běží na GitHub Pages: https://ok1xoe.github.io/TCommander/

## Co se nastavuje

| Proměnná | Význam | Příklad |
|---|---|---|
| `CUSTOM_DOMAIN` | vlastní doména; vytvoří soubor `CNAME` a nastaví adresy | `tcommander.ok1xoe.dev` |
| `SITE_URL` | úplná adresa webu, když není na kořeni domény | `https://ok1xoe.dev/tcommander` |
| `APPSTORE_URL` | odkaz do Mac App Store (tlačítko „coming soon“ se změní na odkaz) | `https://apps.apple.com/…` |

Na GitHubu se nastavují v repozitáři: **Settings › Secrets and variables › Actions › Variables**. Po změně spusťte workflow *Web a příručka* ručně (**Actions › Run workflow**). Lokálně: `CUSTOM_DOMAIN=tcommander.ok1xoe.dev scripts/build_site.sh`.

## Varianta A: samostatná doména (tcommander.com nebo tcommander.ok1xoe.dev)

1. Zvolte adresu a (u vlastní domény) ji zaregistrujte.
2. U poskytovatele DNS nastavte záznamy:
   - **subdoména** `tcommander.ok1xoe.dev`: záznam **CNAME** `tcommander` → `ok1xoe.github.io`
   - **kořenová doména** `tcommander.com`: čtyři záznamy **A** na `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153` (volitelně i čtyři **AAAA** podle dokumentace GitHub Pages) a záznam **CNAME** `www` → `ok1xoe.github.io`
3. V repozitáři přidejte proměnnou `CUSTOM_DOMAIN` (např. `tcommander.com`) a spusťte workflow.
4. **Settings › Pages**: u *Custom domain* se doména objeví sama (z `CNAME`); po ověření DNS zaškrtněte **Enforce HTTPS**.

Jeden repozitář může mít jen jednu vlastní doménu. Další (například `www` nebo druhou adresu) nastavte u poskytovatele DNS jako přesměrování na hlavní.

## Varianta B: stránka na hlavním webu OK1XOE.dev

- Pokud je OK1XOE.dev nasazený přes GitHub Pages jako uživatelský web (repozitář `ok1xoe.github.io`), je projektový web TCommanderu dostupný sám na `https://ok1xoe.dev/TCommander/`. Nastavte jen `SITE_URL=https://ok1xoe.dev/TCommander`.
- Pokud OK1XOE.dev běží jinde, nastavte `SITE_URL=https://ok1xoe.dev/tcommander`, spusťte `scripts/build_site.sh` a obsah složky `site/` nahrajte do podsložky `tcommander/` svého webu. Odkazy fungují beze změny. Z hlavní stránky na ni stačí odkázat.

## Co udělat po schválení v App Store

1. Nastavit `APPSTORE_URL` a spustit workflow: tlačítko „Mac App Store“ povede do obchodu.
2. Do `appstore/metadata` (pole *Marketing URL*) doplnit konečnou adresu webu.
3. Stejnou adresu uvést v zásadách soukromí a na stránce podpory, pokud se změní.

## Obsah stránky

Úvod: ikona, slogan, tlačítka stažení, galerie snímků (6 viditelných, ostatní pod „Zobrazit všechny“), 12 hlavních funkcí, sekce „Přicházíte z Total Commanderu?“, tabulka rozdílů mezi edicemi (GitHub × App Store s vysvětlením), stažení obou edic, otázky a odpovědi. Příručka má 15 stránek s vyhledáváním. Texty webu jsou v `Sources/DocsBuilder/Texts.swift`, vzhled v `docs/web/style.css`, snímky v `docs/web/img` (vznikají skriptem `scripts/screenshots/take.sh`).
