# Selecting and Searching

## Marking files

Marked files are shown in red. Most commands work on the marked files, or on the file under the cursor if nothing is marked.

| Do | Result |
|---|---|
| **Space** or **Insert** | mark or unmark the file under the cursor and move down (Space on a folder also calculates its size) |
| **⌘A** / **⇧⌘A** | mark all / unmark all |
| Numpad **+** / **−** | mark or unmark by mask, e.g. `*.jpg;*.png` |
| Numpad **\*** | invert the marking |
| *Mark ▸ Mark same extension* | mark all files with the extension of the current file |
| *Save selection / Restore selection* | remember a marking and bring it back |

Masks use `*` and `?` and can be combined with `;` or a space.

## Quick filter

Press **Ctrl+S** (or **⌘F**) and type to show only matching names in the panel. Esc cancels the filter.

## Find files (Alt+F7)

The search dialog is as powerful as the one in Total Commander:

- **Where**: any folder, optionally with subfolders; archives can be searched too (in the GitHub edition and the App Store edition alike).
- **What**: name masks (`*.txt;*.md`), names to exclude, text inside files (case sensitive, regular expression, whole words), and binary byte sequences such as `4D 5A`.
- **Filters**: size, date range ("modified in the last N days"), and attributes.
- **Templates**: save a search under a name and run it again later.

Results appear in a list. Double-click or press Return to go to a file, **F3** views it, and **Results to panel** shows the found files as a virtual folder in a panel, where you can copy, move or delete them like any other files.

## Branch view

*View ▸ Branch view* lists all files of the current folder and its subfolders in one flat list: ideal for working with "everything below this folder" without searching.
