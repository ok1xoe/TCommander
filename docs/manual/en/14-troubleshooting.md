# Troubleshooting

## "TCommander can't be opened because it is from an unidentified developer" (GitHub edition)

The downloaded app is signed but not notarized by Apple, so macOS asks once. Right-click TCommander in Applications, choose **Open** and confirm. Or run in Terminal:

```
xattr -dr com.apple.quarantine /Applications/TCommander.app
```

## A folder cannot be opened or shows an error

- **App Store edition:** allow the folder when TCommander asks, or drop it on the TCommander icon. See [Mac App Store Edition](13-app-store-edition.html).
- **GitHub edition:** macOS protects some folders (Desktop, Documents, Downloads, external disks, Mail, Photos). Allow access when macOS asks, or add TCommander under *System Settings ▸ Privacy & Security ▸ Full Disk Access*.

## F3 shows a different view than I expected

If a plugin is installed for that file type, its view is an extra tab (the tab bar of the Lister lists it by the plugin's name). The text view is always available.

## Diagrams are not drawn (GitHub edition)

PlantUML needs Java and the PlantUML program. Install with `brew install plantuml`, or enter the path to `plantuml.jar` in *Settings ▸ General*.

## An FTP or network connection fails

- Check the type: many servers need *FTP + explicit TLS* instead of plain FTP.
- For a server with a self-signed certificate tick *Allow self-signed certificate*.
- If you use a proxy, check its address (`socks5://host:port` or `http://host:port`).

## Resetting the settings

Quit TCommander and move the folder `~/Library/Application Support/TCommander` somewhere else (App Store edition: `~/Library/Containers/cz.ok1xoe.TCommander`). It is created again on the next start.

## Reporting a problem

Open an issue at [github.com/ok1xoe/TCommander/issues](https://github.com/ok1xoe/TCommander/issues) and tell us the macOS version, the TCommander version (*TCommander ▸ About*) and what you did.
