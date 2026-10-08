import Foundation

/// Převod Markdownu (CommonMark + běžná rozšíření GitHubu: tabulky, úkoly, přeškrtnutí, ohraničený kód) na HTML pro čtečku v Listeru.
/// Surové HTML ze zdroje se neinterpretuje (escapuje se), odkazy s nebezpečným schématem (např. javascript:) se nevykreslí jako odkazy.
public enum MarkdownHTML {
    /// Jazyky ohraničených bloků kódu (```swift) podle názvu nebo přípony.
    static let fenceLanguages: [String: String] = [
        "swift": "swift", "c": "c", "h": "c", "cpp": "c", "c++": "c", "objc": "c", "objective-c": "c", "java": "java", "cs": "java", "csharp": "java",
        "kotlin": "kotlin", "kt": "kotlin", "js": "js", "javascript": "js", "jsx": "js", "ts": "js", "typescript": "js", "tsx": "js",
        "python": "python", "py": "python", "ruby": "ruby", "rb": "ruby", "sh": "shell", "bash": "shell", "zsh": "shell", "shell": "shell", "console": "shell",
        "go": "go", "golang": "go", "rust": "rust", "rs": "rust", "php": "php", "sql": "sql", "json": "json", "yaml": "yaml", "yml": "yaml",
        "toml": "toml", "ini": "toml", "css": "css", "scss": "css", "html": "markup", "xml": "markup", "svg": "markup", "plist": "markup",
        "lua": "lua", "make": "makefile", "makefile": "makefile", "plantuml": "plantuml", "puml": "plantuml", "adif": "adif", "adi": "adif",
    ]

