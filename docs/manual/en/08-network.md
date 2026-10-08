# Network: FTP, SMB, WebDAV, SFTP

Open *Network ▸ Connect to server…* (**⌘K**). Choose the type, fill in the server and optionally save the connection. Saved connections are in the **Network** menu; passwords are stored in your **Keychain**, never in a file.

| Type | Works as | Notes |
|---|---|---|
| **FTP**, **FTP + explicit TLS**, **FTPS (implicit TLS)** | a folder in a panel | transfers can be resumed; optional self-signed certificate |
| **SMB** (shared folder) | a mounted volume | like *Connect to Server* in Finder |
| **WebDAV** (http / https) | a mounted volume | |
| **SFTP** *(GitHub edition)* | a folder in a panel | password or key file; uses the system `ssh` |
| **Plugin** *(GitHub edition)* | a folder in a panel | file systems from plugins, see [Plugins](11-plugins.html) |

Once connected, the panel works like a local folder: copy, move, delete, rename and create folders; F3 and F4 download the file to a temporary place, open it, and (for F4) upload it again after saving. Use *Network ▸ Disconnect panel* to return to a local folder.

## Proxy

For FTP and SFTP you can enter a proxy such as `socks5://127.0.0.1:1080` or `http://proxy:3128`.

## Tips

- Large transfers run in the background queue; you can keep browsing.
- A transfer that was interrupted continues where it stopped the next time you copy the same file.
- For servers with unusual listings, make sure the connection type is right: *FTP + explicit TLS* is the most common secure type.
