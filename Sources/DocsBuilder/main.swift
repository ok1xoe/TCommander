import Foundation
import TCCore

// Generátor webu a příručky: docs/manual/<jazyk>/*.md → site/ (HTML, vyhledávací index, úvodní stránky, mapa webu).
// Použití: DocsBuilder [--manual docs/manual] [--web docs/web] [--out site] [--version 1.0.0] [--site-url https://…] [--repo https://github.com/…] [--appstore-url https://…] [--custom-domain tcommander.example.com]

var options: [String: String] = ["--manual": "docs/manual", "--web": "docs/web", "--out": "site", "--version": TCVersion.string,
                                 "--site-url": "https://ok1xoe.github.io/TCommander", "--repo": "https://github.com/ok1xoe/TCommander", "--appstore-url": "", "--custom-domain": ""]
var argv = Array(CommandLine.arguments.dropFirst())
while argv.count >= 2 { if options[argv[0]] != nil || argv[0].hasPrefix("--") { options[argv[0]] = argv[1] }; argv.removeFirst(2) }
let fm = FileManager.default
let manual = URL(fileURLWithPath: options["--manual"]!), web = URL(fileURLWithPath: options["--web"]!), out = URL(fileURLWithPath: options["--out"]!)
let version = options["--version"]!, siteURL = options["--site-url"]!.hasSuffix("/") ? String(options["--site-url"]!.dropLast()) : options["--site-url"]!, repo = options["--repo"]!, appStoreURL = options["--appstore-url"]!, customDomain = options["--custom-domain"]!
var warnings: [String] = []

func esc(_ s: String) -> String { MarkdownHTML.escape(s) }
func write(_ text: String, to url: URL) {
    try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { fputs("Nelze zapsat \(url.path): \(error)\n", stderr); exit(1) }
}

// MARK: Stránky

struct Page { var slug: String; var title: String; var markdown: String; var html: String = ""; var plain: String = "" }

func loadPages(_ lang: String) -> [Page] {
    let dir = manual.appendingPathComponent(lang)
    let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasSuffix(".md") }.sorted { a, b in
        // privacy.md až na konec, ostatní podle čísla
        if a == "privacy.md" { return false }; if b == "privacy.md" { return true }; return a < b
    }
    var pages: [Page] = []
    for n in names {
        let md = (try? String(contentsOf: dir.appendingPathComponent(n), encoding: .utf8)) ?? ""
        let title = md.split(separator: "\n").first { $0.hasPrefix("# ") }.map { String($0.dropFirst(2)) } ?? n
        pages.append(Page(slug: String(n.dropLast(3)), title: title, markdown: md))
    }
    return pages
}

// MARK: Zkratky (generované z registru příkazů, takže vždy odpovídají aplikaci)

func prettyKey(_ k: String, cs: Bool) -> String {
    switch k {
    case "return": return "Return"; case "tab": return "Tab"; case "space": return cs ? "Mezerník" : "Space"; case "backspace": return "⌫ Backspace"
    case "delete": return cs ? "⌦ Delete (fn⌫)" : "⌦ Delete (fn⌫)"; case "escape": return "Esc"; case "insert": return "Insert"
    case "up": return "↑"; case "down": return "↓"; case "left": return "←"; case "right": return "→"
    case "home": return "Home"; case "end": return "End"; case "pageup": return "Page Up"; case "pagedown": return "Page Down"
    case "kp+": return cs ? "numerické +" : "numpad +"; case "kp-": return cs ? "numerické −" : "numpad −"; case "kp*": return cs ? "numerická *" : "numpad *"; case "kp/": return cs ? "numerické /" : "numpad /"
    default: return k.count == 1 ? k.uppercased() : k.uppercased()
    }
}

func prettyShortcut(_ s: Shortcut, cs: Bool) -> String {
    var m = ""
    if s.modifiers.contains(.ctrl) { m += "⌃" }; if s.modifiers.contains(.alt) { m += "⌥" }; if s.modifiers.contains(.shift) { m += "⇧" }; if s.modifiers.contains(.cmd) { m += "⌘" }
    return "`" + m + prettyKey(s.key, cs: cs) + "`"
}