    public static func language(forFence info: String) -> String? {
        let word = info.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init)?.lowercased() ?? ""
        return fenceLanguages[word]
    }

    /// Tělo dokumentu (bez `<html>`); `baseURL` je složka souboru pro relativní obrázky a odkazy.
    public static func render(_ source: String, baseURL: URL? = nil) -> String {
        let text = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\t", with: "    ")
        var parser = Parser(base: baseURL)
        return parser.blocks(text.components(separatedBy: "\n"), tight: false)
    }

    /// Celá stránka s CSS (světlý i tmavý vzhled).
    public static func page(_ source: String, baseURL: URL? = nil, title: String = "") -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark">
        <title>\(escape(title))</title><style>\(css)</style></head><body><article>\(render(source, baseURL: baseURL))</article></body></html>
        """
    }

    public static func escape(_ s: String) -> String {
        var out = ""; out.reserveCapacity(s.count)
        for c in s { switch c { case "&": out += "&amp;"; case "<": out += "&lt;"; case ">": out += "&gt;"; case "\"": out += "&quot;"; default: out.append(c) } }
        return out
    }

    static let css = """
    :root{color-scheme:light dark;--fg:#1f2328;--bg:#fff;--muted:#59636e;--border:#d1d9e0;--code:#f6f8fa;--link:#0969da;--quote:#d1d9e0;
      --k:#ad2390;--s:#c41a16;--c:#6c7986;--n:#1c00cf;--t:#1c6e7f;--p:#643820;--g:#216e87;--a:#745a00}
    @media (prefers-color-scheme:dark){:root{--fg:#e6edf3;--bg:#1e1e1e;--muted:#9198a1;--border:#3d444d;--code:#2a2d31;--link:#4493f8;--quote:#3d444d;
      --k:#fc5fa3;--s:#fc6a5d;--c:#7f8c98;--n:#d0bf69;--t:#5dd8ff;--p:#fd8f3f;--g:#5dd8ff;--a:#cdb067}}
    html{background:var(--bg)}body{margin:0;color:var(--fg);font:15px/1.6 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
    article{max-width:860px;margin:0 auto;padding:24px 32px 64px}
    h1,h2{padding-bottom:.3em;border-bottom:1px solid var(--border)}h1,h2,h3,h4,h5,h6{margin:1.4em 0 .6em;line-height:1.25}h1{font-size:2em}h2{font-size:1.5em}h3{font-size:1.25em}
    h6{color:var(--muted)}p,ul,ol,pre,table,blockquote{margin:0 0 1em}a{color:var(--link);text-decoration:none}a:hover{text-decoration:underline}
    code{font:13px ui-monospace,Menlo,monospace;background:var(--code);padding:.15em .35em;border-radius:5px}
    pre{background:var(--code);padding:14px 16px;border-radius:8px;overflow:auto;line-height:1.45}pre code{background:none;padding:0;font-size:13px}
    blockquote{margin-left:0;padding:0 1em;color:var(--muted);border-left:.25em solid var(--quote)}hr{border:0;border-top:1px solid var(--border);margin:1.6em 0}
    table{border-collapse:collapse;display:block;overflow:auto}th,td{border:1px solid var(--border);padding:6px 13px}th{background:var(--code)}tr:nth-child(2n) td{background:color-mix(in srgb,var(--code) 50%,transparent)}
    img{max-width:100%}li>p{margin:0 0 .4em}ul.tasks{list-style:none;padding-left:1.2em}input[type=checkbox]{margin-right:.5em}
    .k{color:var(--k);font-weight:600}.s{color:var(--s)}.c{color:var(--c)}.n{color:var(--n)}.t{color:var(--t)}.p{color:var(--p)}.g{color:var(--g)}.a{color:var(--a)}
    """

    // MARK: Blokový parser

    struct Parser {
        let base: URL?

        // MARK: pomocné
        static func isBlank(_ s: String) -> Bool { s.allSatisfy { $0 == " " } }
        static func leadingSpaces(_ s: String) -> Int { s.prefix { $0 == " " }.count }

        static func fence(_ line: String) -> (char: Character, count: Int, info: String, indent: Int)? {
            let indent = leadingSpaces(line)
            guard indent < 4 else { return nil }
            let rest = line.dropFirst(indent)
            guard let c = rest.first, c == "`" || c == "~" else { return nil }
            let n = rest.prefix { $0 == c }.count
            guard n >= 3 else { return nil }
            let info = String(rest.dropFirst(n)).trimmingCharacters(in: .whitespaces)
            if c == "`" && info.contains("`") { return nil }
            return (c, n, info, indent)
        }

        static func atx(_ line: String) -> (Int, String)? {
            guard leadingSpaces(line) < 4 else { return nil }
            let t = line.drop { $0 == " " }
            let hashes = t.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes) else { return nil }
            let rest = t.dropFirst(hashes)
            guard rest.isEmpty || rest.first == " " else { return nil }
            var text = rest.trimmingCharacters(in: .whitespaces)
            while text.hasSuffix("#") { text.removeLast() }
            if text.isEmpty || text.hasSuffix(" ") || !rest.contains("#") { text = text.trimmingCharacters(in: .whitespaces) }
            return (hashes, text.trimmingCharacters(in: .whitespaces))
        }

        static func isHR(_ line: String) -> Bool {
            guard leadingSpaces(line) < 4 else { return false }
            let t = line.filter { $0 != " " }
            guard t.count >= 3, let c = t.first, "-*_".contains(c) else { return false }
            return t.allSatisfy { $0 == c }
        }

        /// Značka položky seznamu: (odsazení, šířka značky včetně mezery, uspořádaný?, počáteční číslo).
        static func listMarker(_ line: String) -> (indent: Int, width: Int, ordered: Bool, start: Int, delim: Character)? {
            let indent = leadingSpaces(line)
            guard indent < 4 else { return nil }
            let rest = line.dropFirst(indent)
            if let c = rest.first, "-*+".contains(c), rest.dropFirst().first == " " || rest.dropFirst().isEmpty {
                if isHR(line) { return nil }
                return (indent, 2, false, 1, c)
            }
            let digits = rest.prefix { $0.isNumber && $0.isASCII }
            if (1...9).contains(digits.count), let d = rest.dropFirst(digits.count).first, d == "." || d == ")",
               rest.dropFirst(digits.count + 1).first == " " || rest.dropFirst(digits.count + 1).isEmpty {
                return (indent, digits.count + 2, true, Int(digits) ?? 1, d)
            }
            return nil
        }

        static func startsBlock(_ line: String) -> Bool {
            fence(line) != nil || atx(line) != nil || isHR(line) || line.drop { $0 == " " }.hasPrefix(">") || listMarker(line) != nil
        }

        static func tableCells(_ line: String) -> [String] {
            var t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
            var cells: [String] = [], cur = "", prev: Character = " "
            for c in t {
                if c == "|" && prev != "\\" { cells.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" } else { cur.append(c) }
                prev = c
            }
            cells.append(cur.trimmingCharacters(in: .whitespaces))
            return cells.map { $0.replacingOccurrences(of: "\\|", with: "|") }
        }

        static func tableAlignments(_ line: String) -> [String]? {
            guard line.contains("-") else { return nil }
            let cells = tableCells(line)
            var out: [String] = []
            for c in cells {
                guard !c.isEmpty, c.allSatisfy({ $0 == "-" || $0 == ":" }), c.contains("-") else { return nil }
                out.append(c.hasPrefix(":") && c.hasSuffix(":") ? "center" : c.hasSuffix(":") ? "right" : c.hasPrefix(":") ? "left" : "")
            }
            return out
        }

        /// Identifikátor nadpisu: malá písmena a číslice, mezery a pomlčky jako „-“, bez diakritiky (aby fungovaly odkazy #hromadne-prejmenovani).
        static func slug(_ text: String) -> String { slugify(text.folding(options: .diacriticInsensitive, locale: nil)) }

        /// Varianta s diakritikou (jako na GitHubu); liší-li se od `slug`, přidá se k nadpisu jako druhá kotva.
        static func unicodeSlug(_ text: String) -> String { slugify(text) }

        private static func slugify(_ text: String) -> String {
            var s = ""
            for c in text.lowercased() { if c.isLetter || c.isNumber { s.append(c) } else if c == " " || c == "-" { s.append("-") } }
            return s
        }

        /// Otevírací značka nadpisu včetně kotev.
        func headingOpen(_ level: Int, _ text: String) -> String {
            let a = Self.slug(text), b = Self.unicodeSlug(text)
            return "<h\(level) id=\"\(a)\">" + (a != b ? "<a id=\"\(MarkdownHTML.escape(b))\"></a>" : "")
        }

        // MARK: bloky

        mutating func blocks(_ lines: [String], tight: Bool) -> String {
            var out = ""
            var i = 0
            while i < lines.count {
                let line = lines[i]
                if Self.isBlank(line) { i += 1; continue }

                if let f = Self.fence(line) {                                              // ohraničený kód
                    var body: [String] = []; i += 1
                    while i < lines.count {
                        let l = lines[i]
                        if let e = Self.fence(l), e.char == f.char, e.count >= f.count, e.info.isEmpty { i += 1; break }
                        body.append(String(l.dropFirst(min(f.indent, Self.leadingSpaces(l))))); i += 1
                    }
                    out += codeBlock(body.joined(separator: "\n"), info: f.info)
                    continue
                }
                if let (level, text) = Self.atx(line) {
                    out += headingOpen(level, text) + "\(inline(text))</h\(level)>\n"; i += 1; continue
                }
                if Self.isHR(line) { out += "<hr>\n"; i += 1; continue }

                if line.drop(while: { $0 == " " }).hasPrefix(">") {                       // citace
                    var inner: [String] = []
                    while i < lines.count, !Self.isBlank(lines[i]) {
                        let l = lines[i]
                        if l.drop(while: { $0 == " " }).hasPrefix(">") {
                            var r = l.drop { $0 == " " }.dropFirst()
                            if r.first == " " { r = r.dropFirst() }
                            inner.append(String(r))
                        } else if Self.startsBlock(l) { break } else { inner.append(l) }
                        i += 1
                    }
                    out += "<blockquote>\n\(blocks(inner, tight: false))</blockquote>\n"
                    continue
                }
                if Self.listMarker(line) != nil { out += list(lines, &i); continue }

                if i + 1 < lines.count, line.contains("|"), let aligns = Self.tableAlignments(lines[i + 1]), Self.tableCells(line).count == aligns.count {   // tabulka
                    let head = Self.tableCells(line)
                    var rows: [[String]] = []; i += 2
                    while i < lines.count, !Self.isBlank(lines[i]), lines[i].contains("|"), !Self.startsBlock(lines[i]) { rows.append(Self.tableCells(lines[i])); i += 1 }
                    func cell(_ tag: String, _ text: String, _ idx: Int) -> String {
                        let a = idx < aligns.count && !aligns[idx].isEmpty ? " style=\"text-align:\(aligns[idx])\"" : ""
                        return "<\(tag)\(a)>\(inline(text))</\(tag)>"
                    }
                    out += "<table><thead><tr>" + head.enumerated().map { cell("th", $0.element, $0.offset) }.joined() + "</tr></thead><tbody>\n"
                    for r in rows { out += "<tr>" + (0..<aligns.count).map { cell("td", $0 < r.count ? r[$0] : "", $0) }.joined() + "</tr>\n" }
                    out += "</tbody></table>\n"
                    continue
                }
                if Self.leadingSpaces(line) >= 4 {                                         // odsazený kód
                    var body: [String] = []
                    while i < lines.count, Self.isBlank(lines[i]) || Self.leadingSpaces(lines[i]) >= 4 { body.append(String(lines[i].dropFirst(min(4, lines[i].count)))); i += 1 }
                    while body.last.map(Self.isBlank) == true { body.removeLast() }
                    out += codeBlock(body.joined(separator: "\n"), info: "")
                    continue
                }

                var para: [String] = [line]; i += 1                                          // odstavec (případně nadpis podtržením)
                var setext = 0
                while i < lines.count, !Self.isBlank(lines[i]) {
                    let l = lines[i]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty, t.allSatisfy({ $0 == "=" }) { setext = 1; i += 1; break }
                    if !t.isEmpty, t.allSatisfy({ $0 == "-" }), Self.leadingSpaces(l) < 4 { setext = 2; i += 1; break }
                    if Self.startsBlock(l) && Self.listMarker(l)?.ordered != true || Self.fence(l) != nil { break }
                    if let m = Self.listMarker(l), m.ordered, m.start != 1 { para.append(l); i += 1; continue }
                    if Self.listMarker(l) != nil { break }
                    para.append(l); i += 1
                }
                let text = para.enumerated().map { idx, l -> String in
                    let lead = String(l.drop { $0 == " " })
                    let trailing = lead.count - lead.reversed().drop { $0 == " " }.count
                    let core = lead.trimmingCharacters(in: .init(charactersIn: " "))
                    return trailing >= 2 && idx < para.count - 1 ? core + "  " : core
                }.joined(separator: "\n")
                if setext > 0 { out += headingOpen(setext, text) + "\(inline(text))</h\(setext)>\n" }
                else if tight { out += inline(text) + "\n" } else { out += "<p>\(inline(text))</p>\n" }
            }
            return out
        }

        mutating func codeBlock(_ code: String, info: String) -> String {
            let cls = info.isEmpty ? "" : " class=\"language-\(MarkdownHTML.escape(info.split(separator: " ").first.map(String.init) ?? ""))\""
            guard let lang = MarkdownHTML.language(forFence: info), code.utf16.count < 200_000 else { return "<pre><code\(cls)>\(MarkdownHTML.escape(code))</code></pre>\n" }
            let ns = code as NSString
            var html = "", pos = 0
            let classes: [SyntaxKind: String] = [.keyword: "k", .string: "s", .comment: "c", .number: "n", .type: "t", .preprocessor: "p", .tag: "g", .attribute: "a"]
            for t in SyntaxHighlighter.tokens(in: code, language: lang) where t.range.location >= pos {
                html += MarkdownHTML.escape(ns.substring(with: NSRange(location: pos, length: t.range.location - pos)))
                html += "<span class=\"\(classes[t.kind] ?? "")\">\(MarkdownHTML.escape(ns.substring(with: t.range)))</span>"
                pos = NSMaxRange(t.range)
            }
            html += MarkdownHTML.escape(ns.substring(from: pos))
            return "<pre><code\(cls)>\(html)</code></pre>\n"
        }

        mutating func list(_ lines: [String], _ i: inout Int) -> String {
            guard let first = Self.listMarker(lines[i]) else { return "" }
            var items: [[String]] = []
            var tight = true
            var sawBlankBetween = false
            while i < lines.count, let m = Self.listMarker(lines[i]), m.ordered == first.ordered, m.delim == first.delim {
                let content = m.indent + m.width
                var item = [String(lines[i].dropFirst(min(content, lines[i].count)))]
                i += 1
                var pendingBlank = 0
                while i < lines.count {
                    let l = lines[i]
                    if Self.isBlank(l) { pendingBlank += 1; i += 1; continue }
                    let indent = Self.leadingSpaces(l)
                    if indent >= content { item.append(contentsOf: Array(repeating: "", count: pendingBlank)); pendingBlank = 0; item.append(String(l.dropFirst(content))); i += 1; continue }
                    if pendingBlank == 0, Self.listMarker(l) == nil, !Self.startsBlock(l) { item.append(l.trimmingCharacters(in: .init(charactersIn: " "))); i += 1; continue }   // líné pokračování
                    break
                }
                if pendingBlank > 0, i < lines.count, let n = Self.listMarker(lines[i]), n.ordered == first.ordered, n.delim == first.delim { sawBlankBetween = true }
                else if pendingBlank > 0 { i -= 0 }
                items.append(item)
            }
            if sawBlankBetween { tight = false }
            if items.contains(where: { $0.contains { Self.isBlank($0) } && $0.count > 1 && $0.dropLast().contains { Self.isBlank($0) } }) { tight = false }
            let hasTasks = items.contains { $0.first.map { $0.hasPrefix("[ ] ") || $0.hasPrefix("[x] ") || $0.hasPrefix("[X] ") } ?? false }
            let tag = first.ordered ? "ol" : "ul"
            let startAttr = first.ordered && first.start != 1 ? " start=\"\(first.start)\"" : ""
            var out = "<\(tag)\(startAttr)\(hasTasks ? " class=\"tasks\"" : "")>\n"
            for var item in items {
                var checkbox = ""
                if let f = item.first {
                    if f.hasPrefix("[ ] ") { checkbox = "<input type=\"checkbox\" disabled> "; item[0] = String(f.dropFirst(4)) }
                    else if f.hasPrefix("[x] ") || f.hasPrefix("[X] ") { checkbox = "<input type=\"checkbox\" checked disabled> "; item[0] = String(f.dropFirst(4)) }
                }
                out += "<li>" + checkbox + blocks(item, tight: tight).trimmingCharacters(in: .newlines) + "</li>\n"
            }
            return out + "</\(tag)>\n"
        }

        // MARK: inline

        func resolve(_ url: String, isImage: Bool) -> String? {
            let u = url.trimmingCharacters(in: .whitespaces)
            if u.isEmpty { return "" }
            if u.hasPrefix("#") { return u }
            if let r = u.range(of: ":"), !u[..<r.lowerBound].contains("/") {
                let scheme = u[..<r.lowerBound].lowercased()
                return ["http", "https", "mailto"].contains(scheme) && !(isImage && scheme == "mailto") ? u : nil
            }
            guard let base else { return u }
            let path = u.removingPercentEncoding ?? u
            return URL(fileURLWithPath: path, relativeTo: base).standardized.absoluteString
        }

        /// Rozdělí „url "titulek"“ na adresu a titulek.
        static func splitDestination(_ s: String) -> (String, String?) {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("<"), let end = t.firstIndex(of: ">") { let u = String(t[t.index(after: t.startIndex)..<end]); t = String(t[t.index(after: end)...]).trimmingCharacters(in: .whitespaces); return (u, title(t)) }
            if let q = t.firstIndex(where: { $0 == " " }) { return (String(t[..<q]), title(String(t[q...]).trimmingCharacters(in: .whitespaces))) }
            return (t, nil)
        }
        static func title(_ t: String) -> String? {
            guard t.count >= 2, let f = t.first, let l = t.last, (f == "\"" && l == "\"") || (f == "'" && l == "'") || (f == "(" && l == ")") else { return nil }
            return String(t.dropFirst().dropLast())
        }

        /// Konec zdůraznění: první běh `ch` délky ≥ d (u jednoduchého jen délky 1) za neprázdným obsahem a mimo kód; nikdy po mezeře.
        func closingDelimiter(_ c: [Character], _ ch: Character, _ d: Int, from: Int, opener: Int) -> Int? {
            var k = from
            while k < c.count {
                if c[k] == "\\" { k += 2; continue }
                if c[k] == "`" {
                    var n = 1; while k + n < c.count, c[k + n] == "`" { n += 1 }
                    var j = k + n, found = false
                    while j < c.count { if c[j] == "`" { var m = 0; while j + m < c.count, c[j + m] == "`" { m += 1 }; if m == n { k = j + m; found = true; break }; j += m } else { j += 1 } }
                    if found { continue }
                    k += n; continue
                }
                if c[k] == ch {
                    var r = 1; while k + r < c.count, c[k + r] == ch { r += 1 }
                    let validRun = d == 1 ? r == 1 : r >= d
                    if validRun, k > from, !c[k - 1].isWhitespace {
                        let next: Character? = k + d < c.count ? c[k + d] : nil
                        if !(ch == "_" && (next.map { $0.isLetter || $0.isNumber } ?? false)) { return k }
                    }
                    k += r; continue
                }
                k += 1
            }
            return nil
        }

        func inline(_ text: String) -> String {
            let c = Array(text)
            var out = ""
            var i = 0
            func isAlnum(_ ch: Character?) -> Bool { ch.map { $0.isLetter || $0.isNumber } ?? false }
            func findRun(_ n: Int, from: Int) -> Int? {
                var k = from
                while k < c.count {
                    if c[k] == "`" { var run = 0; while k + run < c.count, c[k + run] == "`" { run += 1 }; if run == n { return k }; k += run } else { k += 1 }
                }
                return nil
            }
            /// Najde konec hranatých závorek s vnořením od `open` (ukazuje za „[“).
            func closingBracket(from open: Int) -> Int? {
                var depth = 1, k = open
                while k < c.count {
                    if c[k] == "\\" { k += 2; continue }
                    if c[k] == "`", let close = findRun(1, from: k + 1) { k = close + 1; continue }
                    if c[k] == "[" { depth += 1 } else if c[k] == "]" { depth -= 1; if depth == 0 { return k } }
                    k += 1
                }
                return nil
            }
            func closingParen(from open: Int) -> Int? {
                var depth = 1, k = open
                while k < c.count {
                    if c[k] == "\\" { k += 2; continue }
                    if c[k] == "(" { depth += 1 } else if c[k] == ")" { depth -= 1; if depth == 0 { return k } }
                    k += 1
                }
                return nil
            }

            while i < c.count {
                let ch = c[i]
                if ch == "\\", i + 1 < c.count {
                    if c[i + 1] == "\n" { out += "<br>\n"; i += 2; continue }
                    if "\\`*_{}[]()#+-.!|~<>\"'&".contains(c[i + 1]) { out += MarkdownHTML.escape(String(c[i + 1])); i += 2; continue }
                }
                if ch == "`" {
                    var run = 1; while i + run < c.count, c[i + run] == "`" { run += 1 }
                    if let close = findRun(run, from: i + run) {
                        var code = String(c[(i + run)..<close]).replacingOccurrences(of: "\n", with: " ")
                        if code.hasPrefix(" "), code.hasSuffix(" "), code.trimmingCharacters(in: .whitespaces).count > 0 { code = String(code.dropFirst().dropLast()) }
                        out += "<code>\(MarkdownHTML.escape(code))</code>"; i = close + run; continue
                    }
                    out += String(repeating: "`", count: run); i += run; continue
                }
                if ch == "!" || ch == "[" {                                                   // obrázek / odkaz
                    let isImage = ch == "!" && i + 1 < c.count && c[i + 1] == "["
                    let open = isImage ? i + 2 : i + 1
                    if (ch == "[" || isImage), let close = closingBracket(from: open), close + 1 < c.count, c[close + 1] == "(", let end = closingParen(from: close + 2) {
                        let label = String(c[open..<close])
                        let (dest, title) = Self.splitDestination(String(c[(close + 2)..<end]))
                        let titleAttr = title.map { " title=\"\(MarkdownHTML.escape($0))\"" } ?? ""
                        if let url = resolve(dest, isImage: isImage) {
                            if isImage { out += "<img src=\"\(MarkdownHTML.escape(url))\" alt=\"\(MarkdownHTML.escape(label))\"\(titleAttr)>" }
                            else { out += "<a href=\"\(MarkdownHTML.escape(url))\"\(titleAttr)>\(inline(label))</a>" }
                        } else { out += inline(label) }
                        i = end + 1; continue
                    }
                }
                if ch == "<", let end = c[i...].firstIndex(of: ">") {                           // <https://…> a <mail@…>
                    let inner = String(c[(i + 1)..<end])
                    if inner.range(of: #"^(https?://|mailto:)[^\s<>]+$"#, options: .regularExpression) != nil {
                        out += "<a href=\"\(MarkdownHTML.escape(inner))\">\(MarkdownHTML.escape(inner))</a>"; i = end + 1; continue
                    }
                    if inner.range(of: #"^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$"#, options: .regularExpression) != nil {
                        out += "<a href=\"mailto:\(MarkdownHTML.escape(inner))\">\(MarkdownHTML.escape(inner))</a>"; i = end + 1; continue
                    }
                }
                if (ch == "h"), i == 0 || !isAlnum(c[i - 1]), text[text.index(text.startIndex, offsetBy: i)...].hasPrefix("http://") || text[text.index(text.startIndex, offsetBy: i)...].hasPrefix("https://") {
                    var end = i; while end < c.count, !c[end].isWhitespace, c[end] != "<" { end += 1 }
                    while end > i, ".,;:!?)\"'".contains(c[end - 1]) { end -= 1 }
                    let url = String(c[i..<end])
                    out += "<a href=\"\(MarkdownHTML.escape(url))\">\(MarkdownHTML.escape(url))</a>"; i = end; continue
                }
                if ch == "*" || ch == "_" || ch == "~" {                                      // zdůraznění
                    var run = 1; while i + run < c.count, c[i + run] == ch { run += 1 }
                    let prevAlnum = i > 0 && isAlnum(c[i - 1])
                    let canOpen = i + run < c.count && !c[i + run].isWhitespace && !(ch == "_" && prevAlnum) && !(ch == "~" && run < 2)
                    var matched = false
                    if canOpen {
                        for d in (ch == "~" ? [2] : Array((1...min(run, 3)).reversed())) {
                            guard let close = closingDelimiter(c, ch, d, from: i + d, opener: i) else { continue }
                            let inner = inline(String(c[(i + d)..<close]))
                            switch (ch, d) {
                            case ("~", _): out += "<del>\(inner)</del>"
                            case (_, 1): out += "<em>\(inner)</em>"
                            case (_, 2): out += "<strong>\(inner)</strong>"
                            default: out += "<strong><em>\(inner)</em></strong>"
                            }
                            i = close + d; matched = true; break
                        }
                    }
                    if !matched { out += String(repeating: String(ch), count: run); i += run }
                    continue
                }
                if ch == " ", i + 2 < c.count, c[i + 1] == " ", c[i + 2] == "\n" { out += "<br>\n"; i += 3; continue }
                if ch == "&" {
                    if let semi = c[i...].firstIndex(of: ";"), semi - i <= 10, String(c[i...semi]).range(of: #"^&(#[0-9]+|#x[0-9a-fA-F]+|[A-Za-z0-9]+);$"#, options: .regularExpression) != nil {
                        out += String(c[i...semi]); i = semi + 1; continue
                    }
                }
                out += MarkdownHTML.escape(String(ch)); i += 1
            }
            return out
        }

    }
}
