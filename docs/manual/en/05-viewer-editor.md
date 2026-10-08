# Viewer and Editor

## The Lister (F3)

**F3** opens the Lister for the file under the cursor. Tabs at the top switch between the available views; **Esc** closes the window and **N** / **P** go to the next and previous file of the panel.

| View | For |
|---|---|
| **Text** | any text; choose the **encoding** (UTF-8, UTF-16, Windows-1250, ISO-8859-2, …) or leave it on Automatic; wrap lines; very large files are shown page by page; search with **⌘F** |
| **Hex** | a hexadecimal dump of any file of any size; search for text or bytes, go to an offset |
| **Image** | zoom in and out, 100 %, fit to window, rotate; PNG, JPEG, HEIC, TIFF, GIF, WebP and more |
| **PDF** | read PDF documents |
| **Player** | audio and video |
| **HTML** | web pages (with the correct character set) |
| **Markdown** | a rendered page for `.md` files |
| **Diagram** | rendered PlantUML diagrams *(GitHub edition)* |

Documents such as Word, Pages or Excel open in macOS **Quick Look**.

### Markdown reader

For `.md`, `.markdown`, `.mdown` and `.mkd` files F3 shows the rendered document: headings, lists (also nested and task lists), tables, quotes, links, images (also relative ones), code blocks with syntax highlighting, strikethrough. Links to websites open in your browser, links to other files open in the Lister. The source is on the **Text** tab. Scripts in the document are never run.

### PlantUML diagrams *(GitHub edition)*

F3 on a `.puml`, `.plantuml`, `.pu`, `.wsd` or `.iuml` file draws the diagram. Files with several diagrams get **◀ Diagram / Diagram ▶** buttons. You need PlantUML and Java: `brew install plantuml`, or put `plantuml.jar` into `~/Library/Application Support/TCommander/` or enter its path in *Settings ▸ General*.

## Syntax highlighting

Source code is colored in the Lister, in the editor and in the compare window. Supported: Swift, C, C++, Objective-C, Java, C#, Kotlin, JavaScript, TypeScript, Python, Ruby, shell, Go, Rust, PHP, SQL (PostgreSQL, MySQL, T-SQL, PL/SQL), Lua, JSON, YAML, TOML, INI, CSS, HTML, XML, Makefile, Markdown, PlantUML and ADIF amateur radio logs. Light and dark appearance are both supported. Files over 2 MB are not colored to keep scrolling smooth.

## The editor (F4)

**F4** edits the file under the cursor. For text and source files that TCommander can highlight, it opens the **built-in editor**: syntax highlighting while you type, find bar (**⌘F**), undo, saving in the same encoding (**⌘S**; if the text cannot be represented in that encoding you are offered UTF-8). Other text files open in the editor chosen in *Settings ▸ General* (TextEdit by default) unless you switch on *Open text files (F4) in the built-in editor*. Files of other types open in their default application. You can assign your own programs to file types in *Settings ▸ File Associations*.

## File associations

*Settings ▸ File Associations* maps extensions to a program or command for **Return**, **F3** and **F4**. Without an association, TCommander chooses by file type: the Lister for text, images, PDF and media; Quick Look for documents; the default application for everything else.
