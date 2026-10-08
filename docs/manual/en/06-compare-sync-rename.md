# Compare, Synchronize, Rename

## Compare files by content

Mark two files (or put the cursor on a file in each panel) and choose *Compare ▸ Compare files by content*. The two files appear side by side with differences highlighted (changed lines yellow, only on the left red, only on the right green).

- **◀ Previous difference / Next difference ▶** jump between blocks.
- **Block → right / ← Block left** copy the block under the cursor to the other file.
- **Edit text** lets you type directly in both files; press **Done** and the differences are recalculated.
- **Save left / Save right** write the files in their original encoding.
- Binary files are compared byte by byte and the differing rows are listed.

## Compare folders

*Compare ▸ Compare folders (mark differences)* marks in both panels the files that are only on one side, or are different or newer. Then use F5 to copy the marked files over.

## Synchronize folders

*Compare ▸ Synchronize folders…* shows a table of both folders with the proposed action for each item.

- Direction: left to right, right to left, **two-way** (the newer file wins), or **mirror** (delete extras at the target).
- Filters: only different files, show identical files, ignore masks such as `*.tmp;.DS_Store`.
- Select or clear individual items, review the preview with counts of copies and deletions, and run it.
- Archives such as zip or tar can be one side of a synchronization; the archive is rewritten afterwards.

## Multi-Rename Tool

*Tools ▸ Multi-Rename* (**Ctrl+M**) renames the marked files by a pattern, with a live preview and a warning about duplicate or invalid names.

| Placeholder | Meaning |
|---|---|
| `[N]` / `[E]` | name / extension |
| `[N1-3]`, `[N2,5]` | characters 1 to 3 of the name; 5 characters from position 2 |
| `[C]`, `[C10+5:3]` | counter; start 10, step 5, 3 digits |
| `[P]` | name of the parent folder |
| `[Y] [M] [D] [h] [m] [s]` | date and time of modification |

Plus **search and replace** (also with regular expressions), **letter case** (UPPERCASE, lowercase, First Capital, Each Word Capitalized) and **presets** you can save under a name. Renames can be undone right after.
