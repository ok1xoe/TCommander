#!/usr/bin/env python3
"""Vytvoří demonstrační složku se vzorovými soubory pro snímky obrazovky (bez osobních údajů): python3 make_demo_data.py /Users/Shared/Demo"""
import os, sys, zlib, struct, math, shutil, subprocess, time

root = sys.argv[1] if len(sys.argv) > 1 else "/Users/Shared/Demo"

def write(path, text, mtime=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f: f.write(text)
    if mtime: os.utime(path, (mtime, mtime))

def png(path, w, h, colors):
    """Gradient (dvě barvy diagonálně) jako PNG bez závislostí."""
    (r1, g1, b1), (r2, g2, b2) = colors
    rows = b""
    for y in range(h):
        row = bytearray([0])
        for x in range(w):
            t = (x / w + y / h) / 2
            wave = 0.08 * math.sin(x / 38.0) * math.cos(y / 31.0)
            t = min(1, max(0, t + wave))
            row += bytes((int(r1 + (r2 - r1) * t), int(g1 + (g2 - g1) * t), int(b1 + (b2 - b1) * t)))
        rows += bytes(row)
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows, 6)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f: f.write(data)

if os.path.isdir(root): shutil.rmtree(root)
now = time.time(); day = 86400
def t(days): return now - days * day

# --- Projects/website
web = f"{root}/Projects/website"
write(f"{web}/README.md", """# Harbor Café website

A small static site for a neighbourhood café: menu, opening hours and a contact form.

## Features

- **Responsive** layout (mobile first)
- Menu rendered from `menu.json`
- Dark mode with `prefers-color-scheme`
- ~~jQuery~~ no dependencies

## Getting started

```bash
python3 -m http.server 8000
open http://localhost:8000
```

## To do

- [x] Menu page
- [x] Opening hours
- [ ] Online reservations
- [ ] Photo gallery

| Page | File | Status |
|:--|:--|:-:|
| Home | `index.html` | done |
| Menu | `menu.html` | done |
| Contact | `contact.html` | draft |

> Tip: edit `style.css` to change the colors.
""", t(2))
write(f"{web}/index.html", """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Harbor Café</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <header class="hero"><h1>Harbor Café</h1><p>Coffee, cakes and a view of the water.</p></header>
  <main id="menu"></main>
  <script src="app.js"></script>
</body>
</html>
""", t(3))
write(f"{web}/style.css", """:root {
  --bg: #fffaf3;
  --fg: #2b2118;
  --accent: #c1440e;
  --radius: 14px;
}

@media (prefers-color-scheme: dark) {
  :root { --bg: #1b1612; --fg: #f4ece2; }
}

body {
  margin: 0;
  font: 16px/1.5 system-ui, sans-serif;
  background: var(--bg);
  color: var(--fg);
}

.hero {
  padding: 4rem 1rem;
  text-align: center;
  background: linear-gradient(135deg, #f6d365, #fda085);
}

h1 { font-size: 3rem; margin: 0 0 .5rem; /* big and friendly */ }

article {
  max-width: 34rem;
  margin: 1.5rem auto;
  padding: 1rem 1.25rem;
  border-radius: var(--radius);
  box-shadow: 0 2px 12px rgba(0, 0, 0, .12);
}

a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
""", t(4))
write(f"{web}/app.js", """// Render the menu from menu.json
async function loadMenu() {
  const response = await fetch('menu.json');
  const items = await response.json();
  const list = document.getElementById('menu');
  for (const item of items) {
    const card = document.createElement('article');
    card.innerHTML = `<h3>${item.name}</h3><p>${item.price.toFixed(2)} EUR</p>`;
    list.append(card);
  }
}
loadMenu().catch(console.error);
""", t(3))
write(f"{web}/menu.json", '[{"name": "Espresso", "price": 2.4}, {"name": "Flat white", "price": 3.2}, {"name": "Carrot cake", "price": 4.5}]\n', t(6))
write(f"{web}/notes.md", "# Notes\n\n- Ask about opening hours on Sundays\n- New logo from the designer\n", t(9))
# záloha téhož webu s drobnými rozdíly (pro porovnání a synchronizaci)
bk = f"{root}/Backup/website"
for f in ["index.html", "style.css", "app.js", "menu.json", "README.md", "notes.md"]:
    shutil.copy2(f"{web}/{f}", f"{bk}/{f}") if os.path.isdir(bk) else (os.makedirs(bk, exist_ok=True), shutil.copy2(f"{web}/{f}", f"{bk}/{f}"))
write(f"{bk}/style.css", """:root {
  --bg: #ffffff;
  --fg: #2b2118;
  --accent: #c1440e;
}

body {
  margin: 0;
  font: 16px/1.5 system-ui, sans-serif;
  background: var(--bg);
  color: var(--fg);
}

.hero {
  padding: 3rem 1rem;
  text-align: center;
  background: linear-gradient(135deg, #f6d365, #fda085);
}

h1 { font-size: 2.5rem; margin: 0 0 .5rem; }

article {
  max-width: 30rem;
  margin: 1rem auto;
  padding: 1rem;
  border: 1px solid #e6dccf;
}

a { color: var(--accent); }
""", t(30))
write(f"{bk}/old-logo.svg", '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><circle cx="32" cy="32" r="28" fill="#c1440e"/></svg>\n', t(120))

