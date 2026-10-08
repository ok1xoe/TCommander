# TCommander

*English · [Česky](README.cs.md)*

A native two-panel file manager for macOS in the tradition of Norton Commander and Total Commander. Swift 6, SwiftUI + AppKit, built as a Swift package (no Xcode project).

**Website and user guide:** https://ok1xoe.github.io/TCommander/ · also built into the app (*Help* menu)

## Features

- **Two panels with tabs**, history, favorites; full, brief, thumbnail and tree views; custom columns and colors; a queue of operations with progress, pause and cancel; verified copies
- **Viewer (F3)**: text in any encoding, hex, images, PDF, audio/video, HTML, a built-in **Markdown reader**, PlantUML diagrams
- **Editor (F4)** and viewer with **syntax highlighting** for 25+ languages (also YAML, SQL, ADIF, Markdown, PlantUML)
- **Search** by name, content, regex, hex, date, size and attributes, also inside archives
- **Compare** files (side by side, editable) and folders; **synchronize** with a preview; Multi-Rename; checksums; duplicates; split/combine
- **Archives as folders**: zip, tar.*, 7z (read/write), rar, iso, cab (read)
- **Network**: FTP/FTPS, SFTP, SMB, WebDAV with proxy support and Keychain passwords
- **Terminal** (also full-screen programs like vim and top) and a command line
- **Customizable**: every shortcut, the button bar, Start menu, main menu, user commands; import from Total Commander (`wincmd.ini`)
- **Plugins** in any language (columns, viewers, archives, file systems) with ten working examples
- English and Czech interface

## Install

Download the `.dmg` or `.zip` (universal: Apple silicon and Intel, macOS 14+) from [Releases](../../releases) and drag **TCommander.app** to Applications. The download is signed ad-hoc, so on first launch right-click › **Open** (or `xattr -dr com.apple.quarantine /Applications/TCommander.app`). Developer ID signing and notarization are described in [docs/release.md](docs/release.md).

TCommander is also prepared for the **Mac App Store** (App Sandbox edition), see [docs/appstore.md](docs/appstore.md).

## Build from source

Requires macOS 14+ and Swift 6 (the Command Line Tools are enough).

```bash
swift run TCommander          # run from the package
scripts/bundle.sh             # build dist/TCommander.app (release, ad-hoc signed)
scripts/package.sh            # universal .app + .zip + .dmg in dist/
scripts/appstore.sh           # Mac App Store package (see docs/appstore.md)
scripts/build_site.sh         # website and user guide in site/
scripts/test.sh               # tests (swift test with the Swift Testing plugin path for the Command Line Tools)
```

## Documentation

- User guide: [English](docs/manual/en/00-index.md) · [Čeština](docs/manual/cs/00-index.md) (sources of the built-in help and the website)
- [docs/plugins.md](docs/plugins.md): plugin API, examples in `docs/plugin-examples/`
- [docs/spec.md](docs/spec.md): design and architecture · [docs/index.html](docs/index.html): feature list with implementation status
- [docs/release.md](docs/release.md): releases and signing · [docs/appstore.md](docs/appstore.md): Mac App Store

## Architecture

- `TCCore`: logic without UI (virtual file systems for local, archive, FTP, SFTP and plugins; file operations, search, synchronization, renaming, commands, plugins, Markdown and syntax highlighting). Covered by automated tests.
- `TCApp`: SwiftUI/AppKit interface.
- `CArchive`, `CCurl`: thin bindings to the system libarchive and libcurl.
- `DocsBuilder`: generates the website and the built-in help from `docs/manual`.

## Notes

TCommander is an independent project and is not affiliated with Total Commander or its author.
