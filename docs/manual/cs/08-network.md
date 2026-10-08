# Síť: FTP, SMB, WebDAV, SFTP

Otevřete *Síť ▸ Připojit k serveru…* (**⌘K**). Vyberte typ, vyplňte server a připojení případně uložte. Uložená připojení jsou v menu **Síť**; hesla se ukládají do **Klíčenky**, nikdy do souboru.

| Typ | Funguje jako | Poznámky |
|---|---|---|
| **FTP**, **FTP + explicitní TLS**, **FTPS (implicitní TLS)** | složka v panelu | přenosy lze navázat; volitelně self-signed certifikát |
| **SMB** (sdílená složka) | připojený svazek | jako *Připojit se k serveru* ve Finderu |
| **WebDAV** (http / https) | připojený svazek | |
| **SFTP** *(edice z GitHubu)* | složka v panelu | heslo nebo soubor s klíčem; používá systémový `ssh` |
| **Plugin** *(edice z GitHubu)* | složka v panelu | souborové systémy z pluginů, viz [Pluginy](11-plugins.html) |

Po připojení panel funguje jako místní složka: kopírování, přesun, mazání, přejmenování a vytváření složek; F3 a F4 stáhnou soubor na dočasné místo, otevřou ho a (u F4) po uložení znovu nahrají. Návrat do místní složky provedete příkazem *Síť ▸ Odpojit panel od serveru*.

## Proxy

U FTP a SFTP můžete zadat proxy, např. `socks5://127.0.0.1:1080` nebo `http://proxy:3128`.

## Tipy

- Velké přenosy běží ve frontě na pozadí; můžete dál procházet.
- Přerušený přenos pokračuje tam, kde skončil, až příště zkopírujete týž soubor.
- U serverů s neobvyklými výpisy zkontrolujte typ připojení: nejběžnější zabezpečený typ je *FTP + explicitní TLS*.