let categoryNames: [String: (en: String, cs: String)] = [
    "Soubory": ("Files", "Soubory"), "Označování": ("Marking", "Označování"), "Panely": ("Panels and tabs", "Panely a záložky"),
    "Porovnání": ("Compare and synchronize", "Porovnání a synchronizace"), "Síť": ("Network", "Síť"), "Nástroje": ("Tools", "Nástroje")]

let menuShortcuts: [(en: String, cs: String, keys: String)] = [
    ("New tab / close tab", "Nový tab / zavřít tab", "⌘T / ⌘W"), ("Open", "Otevřít", "⌘O"), ("Find files", "Hledat soubory", "⇧⌘F"), ("New folder", "Nový adresář", "⇧⌘N"),
    ("Delete (to Trash)", "Smazat (do Koše)", "⌘⌫"), ("Mark all / unmark all", "Označit vše / zrušit označení", "⌘A / ⇧⌘A"), ("Mark same extension", "Označit stejnou příponu", "⇧⌘E"),
    ("Compare files by content", "Porovnat soubory podle obsahu", "⌃⇧C"), ("Compare folders", "Porovnat adresáře", "⌃⇧D"), ("Synchronize folders", "Synchronizovat adresáře", "⌃⇧S"),
    ("Settings", "Nastavení", "⌘,"), ("Terminal", "Terminál", "⌥⌘T"), ("Connect to server / disconnect", "Připojit k serveru / odpojit", "⌘K / ⇧⌘K"),
    ("Add current folder to favorites", "Přidat aktuální adresář do oblíbených", "⌘D"), ("Show hidden files", "Skryté soubory", "⇧⌘."), ("Full / brief / thumbnails / tree", "Plný / stručný / náhledy / strom", "⌃1 / ⌃2 / ⌃3 / ⌃4"),
    ("Quick View", "Quick View", "⌃Q"), ("Reload", "Obnovit", "⌘R"), ("Branch view", "Branch view", "⌘B"), ("Quick filter", "Rychlý filtr", "⌘F"),
    ("Up / back / forward", "Nadřazený adresář / zpět / vpřed", "⌘↑ / ⌘[ / ⌘]"), ("Target = source", "Cíl = zdroj", "⌘="), ("Swap panels", "Prohodit panely", "⌘U"),
    ("Next / previous tab", "Další / předchozí tab", "⇧⌘] / ⇧⌘["), ("Help", "Nápověda", "⌘?")]

func shortcutsMarkdown(cs: Bool) -> String {
    var md = cs ? "# Klávesové zkratky\n\nVýchozí klávesy příkazů. Všechny se dají změnit v *Nastavení ▸ Zkratky*; příkaz lze vložit i do tlačítkové lišty nebo menu Start pod uvedeným názvem (`cm_…`).\n\n"
                : "# Keyboard Shortcuts\n\nThe default keys of the commands. All of them can be changed in *Settings ▸ Shortcuts*; each command can also be placed on the button bar or the Start menu under its name (`cm_…`).\n\n"
    var grouped: [String: [CommandInfo]] = [:]
    for c in CommandRegistry.all { grouped[c.category, default: []].append(c) }
    for category in ["Soubory", "Označování", "Panely", "Porovnání", "Síť", "Nástroje"] {
        guard let list = grouped[category] else { continue }
        let names = categoryNames[category] ?? (category, category)
        md += "## \(cs ? names.cs : names.en)\n\n| \(cs ? "Příkaz" : "Command") | \(cs ? "Klávesa" : "Key") | ID |\n|---|---|---|\n"
        for c in list {
            let title: String
            if cs { title = c.title } else {
                title = Localization.translate(c.title, language: "en")
                if Localization.en[c.title] == nil && Localization.enMore[c.title] == nil { warnings.append("Chybí anglický překlad příkazu „\(c.title)“") }
            }
            let keys = c.defaultShortcuts.isEmpty ? (cs ? "(bez zkratky)" : "(none)") : c.defaultShortcuts.map { prettyShortcut($0, cs: cs) }.joined(separator: ", ")
            md += "| \(title) | \(keys) | `\(c.id)` |\n"
        }
        md += "\n"
    }
    md += cs ? "## Zkratky hlavního menu\n\nNěkteré zkratky patří přímo položkám menu (jejich skrytí v *Nastavení ▸ Hlavní menu* je odstraní).\n\n| Položka | Klávesa |\n|---|---|\n"
             : "## Main menu shortcuts\n\nSome shortcuts belong to the menu items themselves (hiding an item in *Settings ▸ Main Menu* removes its shortcut).\n\n| Item | Key |\n|---|---|\n"
    for m in menuShortcuts { md += "| \(cs ? m.cs : m.en) | `\(m.keys)` |\n" }
    md += cs ? "\nNa Macu klávesa **Delete** (⌫) odpovídá klávese Backspace. Klávesa „Delete“ ve smyslu Windows (⌦) je **fn⌫**.\n" : "\nOn a Mac the **Delete** key (⌫) is the Backspace key. The Windows-style “Delete” (⌦) is **fn⌫**.\n"
    return md
}

