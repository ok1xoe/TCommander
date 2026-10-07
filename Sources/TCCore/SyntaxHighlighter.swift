import Foundation

public enum SyntaxKind: Sendable { case keyword, string, comment, number, type, preprocessor, tag, attribute }

public struct SyntaxToken: Equatable, Sendable {
    public let range: NSRange            // v jednotkách UTF-16 (kompatibilní s NSString/NSTextStorage)
    public let kind: SyntaxKind
}

/// Jednoduché zvýrazňování syntaxe pro běžné programovací a značkovací jazyky (bez závislostí, jedním průchodem).
public enum SyntaxHighlighter {
    struct Config {
        var lineComments: [String] = []
        var blockComment: (String, String)? = nil
        var quotes: [Character] = ["\"", "'"]
        var tripleQuotes = false
        var keywords: Set<String> = []
        var typesCapitalized = false
        var preprocessor = false          // řádky začínající #
        var markup = false                // HTML/XML
        var caseInsensitiveKeywords = false
        var backtickStrings = false
        var yaml = false                  // klíče, kotvy, značky, oddělovače dokumentů
        var arrows = false                // šipky ->, -->, ..>, <|-- (PlantUML)
        var directivePrefixes: [UInt16] = []   // řádky začínající těmito znaky (např. @startuml, !include)
        var commentNeedsBlankBefore = false    // komentář jen na začátku řádku nebo za mezerou (YAML)
        var commentOnlyAtLineStart = false     // komentář jen jako první znak řádku (PlantUML)
    }

    private static func kw(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }

