# Řešení potíží

## „TCommander nelze otevřít, protože pochází od neidentifikovaného vývojáře“ (edice z GitHubu)

Stažená aplikace je podepsaná, ale není notarizovaná Applem, takže se macOS jednou zeptá. Klepněte pravým tlačítkem na TCommander v Aplikacích, zvolte **Otevřít** a potvrďte. Nebo v Terminálu spusťte:

```
xattr -dr com.apple.quarantine /Applications/TCommander.app
```

## Složku nelze otevřít nebo ukazuje chybu

- **Edice z App Store:** povolte složku, když se TCommander zeptá, nebo ji přetáhněte na ikonu TCommanderu. Viz [Verze z Mac App Store](13-app-store-edition.html).
- **Edice z GitHubu:** macOS chrání některé složky (Plocha, Dokumenty, Stažené, externí disky, Pošta, Fotky). Povolte přístup, když se macOS zeptá, nebo přidejte TCommander v *Nastavení systému ▸ Soukromí a zabezpečení ▸ Úplný přístup k disku*.

## F3 ukazuje jiný pohled, než jsem čekal

Pokud je pro daný typ souboru nainstalovaný plugin, jeho pohled je další záložka (v záhlaví Listeru je pod názvem pluginu). Textový pohled je vždy k dispozici.

## Diagramy se nekreslí (edice z GitHubu)

PlantUML potřebuje Javu a program PlantUML. Nainstalujte ho příkazem `brew install plantuml`, nebo zadejte cestu k `plantuml.jar` v *Nastavení ▸ Obecné*.

## FTP nebo síťové připojení selhává

- Zkontrolujte typ: mnoho serverů vyžaduje *FTP + explicitní TLS* místo prostého FTP.
- U serveru se self-signed certifikátem zaškrtněte *Povolit self-signed certifikát*.
- Pokud používáte proxy, zkontrolujte její adresu (`socks5://host:port` nebo `http://host:port`).

## Obnovení nastavení

Ukončete TCommander a přesuňte složku `~/Library/Application Support/TCommander` jinam (edice z App Store: `~/Library/Containers/cz.ok1xoe.TCommander`). Při příštím spuštění se vytvoří znovu.

## Hlášení problému

Založte hlášení na [github.com/ok1xoe/TCommander/issues](https://github.com/ok1xoe/TCommander/issues) a uveďte verzi macOS, verzi TCommanderu (*TCommander ▸ O aplikaci TCommander*) a co jste dělali.
