# Mac App Store Edition

The Mac App Store requires every app to run in the **App Sandbox**, a protection built into macOS that keeps an app away from your files until you allow it. TCommander works fully inside it, with these differences.

## Allowing access to your files

- The first time you start TCommander it asks you to choose a folder. **Choose your home folder** (or any other folder): TCommander can then open that folder and everything inside it.
- If you later open a place that is not covered yet (for example another disk in `/Volumes`, or a folder outside your home), the same dialog appears for it. You can choose a whole disk to allow it entirely.
- Your choices are remembered; you are not asked again.
- You can also **drop a folder on the TCommander icon** in the Dock, or use *Open With ▸ TCommander* in Finder, which allows that folder.
- Dragging files from Finder into a panel works without any prompt.

The dialog is shown by macOS itself, so TCommander never sees anything outside the folders you choose.

## Which edition should I choose?

TCommander is **one app in two editions** that share the same code, the same look and the same manual. They differ only where Apple's rules for the Mac App Store do not allow a feature.

- **GitHub edition**: a free download with full access to your disk. Choose it if you need SFTP, plugins or PlantUML diagrams, or if you simply prefer to install apps yourself.
- **Mac App Store edition**: installed and updated automatically by the App Store. Choose it if you want the easiest setup and do not need the three features below.

## Differences between the editions

| Feature | GitHub edition | Mac App Store edition | Why |
|---|---|---|---|
| File manager, viewer, editor, search, compare, sync, archives | ✓ | ✓ | |
| FTP, FTPS, SMB, WebDAV | ✓ | ✓ | |
| Built-in terminal | ✓ | ✓ | In the App Store edition the shell reaches only the folders you allowed. |
| SFTP | ✓ | ✗ | It needs the system `ssh` and your keys, which the sandbox blocks. |
| Plugins | ✓ | ✗ | Apple does not allow apps to run downloaded code. |
| PlantUML diagrams | ✓ | ✗ | They need Java and an external program. The diagram source is still shown as text. |
| Access to your files | whole disk (macOS asks once per protected folder, such as Documents) | only folders you choose, once | The App Sandbox is required for every app in the store. |
| Updates | download a new release | automatic, through the App Store | |

✓ means available, ✗ means not available in that edition.

**Settings are not shared between the editions.** Both use the same file format, but each edition keeps its files in its own place (the GitHub edition in `~/Library/Application Support/TCommander/`, the App Store edition in its sandbox container). If you switch editions, you can copy your settings, shortcuts and favorites over, or export and import them.

## Privacy

TCommander has no accounts, no analytics and no tracking. See the [Privacy Policy](privacy.html).