// MARK: HTML

func plainText(_ html: String) -> String {
    var t = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    for (a, b) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] { t = t.replacingOccurrences(of: a, with: b) }
    return t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
}

func htmlFileName(_ slug: String) -> String { slug == "00-index" ? "index.html" : slug + ".html" }

func head(_ s: Strings, title: String, description: String, assets: String, canonical: String, alternate: String, searchIndex: String?, extra: String = "") -> String {
    let other = s.lang == "en" ? "cs" : "en"
    return """
    <!doctype html>
    <html lang="\(s.lang)"><head>
    <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light dark">
    <title>\(esc(title))</title><meta name="description" content="\(esc(description))">
    <link rel="canonical" href="\(esc(canonical))"><link rel="alternate" hreflang="\(s.lang)" href="\(esc(canonical))"><link rel="alternate" hreflang="\(other)" href="\(esc(alternate))">
    <meta property="og:title" content="\(esc(title))"><meta property="og:description" content="\(esc(description))"><meta property="og:type" content="website"><meta property="og:url" content="\(esc(canonical))"><meta property="og:image" content="\(esc(siteURL))/assets/img/icon-512.png"><meta property="og:locale" content="\(s.locale)">
    <link rel="icon" type="image/png" href="\(assets)img/icon-64.png"><link rel="apple-touch-icon" href="\(assets)img/icon-180.png">
    <link rel="stylesheet" href="\(assets)style.css">
    \(searchIndex.map { "<script src=\"\($0)\" defer></script>" } ?? "")<script src="\(assets)app.js" defer></script>\(extra)
    </head>
    """
}

func renderGuidePage(_ s: Strings, pages: [Page], index: Int) -> String {
    let p = pages[index]
    let langPath = s.lang
    let sideItems = pages.enumerated().map { i, q in
        "<li><a href=\"\(htmlFileName(q.slug))\"\(i == index ? " class=\"current\" aria-current=\"page\"" : "")>\(esc(q.title))</a></li>"
    }.joined(separator: "\n")
    let prev = index > 0 ? "<a class=\"prev\" href=\"\(htmlFileName(pages[index - 1].slug))\">← \(s.previous)<span>\(esc(pages[index - 1].title))</span></a>" : "<span></span>"
    let next = index + 1 < pages.count ? "<a class=\"next\" href=\"\(htmlFileName(pages[index + 1].slug))\">\(s.next) →<span>\(esc(pages[index + 1].title))</span></a>" : "<span></span>"
    let canonical = "\(siteURL)/docs/\(langPath)/\(htmlFileName(p.slug))"
    let alt = "\(siteURL)/docs/\(s.otherLanguage)/\(htmlFileName(p.slug))"
    let desc = String(p.plain.prefix(155))
    let landing = s.lang == "en" ? "../../index.html" : "../../cs/index.html"
    return head(s, title: "\(p.title) – TCommander", description: desc, assets: "../../assets/", canonical: canonical, alternate: alt, searchIndex: "search-index.js") + """
    <body class="guide">
    <header class="top">
      <a class="brand" href="index.html"><img src="../../assets/img/icon-64.png" alt="" width="28" height="28"><b>TCommander</b><span>\(s.guide)</span></a>
      <div class="search"><input id="q" type="search" placeholder="\(esc(s.searchPlaceholder))" autocomplete="off" aria-label="\(esc(s.searchPlaceholder))"><div id="results" hidden></div></div>
      <nav class="links"><a href="\(landing)">\(s.home)</a><a class="lang" href="../\(s.otherLanguage)/\(htmlFileName(p.slug))" hreflang="\(s.otherLanguage)">\(s.otherLanguageName)</a></nav>
    </header>
    <div class="layout">
      <nav class="side" aria-label="\(s.guide)"><ul>
    \(sideItems)
      </ul></nav>
      <main><article>
    \(p.html)
      </article>
      <div class="pager">\(prev)\(next)</div>
      <footer><a href="privacy.html">\(s.privacy)</a> · <a href="\(repo)/issues">\(s.support)</a> · <a href="\(repo)">\(s.license)</a> · TCommander \(version)</footer>
      </main>
    </div>
    </body></html>
    """
}

