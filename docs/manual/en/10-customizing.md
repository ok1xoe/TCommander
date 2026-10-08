# Customizing

Open **Settings** with **⌘,** (*Tools ▸ Settings…*). It has one tab for each area.

## General

Your external editor and terminal application, whether to delete to the Trash, verify copies, show hidden files, stack the panels, the font size and row height of the lists, the **language** (English or Čeština; takes effect after a restart) and, in the GitHub edition, the path to PlantUML.

## Keyboard shortcuts

Every command has a name like `cm_copy`. The **Shortcuts** tab lists all of them with their keys. Click a key cell and type the shortcut you want (for example `ctrl+shift+c` or `f9`), or several separated by commas. Conflicts are reported. *Restore default shortcuts* resets everything. See [Keyboard Shortcuts](12-shortcuts.html) for the defaults.

## Button bar and Start menu

The **Button bar** at the top and the **Start menu** are lists of entries. Each has a title, an icon (a name from SF Symbols, e.g. `star`), a **command** and parameters. The command can be:

- an internal command such as `cm_copy` or `cm_search`;
- a user command (`em_…`, see below);
- any program or shell command.

Use + and − to add and remove entries and ↑ ↓ to reorder.

## User commands

On the **User Commands** tab you define your own commands named `em_something` with a program, parameters, a start folder, an icon, and whether to run it in the Terminal. Parameters can use these placeholders:

| Placeholder | Replaced by |
|---|---|
| `%P` | source folder (with a slash at the end) |
| `%N` | name of the file under the cursor |
| `%S` | names of the marked files |
| `%T` | target folder |
| `%F` | full path of the file under the cursor |
| `%L` | a file with the list of marked paths |

Names are quoted safely so that spaces and special characters cannot break the command.

## Main menu

The **Main Menu** tab lets you hide any of the built-in menu items (hidden items also lose their shortcut) and build a **custom menu** with your own title. Entries can have submenus (write the title as `Submenu/Item`), separators (a single `-`), and keyboard shortcuts. The order of the built-in items is fixed; arrange your own in the custom menu.

## File associations

Map extensions to a program or command for **Return**, **F3** and **F4**; see [Viewer and Editor](05-viewer-editor.html#file-associations).

## Columns

Define named **column sets** ("views") for the Full mode, for example *Name, Size, Date* or *Name, Dimensions, Duration*, and choose them in the *View ▸ Columns* menu. Available columns include name, extension, size, date, attributes, kind, owner, and (from built-in providers) image dimensions, audio and video length, PDF pages and text lines. Plugins can add more.

## Colors

Colors the file names by **masks**: for example `*.zip;*.7z` in red. The first matching rule wins. Folders and marked files have their own colors.

## Import from Total Commander

*Tools ▸ Import settings from Total Commander…* reads a `wincmd.ini` (and the `usercmd.ini` next to it) and converts what it can: the button bar, the Start menu, user commands, favorite folders and keyboard shortcuts. A report tells you what was skipped. Commands that exist only on Windows are left out.

## Where settings are stored

The GitHub edition keeps its files in `~/Library/Application Support/TCommander/` (settings, shortcuts, buttons, favorites, connections without passwords, plugins). The App Store edition keeps them in its sandbox container. Passwords are in the macOS Keychain.