# --- Projects/mobile-app
app = f"{root}/Projects/mobile-app"
write(f"{app}/Sources/main.swift", """import Foundation

/// A tiny task list used to demonstrate syntax highlighting.
struct Task: Identifiable, Codable {
    let id: UUID
    var title: String
    var isDone = false
    var due: Date?

    var summary: String { isDone ? "✓ \\(title)" : "• \\(title)" }
}

final class TaskStore {
    private(set) var tasks: [Task] = []

    func add(_ title: String, due: Date? = nil) {
        tasks.append(Task(id: UUID(), title: title, due: due))
    }

    func complete(at index: Int) throws {
        guard tasks.indices.contains(index) else { throw StoreError.outOfRange(index) }
        tasks[index].isDone = true
    }
}

enum StoreError: Error { case outOfRange(Int) }

let store = TaskStore()
store.add("Write the user guide")
store.add("Publish version 1.0", due: Date().addingTimeInterval(86_400 * 7))
try? store.complete(at: 0)
store.tasks.forEach { print($0.summary) }
""", t(1))
write(f"{app}/Package.swift", "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"mobile-app\", targets: [.executableTarget(name: \"mobile-app\", path: \"Sources\")])\n", t(14))
write(f"{app}/Tests/StoreTests.swift", "import Testing\n@Test func addsTasks() { #expect(1 + 1 == 2) }\n", t(8))

# --- Projects/api
api = f"{root}/Projects/api"
write(f"{api}/server.py", '''#!/usr/bin/env python3
"""Minimal JSON API used for the demo."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

ITEMS = [{"id": 1, "name": "Espresso"}, {"id": 2, "name": "Flat white"}]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps(ITEMS).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
''', t(5))
write(f"{api}/schema.sql", "-- Orders for the demo shop\nCREATE TABLE orders (\n  id SERIAL PRIMARY KEY,\n  customer VARCHAR(80) NOT NULL,\n  total NUMERIC(10, 2) DEFAULT 0,\n  created_at TIMESTAMP DEFAULT now()\n);\n\nSELECT customer, SUM(total) AS spent FROM orders GROUP BY customer ORDER BY spent DESC LIMIT 10;\n", t(7))
write(f"{api}/config.yaml", "# service configuration\nserver:\n  host: 127.0.0.1\n  port: 8080\n  debug: true\nlogging: &log\n  level: info\n  file: /var/log/api.log\nworkers:\n  - name: mailer\n    <<: *log\n  - name: cleaner\n    schedule: \"0 3 * * *\"\n", t(11))
write(f"{api}/openapi.json", '{"openapi": "3.0.0", "info": {"title": "Demo API", "version": "1.0"}, "paths": {"/items": {"get": {"summary": "List items"}}}}\n', t(12))

# --- Documents
docs = f"{root}/Documents"
write(f"{docs}/Meeting notes.txt", "Project kick-off\n================\nAttendees: Anna, Ben, Carla\nDecision: ship the first version in November.\n", t(2))
write(f"{docs}/Budget 2026.csv", "Month,Income,Costs\nJan,4200,3100\nFeb,4500,3300\nMar,4100,2900\n", t(20))
write(f"{docs}/Ideas.md", "# Ideas\n\n1. Weekly newsletter\n2. Loyalty card\n3. Seasonal menu\n", t(40))
write(f"{docs}/diagram.puml", "@startuml\nactor Customer\nparticipant \"Café app\" as App\nCustomer -> App : order a flat white\nApp -> App : check stock\nApp --> Customer : ready in 5 minutes\nnote right of App : Payment is optional\n@enduml\n", t(3))

# --- Photos
cols = [((255, 154, 76), (200, 60, 120)), ((60, 140, 255), (120, 60, 220)), ((40, 190, 140), (20, 90, 160)), ((250, 214, 100), (240, 120, 60)),
        ((120, 200, 255), (30, 60, 140)), ((200, 120, 220), (60, 40, 160)), ((90, 210, 120), (230, 220, 80)), ((250, 120, 120), (120, 30, 90)),
        ((70, 100, 190), (170, 220, 250)), ((255, 190, 120), (130, 70, 40)), ((110, 180, 160), (30, 70, 90)), ((240, 150, 190), (90, 50, 170))]
for i, c in enumerate(cols, 1):
    png(f"{root}/Photos/Summer/IMG_{1000 + i}.png", 640, 480, c)
    os.utime(f"{root}/Photos/Summer/IMG_{1000 + i}.png", (t(i * 3), t(i * 3)))

# --- Downloads
dl = f"{root}/Downloads"
write(f"{dl}/installer-notes.txt", "Release 3.2\n- fixed crash on start\n- faster search\n", t(1))
with open(f"{dl}/sample-data.bin", "wb") as f: f.write(os.urandom(48_000))
write(f"{dl}/invoice-2026-09.csv", "id,customer,total\n1,ACME,120.00\n2,Globex,87.50\n", t(5))
subprocess.run(["/usr/bin/zip", "-qr", f"{dl}/Backup-2026-09.zip", "Projects/website"], cwd=root, check=False)
print("Hotovo:", root)