    private static let cLike = "if else for while do switch case default break continue return goto sizeof typedef struct union enum static const extern volatile inline void int long short char float double unsigned signed auto register true false NULL nullptr class public private protected virtual namespace template typename using new delete this try catch throw operator bool"
    private static let configs: [String: Config] = [
        "swift": Config(lineComments: ["//"], blockComment: ("/*", "*/"), tripleQuotes: true, keywords: kw("import class struct enum protocol extension func var let if else guard switch case default for while repeat return break continue in is as try catch throw throws rethrows defer do init deinit self Self super nil true false public private fileprivate internal open static final override mutating nonmutating lazy weak unowned async await actor where typealias associatedtype some any inout subscript get set willSet didSet @MainActor"), typesCapitalized: true),
        "c": Config(lineComments: ["//"], blockComment: ("/*", "*/"), keywords: kw(cLike), typesCapitalized: false, preprocessor: true),
        "java": Config(lineComments: ["//"], blockComment: ("/*", "*/"), keywords: kw("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false null var record sealed permits yield"), typesCapitalized: true),
        "kotlin": Config(lineComments: ["//"], blockComment: ("/*", "*/"), tripleQuotes: true, keywords: kw("package import class interface object fun val var if else when for while do return break continue in is as try catch finally throw null true false this super override open abstract final sealed data enum companion init constructor private public protected internal suspend inline lateinit by typealias"), typesCapitalized: true),
        "js": Config(lineComments: ["//"], blockComment: ("/*", "*/"), keywords: kw("function var let const if else for while do switch case default break continue return new delete typeof instanceof in of this class extends super import export from as async await yield try catch finally throw null undefined true false void static get set interface type enum implements public private protected readonly abstract namespace declare"), typesCapitalized: true, backtickStrings: true),
        "python": Config(lineComments: ["#"], tripleQuotes: true, keywords: kw("and as assert async await break class continue def del elif else except finally for from global if import in is lambda None nonlocal not or pass raise return try while with yield True False self match case"), typesCapitalized: true),
        "ruby": Config(lineComments: ["#"], blockComment: ("=begin", "=end"), keywords: kw("alias and begin break case class def defined? do else elsif end ensure false for if in module next nil not or redo rescue retry return self super then true undef unless until when while yield require require_relative attr_accessor attr_reader attr_writer puts"), typesCapitalized: true),
        "shell": Config(lineComments: ["#"], keywords: kw("if then else elif fi for while until do done case esac in function select return exit break continue local export readonly declare unset set shift source alias echo cd test true false"), backtickStrings: true),
        "go": Config(lineComments: ["//"], blockComment: ("/*", "*/"), quotes: ["\"", "'"], keywords: kw("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var nil true false iota make new len cap append"), typesCapitalized: true, backtickStrings: true),
        "rust": Config(lineComments: ["//"], blockComment: ("/*", "*/"), keywords: kw("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while macro_rules"), typesCapitalized: true),
        "php": Config(lineComments: ["//", "#"], blockComment: ("/*", "*/"), keywords: kw("abstract and array as break case catch class clone const continue declare default do echo else elseif empty enddeclare endfor endforeach endif endswitch endwhile extends final finally fn for foreach function global if implements include include_once instanceof interface isset list match namespace new null or print private protected public require require_once return static switch throw trait try unset use var while yield true false"), typesCapitalized: true),
        "sql": Config(lineComments: ["--", "#"], blockComment: ("/*", "*/"), quotes: ["'", "\""], keywords: kw("select from where and or not in is null like ilike between join inner left right outer full cross natural on using group by order having limit offset fetch first next rows only top insert into values update set delete truncate merge create table temporary temp alter add column drop rename to index unique view materialized schema database sequence trigger procedure function returns return language begin end declare if then else elsif elseif case when loop while for each execute exec call commit rollback savepoint transaction start primary key foreign references check default constraint cascade restrict distinct all any some exists union intersect except as asc desc nulls with recursive over partition window rank row_number count sum avg min max coalesce nullif cast convert grant revoke to explain analyze vacuum pragma show use describe replace returning conflict do nothing auto_increment identity serial engine charset collate if int integer bigint smallint tinyint decimal numeric float double real boolean bool bit char varchar nvarchar text clob blob date time timestamp datetime interval json jsonb uuid bytea true false"), caseInsensitiveKeywords: true, backtickStrings: true),
        "json": Config(quotes: ["\""], keywords: kw("true false null")),
        "yaml": Config(lineComments: ["#"], keywords: kw("true false null True False Null TRUE FALSE NULL"), yaml: true, commentNeedsBlankBefore: true),
        "plantuml": Config(lineComments: ["'"], blockComment: ("/'", "'/"), quotes: ["\""], keywords: kw("participant actor boundary control entity database collections queue class interface abstract enum annotation package namespace node cloud frame folder rectangle component usecase state object map note end of over left right top bottom as title legend header footer caption skinparam hide show remove restore if then else elseif endif while endwhile repeat fork again start stop detach partition group alt opt loop par break critical ref activate deactivate destroy create return autonumber newpage together box endbox is extends implements static split kill label goto switch case endswitch backward do not mainframe sprite scale rotate direction to"), caseInsensitiveKeywords: true, arrows: true, directivePrefixes: [64, 33], commentOnlyAtLineStart: true),
        "toml": Config(lineComments: ["#"], tripleQuotes: true, keywords: kw("true false")),
        "css": Config(blockComment: ("/*", "*/"), keywords: kw("important inherit initial none auto")),
        "markup": Config(blockComment: ("<!--", "-->"), markup: true),
        "lua": Config(lineComments: ["--"], blockComment: ("--[[", "]]"), keywords: kw("and break do else elseif end false for function goto if in local nil not or repeat return then true until while")),
        "makefile": Config(lineComments: ["#"], keywords: kw("ifeq ifneq ifdef ifndef else endif include define endef export")),
    ]

    private static let extensions: [String: String] = [
        "swift": "swift", "c": "c", "h": "c", "m": "c", "mm": "c", "cc": "c", "cpp": "c", "cxx": "c", "hpp": "c", "hh": "c", "cs": "java", "java": "java",
        "kt": "kotlin", "kts": "kotlin", "js": "js", "mjs": "js", "cjs": "js", "jsx": "js", "ts": "js", "tsx": "js", "py": "python", "rb": "ruby",
        "sh": "shell", "bash": "shell", "zsh": "shell", "command": "shell", "go": "go", "rs": "rust", "php": "php", "sql": "sql", "pls": "sql", "plsql": "sql", "psql": "sql", "pgsql": "sql", "mysql": "sql", "tsql": "sql", "ddl": "sql", "dml": "sql", "hql": "sql", "sqlite": "sql", "json": "json",
        "yml": "yaml", "yaml": "yaml", "sls": "yaml", "md": "markdown", "markdown": "markdown", "mdown": "markdown", "mkd": "markdown", "puml": "plantuml", "plantuml": "plantuml", "pu": "plantuml", "wsd": "plantuml", "iuml": "plantuml", "adi": "adif", "adif": "adif", "toml": "toml", "ini": "toml", "css": "css", "scss": "css", "html": "markup", "htm": "markup", "xml": "markup",
        "plist": "markup", "svg": "markup", "xhtml": "markup", "lua": "lua", "mk": "makefile",
    ]

