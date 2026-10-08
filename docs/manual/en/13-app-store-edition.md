# Mac App Store Edition

The Mac App Store requires every app to run in the **App Sandbox**, a protection built into macOS that keeps an app away from your files until you allow it. TCommander works fully inside it, with these differences.

## Allowing access to your files

- The first time you start TCommander it asks you to choose a folder. **Choose your home folder** (or any other folder): TCommander can then open that folder and everything inside it.
- If you later open a place that is not covered yet (for example another disk in `/Volumes`, or a folder outside your home), the same dialog appears for it. You can choose a whole disk to allow it entirely.
- Your choices are remembered; you are not asked again.
- You can also **drop a folder on the TCommander icon** in the Dock, or use *Open With ▸ TCommander* in Finder, which allows that folder.
- Dragging files from Finder into a panel works without any prompt.

The dialog is shown by macOS itself, so TCommander never sees anything outside the folders you choose.

## Differences from the GitHub edition

| Feature | App Store edition |
|---|---|
| SFTP | not available (it needs the system `ssh` with your keys) |
| Plugins | not available (Apple does not allow apps to run downloaded code) |
| PlantUML diagrams | not available (they need Java); the source is shown as text |
| FTP, FTPS, SMB, WebDAV | available |
| Terminal | available; the shell can only reach the folders you have allowed |
| Everything else | the same |

Both editions use the same settings format, and the same manual.

## Privacy

TCommander has no accounts, no analytics and no tracking. See the [Privacy Policy](privacy.html).
