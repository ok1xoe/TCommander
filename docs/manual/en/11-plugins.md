# Plugins

*Plugins are available in the GitHub edition only.* The App Store edition does not run code from outside the app.

A plugin is a **folder** in `~/Library/Application Support/TCommander/PlugIns/` with a `plugin.json` and an executable (any language: Python, shell, Swift, Go, …). It talks to TCommander through command-line arguments, standard input and JSON on standard output. After adding a plugin, choose *Settings ▸ Plugins ▸ Reload*.

A plugin can add:

| Capability | Adds | Equivalent in Total Commander |
|---|---|---|
| **Columns** | new columns in the file list | content plugins (WDX) |
| **Viewer** | an extra tab in the Lister (F3) | lister plugins (WLX) |
| **Archive** | a new archive format that can be entered like a folder | packer plugins (WCX) |
| **File system** | a new kind of connection in *Connect to server* | file system plugins (WFX) |

## Sample plugins

Ten working plugins come with the app. Install them with **Settings ▸ Plugins ▸ Install sample plugins** (existing folders are never overwritten).

| Plugin | Does |
|---|---|
| `adifview` | amateur radio **ADIF/ADI** logs as a table of contacts with a summary by band and mode |
| `filehash` | MD5, SHA-1 and SHA-256 columns |
| `photoinfo` | camera, date taken and DPI columns for photos |
| `structview` | JSON and plist (also binary) formatted and indented |
| `macpackages` | contents of `.pkg` installers and `.dmg` disk images as folders |
| `httpindex` | web directory listings (Apache, nginx, `python -m http.server`) as a read-only file system |
| `wordcount`, `csvview`, `demozip`, `memfs` | the simplest examples of each capability |

For files that TCommander can highlight, the Lister keeps the highlighted text as its first tab and shows the plugin as an additional tab next to *Text* and *Hex*.

## Writing your own

The full specification with the manifest format, the calling conventions and examples is in the repository: [docs/plugins.md](https://github.com/ok1xoe/TCommander/blob/main/docs/plugins.md). The sample plugins in `docs/plugin-examples` are a good starting point: each is a single short Python file.