    /// Jazyk podle přípony nebo názvu souboru (Makefile); nil, pokud soubor nevypadá jako zdrojový kód.
    public static func language(forFileName name: String) -> String? {
        let lower = name.lowercased()
        if lower == "makefile" || lower == "gnumakefile" { return "makefile" }
        if lower == "dockerfile" { return "shell" }
        guard let dot = lower.lastIndex(of: "."), dot != lower.startIndex else { return nil }
        return extensions[String(lower[lower.index(after: dot)...])]
    }

    /// Markdown: nadpisy, ohraničený kód (u známého jazyka obarvený jeho zvýrazněním), citace, položky seznamů, kód v řádku, zdůraznění, odkazy a tabulky.
    static func markdownTokens(in text: String) -> [SyntaxToken] {
        let ns = text as NSString
        var out: [SyntaxToken] = []
        func add(_ r: NSRange, _ k: SyntaxKind) { if r.length > 0 { out.append(SyntaxToken(range: r, kind: k)) } }
        var fence: (char: unichar, count: Int, language: String?, contentStart: Int)?
        func finishFence(upTo end: Int) {
            guard let f = fence else { return }
            if end > f.contentStart {
                let range = NSRange(location: f.contentStart, length: end - f.contentStart)
                if let lang = f.language, lang != "markdown" {
                    for t in tokens(in: ns.substring(with: range), language: lang) {
                        add(NSRange(location: t.range.location + range.location, length: t.range.length), t.kind)
                    }
                } else { add(range, .string) }
            }
            fence = nil
        }
        let inlinePatterns: [(NSRegularExpression, SyntaxKind, Int)] = [
            (try! NSRegularExpression(pattern: #"(`+)(?:(?!\1).)+?\1"#), .string, 0),                                  // kód v řádku
            (try! NSRegularExpression(pattern: #"!?\[([^\]]*)\]\(([^)\s]*)(?:\s+"[^"]*")?\)"#), .tag, 1),                // odkaz / obrázek: text
            (try! NSRegularExpression(pattern: #"<(?:https?://|mailto:)[^>\s]+>"#), .string, 0),                      // <url>
            (try! NSRegularExpression(pattern: #"\*\*\*[^*\s](?:[^*]*[^*\s])?\*\*\*|\*\*[^*\s](?:[^*]*[^*\s])?\*\*|(?<![\w_])__[^_\s](?:[^_]*[^_\s])?__(?![\w_])"#), .keyword, 0),   // tučné
            (try! NSRegularExpression(pattern: #"(?<![\w*])\*[^*\s](?:[^*]*[^*\s])?\*(?![\w*])|(?<![\w_])_[^_\s](?:[^_]*[^_\s])?_(?![\w_])"#), .type, 0),   // kurzíva
            (try! NSRegularExpression(pattern: #"~~[^~\s](?:[^~]*[^~\s])?~~"#), .comment, 0),                         // přeškrtnuté
            (try! NSRegularExpression(pattern: #"</?[A-Za-z][A-Za-z0-9-]*(?:\s[^>]*)?/?>"#), .tag, 0),                 // HTML značky
        ]
        let listRE = try! NSRegularExpression(pattern: #"^(\s*)([-*+]|\d{1,9}[.)])(\s+)"#)
        let headingRE = try! NSRegularExpression(pattern: #"^ {0,3}#{1,6}(\s|$)"#)
        let quoteRE = try! NSRegularExpression(pattern: #"^(\s*>\s?)+"#)
        let tableSepRE = try! NSRegularExpression(pattern: #"^\s*\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$"#)
        var pos = 0
        while pos < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: pos, length: 0))
            var content = lineRange
            while content.length > 0, [10, 13].contains(ns.character(at: content.location + content.length - 1)) { content.length -= 1 }
            let line = ns.substring(with: content)
            defer { pos = NSMaxRange(lineRange) }

            // ohraničený kód
            let trimmed = line.drop { $0 == " " }
            if line.count - trimmed.count < 4, let c = trimmed.first, c == "`" || c == "~" {
                let n = trimmed.prefix { $0 == c }.count
                let info = trimmed.dropFirst(n).trimmingCharacters(in: .whitespaces)
                if let f = fence {
                    if c.utf16.first == f.char, n >= f.count, info.isEmpty { finishFence(upTo: lineRange.location); add(content, .preprocessor); continue }
                } else if n >= 3, !(c == "`" && info.contains("`")) {
                    add(content, .preprocessor)
                    fence = (c.utf16.first!, n, MarkdownHTML.language(forFence: info), NSMaxRange(lineRange)); continue
                }
            }
            if fence != nil { continue }

            if headingRE.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil { add(content, .keyword); continue }
            if MarkdownHTML.Parser.isHR(line) { add(content, .comment); continue }
            let full = NSRange(location: 0, length: (line as NSString).length)
            func shifted(_ r: NSRange) -> NSRange { NSRange(location: r.location + content.location, length: r.length) }
            var claimed: [NSRange] = []
            func claim(_ r: NSRange, _ k: SyntaxKind) {
                if claimed.contains(where: { NSIntersectionRange($0, r).length > 0 }) { return }
                claimed.append(r); add(shifted(r), k)
            }
            if let m = quoteRE.firstMatch(in: line, range: full) { claim(m.range, .comment) }
            else if let m = listRE.firstMatch(in: line, range: full) { claim(m.range(at: 2), .preprocessor) }
            if tableSepRE.firstMatch(in: line, range: full) != nil, line.contains("-"), line.contains("|") { claim(full, .comment); continue }
            for (re, kind, group) in inlinePatterns {
                for m in re.matches(in: line, range: full) {
                    if group > 0, m.numberOfRanges > group, m.range(at: group).location != NSNotFound {                     // odkaz: text jako značka, adresa jako řetězec
                        let whole = m.range
                        let label = m.range(at: 1), url = m.range(at: 2)
                        if claimed.contains(where: { NSIntersectionRange($0, whole).length > 0 }) { continue }
                        claimed.append(whole)
                        add(shifted(NSRange(location: whole.location, length: label.location + label.length + 1 - whole.location)), kind)
                        add(shifted(NSRange(location: label.location + label.length + 1, length: whole.location + whole.length - (label.location + label.length + 1))), .string)
                        _ = url
                    } else { claim(m.range, kind) }
                }
            }
            if line.contains("|") {
                for (i, ch) in line.utf16.enumerated() where ch == 124 { claim(NSRange(location: i, length: 1), .comment) }
            }
        }
        finishFence(upTo: ns.length)
        return out.sorted { $0.range.location < $1.range.location }
    }

    /// ADIF/ADI (formát deníků v radioamatérském provozu): pole `<NÁZEV:délka[:typ]>hodnota`, `<EOH>` a `<EOR>`; volný text hlavičky před prvním polem je komentář.
    static func adifTokens(in text: String) -> [SyntaxToken] {
        let u = Array(text.utf16), n = u.count
        var out: [SyntaxToken] = []
        func add(_ s: Int, _ e: Int, _ k: SyntaxKind) { if e > s { out.append(SyntaxToken(range: NSRange(location: s, length: e - s), kind: k)) } }
        func lower(_ c: UInt16) -> UInt16 { c >= 65 && c <= 90 ? c + 32 : c }
        func matches(_ word: String, at p: Int) -> Bool {
            var k = p; for c in word.utf16 { if k >= n || lower(u[k]) != c { return false }; k += 1 }; return true
        }
        func isNameChar(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 }
        func isTagStart(_ p: Int) -> Bool {                                // <NÁZEV: nebo <NÁZEV>
            guard p < n, u[p] == 60 else { return false }
            var k = p + 1; while k < n && isNameChar(u[k]) { k += 1 }
            return k > p + 1 && k < n && (u[k] == 58 || u[k] == 62)
        }
        var i = 0
        if let first = u.firstIndex(where: { $0 != 32 && $0 != 9 && $0 != 10 && $0 != 13 }), u[first] != 60,       // volný text hlavičky před prvním polem
           let firstTag = (first..<n).first(where: { isTagStart($0) }) { add(0, firstTag, .comment); i = firstTag }
        while i < n {
            guard isTagStart(i) else { i += 1; continue }
            var j = i + 1; while j < n && isNameChar(u[j]) { j += 1 }
            let nameEnd = j
            if matches("<eor>", at: i) || matches("<eoh>", at: i) { add(i, nameEnd + 1, .keyword); i = nameEnd + 1; continue }
            add(i, nameEnd, .tag)
            var length = 0, hasLength = false
            if u[j] == 58 {                                                // :délka
                j += 1; let s = j
                while j < n && u[j] >= 48 && u[j] <= 57 { length = length * 10 + Int(u[j] - 48); hasLength = true; j += 1 }
                add(s, j, .number)
                if j < n, u[j] == 58 { j += 1; let t = j; while j < n && isNameChar(u[j]) { j += 1 }; add(t, j, .type) }       // :typ
            }
            guard j < n, u[j] == 62 else { i = nameEnd; continue }
            add(j, j + 1, .tag)
            var end = min(n, j + 1 + (hasLength ? length : 0))
            if hasLength, let next = (j + 1..<max(j + 1, end)).first(where: { isTagStart($0) }) { end = next }       // délka v bajtech vs. znacích
            while end > j + 1, u[end - 1] == 32 || u[end - 1] == 10 || u[end - 1] == 13 || u[end - 1] == 9 { end -= 1 }
            add(j + 1, end, .string)
            i = max(j + 1, end)
        }
        return out
    }

    public static var languages: [String] { (Array(configs.keys) + ["adif", "markdown"]).sorted() }

    /// Tokeny textu pro daný jazyk (viz `language(forFileName:)`); neznámý jazyk dává prázdný výsledek.
    public static func tokens(in text: String, language: String) -> [SyntaxToken] {
        if language == "adif" { return adifTokens(in: text) }
        if language == "markdown" { return markdownTokens(in: text) }
        guard let cfg = configs[language] else { return [] }
        let u = Array(text.utf16)
        var out: [SyntaxToken] = []
        var i = 0
        let n = u.count
        func has(_ s: String, at p: Int) -> Bool {
            var k = p
            for c in s.utf16 { if k >= n || u[k] != c { return false }; k += 1 }
            return true
        }
        func isIdentStart(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c == 64 || c > 127 }
        func isIdent(_ c: UInt16) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) }
        func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
        func add(_ s: Int, _ e: Int, _ k: SyntaxKind) { out.append(SyntaxToken(range: NSRange(location: s, length: e - s), kind: k)) }
        var lineStart = true
        var keyAllowed = true             // YAML: na začátku řádku nebo za „- “ může následovat klíč

        func isBlank(_ c: UInt16) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }

        while i < n {
            let c = u[i]
            if c == 10 { lineStart = true; keyAllowed = true; i += 1; continue }
            if c == 32 || c == 9 || c == 13 { i += 1; continue }
            let atLineStart = lineStart; lineStart = false
            let canKey = keyAllowed; keyAllowed = false

            // komentáře
            if let (b, e) = cfg.blockComment, has(b, at: i) {
                var j = i + b.utf16.count
                while j < n && !has(e, at: j) { j += 1 }
                j = min(n, j + e.utf16.count); add(i, j, .comment); i = j; continue
            }
            if cfg.lineComments.contains(where: { has($0, at: i) }),
               !(cfg.commentNeedsBlankBefore && i > 0 && !isBlank(u[i - 1])), !(cfg.commentOnlyAtLineStart && !atLineStart) {
                var j = i; while j < n && u[j] != 10 { j += 1 }; add(i, j, .comment); i = j; continue
            }
            if cfg.preprocessor && atLineStart && c == 35 {          // #include, #define …
                var j = i; while j < n && u[j] != 10 { j += 1 }; add(i, j, .preprocessor); i = j; continue
            }
            if atLineStart, cfg.directivePrefixes.contains(c) {          // @startuml, !include …
                var j = i; while j < n && u[j] != 10 { j += 1 }; add(i, j, .preprocessor); i = j; continue
            }
            if cfg.yaml {
                if atLineStart, has("---", at: i) || has("...", at: i), i + 3 >= n || isBlank(u[i + 3]) { add(i, i + 3, .preprocessor); i += 3; continue }
                if c == 45, i + 1 < n, isBlank(u[i + 1]), canKey { i += 1; keyAllowed = true; continue }       // položka seznamu „- “
                if canKey, !"[{#&*!|>%@`,".utf16.contains(c) {                                                // klíč mapy „klíč: hodnota“
                    var j = i
                    if c == 34 || c == 39 {
                        j = i + 1
                        while j < n && u[j] != c && u[j] != 10 { if c == 34 && u[j] == 92 { j += 1 }; j += 1 }
                        j = (j < n && u[j] == c) ? j + 1 : -1
                    } else {
                        while j < n && u[j] != 10 && !(u[j] == 58 && (j + 1 >= n || isBlank(u[j + 1]))) {
                            if u[j] == 35 && j > i && u[j - 1] == 32 { break }
                            j += 1
                        }
                    }
                    if j > i {
                        var k = j; while k < n && (u[k] == 32 || u[k] == 9) { k += 1 }
                        if k < n, u[k] == 58, k + 1 >= n || isBlank(u[k + 1]) {
                            var e = j; while e > i && u[e - 1] == 32 { e -= 1 }
                            add(i, e, .attribute); i = k + 1; continue
                        }
                    }
                }
                if c == 38 || c == 42 || c == 33 {                                                           // &kotva, *alias, !!značka
                    var j = i + 1; while j < n && !isBlank(u[j]) && u[j] != 44 && u[j] != 93 && u[j] != 125 { j += 1 }
                    if j > i + 1 { add(i, j, .type); i = j; continue }
                }
            }
            if cfg.markup {
                if c == 60 {                                          // <tag attr="…">
                    var j = i + 1
                    if j < n && (u[j] == 47 || u[j] == 33 || u[j] == 63) { j += 1 }
                    let s = i; while j < n && (isIdent(u[j]) || u[j] == 45 || u[j] == 58) { j += 1 }
                    add(s, j, .tag); i = j
                    while i < n && u[i] != 62 {
                        if u[i] == 34 || u[i] == 39 {
                            let q = u[i]; var k = i + 1; while k < n && u[k] != q { k += 1 }; k = min(n, k + 1); add(i, k, .string); i = k
                        } else if isIdentStart(u[i]) {
                            var k = i; while k < n && (isIdent(u[k]) || u[k] == 45 || u[k] == 58) { k += 1 }; add(i, k, .attribute); i = k
                        } else { i += 1 }
                    }
                    if i < n { add(i, i + 1, .tag); i += 1 }
                    continue
                }
                i += 1; continue
            }
            // řetězce
            if cfg.tripleQuotes, (c == 34 || c == 39), i + 2 < n, u[i + 1] == c, u[i + 2] == c {
                var j = i + 3; while j < n && !(u[j] == c && j + 2 < n && u[j + 1] == c && u[j + 2] == c) { j += 1 }
                j = min(n, j + 3); add(i, j, .string); i = j; continue
            }
            let yamlQuoteOK: Bool = {
                guard cfg.yaml else { return true }
                var p = i - 1; while p >= 0 && (u[p] == 32 || u[p] == 9) { p -= 1 }
                return p < 0 || [10, 13, 58, 45, 91, 123, 44, 63].contains(u[p])
            }()
            if (cfg.quotes.contains(where: { $0.utf16.first == c }) && yamlQuoteOK) || (cfg.backtickStrings && c == 96) {
                var j = i + 1
                let multiline = c == 96
                while j < n && u[j] != c && (multiline || u[j] != 10) { if u[j] == 92 { j += 1 }; j += 1 }
                j = min(n, j + 1); add(i, j, .string); i = j; continue
            }
            // čísla
            if isDigit(c) || (c == 46 && i + 1 < n && isDigit(u[i + 1])) {
                var j = i + 1
                while j < n && (isIdent(u[j]) || u[j] == 46) { if u[j] == 46 && j + 1 < n && !isDigit(u[j + 1]) { break }; j += 1 }
                add(i, j, .number); i = j; continue
            }
            if cfg.arrows, "-.<>|=*#".utf16.contains(c) {                    // šipky a spojnice PlantUML
                var j = i; while j < n && "-.<>|=*".utf16.contains(u[j]) { j += 1 }
                let run = u[i..<j]
                if run.count >= 2, run.contains(45) || run.contains(61) || (run.contains(46) && (run.contains(60) || run.contains(62))) { add(i, j, .attribute); i = j; continue }
            }
            // identifikátory
            if isIdentStart(c) {
                var j = i + 1; while j < n && isIdent(u[j]) { j += 1 }
                let word = String(decoding: u[i..<j], as: UTF16.self)
                let key = cfg.caseInsensitiveKeywords ? word.lowercased() : word
                if cfg.keywords.contains(key) { add(i, j, .keyword) }
                else if c == 64 { add(i, j, .attribute) }
                else if cfg.typesCapitalized, c >= 65 && c <= 90, j - i > 1 { add(i, j, .type) }
                i = j; continue
            }
            i += 1
        }
        return out
    }
}
