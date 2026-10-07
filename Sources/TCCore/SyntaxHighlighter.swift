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
        "sql": Config(lineComments: ["--"], blockComment: ("/*", "*/"), quotes: ["'", "\""], keywords: kw("select from where and or not in is null like between join inner left right outer full cross on group by order having limit offset insert into values update set delete create table alter drop index view primary key foreign references unique default constraint distinct as union all exists case when then else end asc desc count sum avg min max begin commit rollback"), caseInsensitiveKeywords: true),
        "json": Config(quotes: ["\""], keywords: kw("true false null")),
        "yaml": Config(lineComments: ["#"], keywords: kw("true false null yes no on off")),
        "toml": Config(lineComments: ["#"], tripleQuotes: true, keywords: kw("true false")),
        "css": Config(blockComment: ("/*", "*/"), keywords: kw("important inherit initial none auto")),
        "markup": Config(blockComment: ("<!--", "-->"), markup: true),
        "lua": Config(lineComments: ["--"], blockComment: ("--[[", "]]"), keywords: kw("and break do else elseif end false for function goto if in local nil not or repeat return then true until while")),
        "makefile": Config(lineComments: ["#"], keywords: kw("ifeq ifneq ifdef ifndef else endif include define endef export")),
    ]

    private static let extensions: [String: String] = [
        "swift": "swift", "c": "c", "h": "c", "m": "c", "mm": "c", "cc": "c", "cpp": "c", "cxx": "c", "hpp": "c", "hh": "c", "cs": "java", "java": "java",
        "kt": "kotlin", "kts": "kotlin", "js": "js", "mjs": "js", "cjs": "js", "jsx": "js", "ts": "js", "tsx": "js", "py": "python", "rb": "ruby",
        "sh": "shell", "bash": "shell", "zsh": "shell", "command": "shell", "go": "go", "rs": "rust", "php": "php", "sql": "sql", "json": "json",
        "yml": "yaml", "yaml": "yaml", "toml": "toml", "ini": "toml", "css": "css", "scss": "css", "html": "markup", "htm": "markup", "xml": "markup",
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

    public static var languages: [String] { configs.keys.sorted() }

    /// Tokeny textu pro daný jazyk (viz `language(forFileName:)`); neznámý jazyk dává prázdný výsledek.
    public static func tokens(in text: String, language: String) -> [SyntaxToken] {
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

        while i < n {
            let c = u[i]
            if c == 10 { lineStart = true; i += 1; continue }
            if c == 32 || c == 9 || c == 13 { i += 1; continue }
            let atLineStart = lineStart; lineStart = false

            // komentáře
            if let (b, e) = cfg.blockComment, has(b, at: i) {
                var j = i + b.utf16.count
                while j < n && !has(e, at: j) { j += 1 }
                j = min(n, j + e.utf16.count); add(i, j, .comment); i = j; continue
            }
            if cfg.lineComments.contains(where: { has($0, at: i) }) {
                var j = i; while j < n && u[j] != 10 { j += 1 }; add(i, j, .comment); i = j; continue
            }
            if cfg.preprocessor && atLineStart && c == 35 {          // #include, #define …
                var j = i; while j < n && u[j] != 10 { j += 1 }; add(i, j, .preprocessor); i = j; continue
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
            if cfg.quotes.contains(where: { $0.utf16.first == c }) || (cfg.backtickStrings && c == 96) {
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
