# Archives

Archives behave like folders. Press **Return** on an archive to enter it; leave it with Backspace.

| Format | Browse | Copy out | Change contents |
|---|---|---|---|
| zip, tar, tar.gz, tar.bz2, tar.xz, 7z | yes | yes | yes |
| rar, iso, cab and others supported by libarchive | yes | yes | read only |

## Working in an archive

- **F5** from the archive copies files out, **F5** into an archive adds them. **F6** from an archive is not possible (an archive can only be read from); **F8**, **F2** and **F7** change the contents of writable archives. TCommander rewrites the archive safely (the old file stays until the new one is complete).
- **F3** views a file directly from the archive.
- **Alt+F5** packs the marked files into a new archive (choose the format and name), **Alt+F9** unpacks an archive into a folder; several archives can be unpacked at once, each into its own folder.
- *Tools ▸ Test archive* verifies the integrity of an archive.
- Search (Alt+F7) can look inside archives, and archives can take part in [synchronization](06-compare-sync-rename.html#synchronize-folders).

## Notes

- Archives are processed with the system library *libarchive*; nothing is uploaded anywhere.
- Large archives open quickly because only the index is read.