func landing(_ s: Strings, hasScreens: [String]) -> String {
    let isEN = s.lang == "en"
    let assets = isEN ? "assets/" : "../assets/"
    let docs = isEN ? "docs/en/index.html" : "../docs/cs/index.html"
    let privacyURL = isEN ? "docs/en/privacy.html" : "../docs/cs/privacy.html"
    let other = isEN ? "cs/index.html" : "../index.html"
    let canonical = isEN ? "\(siteURL)/" : "\(siteURL)/cs/"
    let alternate = isEN ? "\(siteURL)/cs/" : "\(siteURL)/"
    let download = "\(repo)/releases/latest"
    let storeButton = appStoreURL.isEmpty ? "<span class=\"btn disabled\">\(s.appStoreSoon)</span>" : "<a class=\"btn\" href=\"\(esc(appStoreURL))\">\(s.appStore)</a>"
    let features = s.features.map { "<div class=\"card\"><h3>\(esc($0.0))</h3><p>\(esc($0.1))</p></div>" }.joined(separator: "\n")
    func mark(_ v: String) -> String { v == "✓" ? "<span class=\"yes\" role=\"img\" aria-label=\"\(s.yes)\">✓</span>" : (v == "✗" ? "<span class=\"no\" role=\"img\" aria-label=\"\(s.no)\">✗</span>" : esc(v)) }
    let rows = s.editionRows.map { "<tr><th scope=\"row\">\(esc($0.0))</th><td>\(mark($0.1))</td><td>\(mark($0.2))</td><td class=\"why\">\(esc($0.3))</td></tr>" }.joined()
    let heads = s.editionHeads
    let switchCards = s.switchItems.map { "<div class=\"card\"><h3>\(esc($0.0))</h3><p>\(esc($0.1))</p></div>" }.joined(separator: "\n")
    let faq = s.faq.map { "<details><summary>\(esc($0.0))</summary><p>\(esc($0.1))</p></details>" }.joined(separator: "\n")
    func shot(_ f: String) -> String { "<a href=\"\(assets)img/\(f)\"><img src=\"\(assets)img/\(f)\" alt=\"TCommander screenshot\" loading=\"lazy\"></a>" }
    let firstShots = hasScreens.prefix(6), moreShots = hasScreens.dropFirst(6)
    let moreBlock = moreShots.isEmpty ? "" : "<details class=\"more-shots\"><summary>\(s.allScreenshots)</summary><div class=\"grid shots-grid\">" + moreShots.map(shot).joined() + "</div></details>"
    let screens = hasScreens.isEmpty ? "" : "<section class=\"shots\"><h2>\(s.screenshotsTitle)</h2><div class=\"grid shots-grid\">" + firstShots.map(shot).joined() + "</div>" + moreBlock + "</section>"
    let ld = """
    <script type="application/ld+json">{"@context":"https://schema.org","@type":"SoftwareApplication","name":"TCommander","operatingSystem":"macOS 14+","applicationCategory":"UtilitiesApplication","softwareVersion":"\(version)","description":"\(esc(s.subtitle))","offers":{"@type":"Offer","price":"0","priceCurrency":"USD"},"url":"\(canonical)"}</script>
    """
    return head(s, title: "TCommander – \(s.tagline)", description: s.subtitle, assets: assets, canonical: canonical, alternate: alternate, searchIndex: nil, extra: ld) + """
    <body class="landing">
    <header class="top"><a class="brand" href="./"><img src="\(assets)img/icon-64.png" alt="" width="28" height="28"><b>TCommander</b></a>
      <nav class="links"><a href="\(docs)">\(s.guide)</a><a href="\(repo)">GitHub</a><a class="lang" href="\(other)" hreflang="\(s.otherLanguage)">\(s.otherLanguageName)</a></nav></header>
    <section class="hero">
      <img class="appicon" src="\(assets)img/icon-512.png" alt="TCommander" width="160" height="160">
      <h1>TCommander</h1><p class="tag">\(s.tagline)</p><p class="sub">\(esc(s.subtitle))</p>
      <p class="cta"><a class="btn primary" href="\(download)">\(s.download)</a> \(storeButton) <a class="btn" href="\(docs)">\(s.readGuide)</a></p>
      <p class="small">\(s.requirements) · v\(version)</p>
    </section>
    \(screens)
    <section><h2>\(s.featuresTitle)</h2><div class="grid">\(features)</div></section>
    <section class="switch"><h2>\(s.switchTitle)</h2><div class="grid">\(switchCards)</div></section>
    <section class="editions"><h2>\(s.editionsTitle)</h2><p>\(esc(s.editionsIntro))</p>
      <div class="table-wrap"><table><thead><tr><th scope="col">\(esc(heads.0))</th><th scope="col">\(esc(heads.1))</th><th scope="col">\(esc(heads.2))</th><th scope="col">\(esc(heads.3))</th></tr></thead><tbody>\(rows)</tbody></table></div></section>
    <section class="get"><h2>\(s.downloadTitle)</h2><div class="grid two">
      <div class="card"><h3>\(esc(s.githubEditionTitle))</h3><p>\(esc(s.githubEditionText))</p><p class="cta left"><a class="btn primary" href="\(download)">\(s.download)</a></p></div>
      <div class="card"><h3>\(esc(s.storeEditionTitle))</h3><p>\(esc(s.storeEditionText))</p><p class="cta left">\(storeButton)</p></div></div></section>
    <section class="faq"><h2>\(s.faqTitle)</h2>\(faq)</section>
    <footer class="foot"><p>\(s.footerNote)</p><p><a href="\(docs)">\(s.guide)</a> · <a href="\(privacyURL)">\(s.privacy)</a> · <a href="\(repo)/issues">\(s.support)</a> · <a href="\(repo)">\(s.license)</a></p><p class="small">© 2026 Tomáš Kaplan · TCommander is an independent project and is not affiliated with Total Commander or its author.</p></footer>
    </body></html>
    """
}

