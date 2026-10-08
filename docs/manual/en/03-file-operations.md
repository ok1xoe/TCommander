# Copying, Moving and Deleting

## Copy and move

Mark files (or leave the cursor on one) and press **F5** to copy or **F6** to move. The target is the folder in the other panel; you can edit it in the dialog.

- Operations run in a **queue** shown at the bottom. Click a job to see details, pause it, or cancel it. Several jobs can wait in line.
- On APFS, copies within a volume are instant (they use file cloning) and take no extra space until a file is changed.
- **Verify copies (SHA-256)** in Settings compares every copied file with its source.
- Interrupted copies can be resumed on FTP servers.
- Copy and move work from and to archives and servers, too (see [Archives](07-archives.html) and [Network](08-network.html)).

### When a file already exists

| Choice | Meaning |
|---|---|
| Overwrite | replace the target file |
| Overwrite older | replace only if the source is newer |
| Skip | leave the target alone |
| Keep both | the new file gets a numbered name |
| ... all | apply the same choice to the rest of the job |

## Delete

**F8** moves the marked files to the **Trash**. **Shift+F8** deletes them permanently after a confirmation. If you switch off "Delete to Trash" in Settings, F8 deletes permanently.

## Create and rename

- **F7** creates a folder (you can type `a/b/c` to create nested folders), **Shift+F4** creates a text file.
- **F2** renames in place, **Shift+F6** opens a rename dialog. For many files at once use [Multi-Rename](06-compare-sync-rename.html#multi-rename-tool).
- **Alt+Return** opens **Properties**: size, dates, permissions (enter them in octal, optionally for everything inside a folder), file flags, and the owner and group (changing those needs administrator rights and is not available).

## Links

*Tools ▸ Symbolic link / Hard link into the other panel* creates a link to the file under the cursor in the folder of the other panel.

## Checksums, splitting, encoding

- **Checksums…** calculates MD5, SHA-1 or SHA-256 for marked files and writes a checksum file; *Verify checksums from file* checks it later.
- **Split file / Combine files** cut a large file into parts (`.001`, `.002`, …) and join them again.
- **Encode / Decode files** converts to and from MIME (Base64), UUE and XXE.
- **Find duplicate files** looks for identical files by size and content and lets you select the redundant copies.