func notFoundPage(_ s: Strings) -> String {
    // 404.html se zobrazuje na libovolné adrese, proto má odkazy absolutní
    let assets = siteURL + "/assets/"
    return head(s, title: "404 – TCommander", description: s.notFoundText, assets: assets, canonical: siteURL + "/404.html", alternate: siteURL + "/", searchIndex: nil) + """
    <body class="landing"><header class="top"><a class="brand" href="\(siteURL)/"><img src="\(assets)img/icon-64.png" alt="" width="28" height="28"><b>TCommander</b></a></header>
    <section class="hero"><h1>404</h1><p class="sub">\(esc(s.notFoundText))</p><p class="cta"><a class="btn primary" href="\(siteURL)/">\(s.home)</a> <a class="btn" href="\(siteURL)/docs/en/index.html">\(s.guide)</a></p></section></body></html>
    """
}

// MARK: Sestavení

try? fm.removeItem(at: out)
try? fm.createDirectory(at: out, withIntermediateDirectories: true)
var sitemap: [String] = ["\(siteURL)/", "\(siteURL)/cs/"]

for s in [Strings.en, Strings.cs] {
    var pages = loadPages(s.lang)
    guard !pages.isEmpty else { fputs("Chybí příručka \(manual.path)/\(s.lang)\n", stderr); exit(1) }
    // vygenerovaná stránka se zkratkami před „Zásady ochrany soukromí“
    let sc = shortcutsMarkdown(cs: s.lang == "cs")
    let shortcutsPage = Page(slug: "12-shortcuts", title: String(sc.split(separator: "\n").first!.dropFirst(2)), markdown: sc)
    if !pages.contains(where: { $0.slug == "12-shortcuts" }) {
        let at = pages.firstIndex { $0.slug > "12-shortcuts" && $0.slug != "privacy" } ?? pages.firstIndex { $0.slug == "privacy" } ?? pages.count
        pages.insert(shortcutsPage, at: at)
    }
    for i in pages.indices {
        pages[i].html = MarkdownHTML.render(pages[i].markdown, baseURL: nil)
        pages[i].plain = plainText(pages[i].html)
    }
    var index: [[String: String]] = []
    for (i, p) in pages.enumerated() {
        write(renderGuidePage(s, pages: pages, index: i), to: out.appendingPathComponent("docs/\(s.lang)/\(htmlFileName(p.slug))"))
        index.append(["t": p.title, "u": htmlFileName(p.slug), "x": String(p.plain.prefix(12000))])
        sitemap.append("\(siteURL)/docs/\(s.lang)/\(htmlFileName(p.slug))")
        // odkazy mezi stránkami musí vést na existující soubory
        for m in (try? NSRegularExpression(pattern: #"href="([^":#]+\.html)(?:#[^"]*)?""#))?.matches(in: p.html, range: NSRange(p.html.startIndex..., in: p.html)) ?? [] {
            let target = (p.html as NSString).substring(with: m.range(at: 1))
            if !pages.contains(where: { htmlFileName($0.slug) == target }) { warnings.append("\(s.lang)/\(p.slug): odkaz na neexistující stránku \(target)") }
        }
    }
    let json = String(decoding: (try? JSONSerialization.data(withJSONObject: index, options: [])) ?? Data("[]".utf8), as: UTF8.self)
    write("window.TC_SEARCH = \(json);\n", to: out.appendingPathComponent("docs/\(s.lang)/search-index.js"))
}

// statické soubory a úvodní stránky
let assetsOut = out.appendingPathComponent("assets")
try? fm.createDirectory(at: assetsOut, withIntermediateDirectories: true)
for f in ["style.css", "app.js"] { try? fm.copyItem(at: web.appendingPathComponent(f), to: assetsOut.appendingPathComponent(f)) }
let imgIn = web.appendingPathComponent("img"), imgOut = assetsOut.appendingPathComponent("img")
try? fm.createDirectory(at: imgOut, withIntermediateDirectories: true)
let images = ((try? fm.contentsOfDirectory(atPath: imgIn.path)) ?? []).filter { !$0.hasPrefix(".") }
for f in images { try? fm.copyItem(at: imgIn.appendingPathComponent(f), to: imgOut.appendingPathComponent(f)) }
let screens = images.filter { $0.hasPrefix("screenshot-") }.sorted()
write(landing(.en, hasScreens: screens), to: out.appendingPathComponent("index.html"))
write(landing(.cs, hasScreens: screens), to: out.appendingPathComponent("cs/index.html"))
write("", to: out.appendingPathComponent(".nojekyll"))
if !customDomain.isEmpty { write(customDomain + "\n", to: out.appendingPathComponent("CNAME")) }
write(notFoundPage(.en), to: out.appendingPathComponent("404.html"))
write("User-agent: *\nAllow: /\nSitemap: \(siteURL)/sitemap.xml\n", to: out.appendingPathComponent("robots.txt"))
write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n" + sitemap.map { "  <url><loc>\($0)</loc></url>" }.joined(separator: "\n") + "\n</urlset>\n", to: out.appendingPathComponent("sitemap.xml"))
if !appStoreURL.isEmpty { write(appStoreURL, to: out.appendingPathComponent("appstore-url.txt")) }

for w in warnings { fputs("VAROVÁNÍ: \(w)\n", stderr) }
print("Hotovo: \(out.path) (\(sitemap.count) stránek, \(images.count) obrázků, \(warnings.count) varování)")
if !warnings.isEmpty && ProcessInfo.processInfo.environment["DOCS_STRICT"] == "1" { exit(2) }
