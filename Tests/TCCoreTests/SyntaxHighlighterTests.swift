import Testing
import Foundation
@testable import TCCore

@Suite struct SyntaxHighlighterTests {
    func kinds(_ text: String, _ lang: String) -> [(String, SyntaxKind)] {
        let ns = text as NSString
        return SyntaxHighlighter.tokens(in: text, language: lang).map { (ns.substring(with: $0.range), $0.kind) }
    }
    func has(_ r: [(String, SyntaxKind)], _ t: String, _ k: SyntaxKind) -> Bool { r.contains { $0.0 == t && $0.1 == k } }

    @Test func detectsLanguageByFileName() {
        #expect(SyntaxHighlighter.language(forFileName: "Main.swift") == "swift")
        #expect(SyntaxHighlighter.language(forFileName: "a.PY") == "python")
        #expect(SyntaxHighlighter.language(forFileName: "Makefile") == "makefile")
        #expect(SyntaxHighlighter.language(forFileName: "notes.txt") == nil)
        #expect(SyntaxHighlighter.language(forFileName: ".gitignore") == nil)
        for l in Set(["swift", "c", "java", "kotlin", "js", "python", "ruby", "shell", "go", "rust", "php", "sql", "json", "yaml", "toml", "css", "markup", "lua", "makefile"]) { #expect(SyntaxHighlighter.languages.contains(l)) }
    }

    @Test func swiftTokens() {
        let r = kinds("let x = 42 // note\nstruct Foo { var s = \"a\\\"b\" }", "swift")
        #expect(has(r, "let", .keyword) && has(r, "42", .number) && has(r, "// note", .comment))
        #expect(has(r, "Foo", .type) && has(r, "\"a\\\"b\"", .string) && has(r, "struct", .keyword))
    }

    @Test func keywordsInsideStringsAndCommentsAreNotHighlighted() {
        let r = kinds("x = \"if else\" /* while */", "c")
        #expect(r.filter { $0.1 == .keyword }.isEmpty)
        #expect(has(r, "\"if else\"", .string) && has(r, "/* while */", .comment))
    }

    @Test func pythonTripleQuotesAndHashComments() {
        let r = kinds("def f():\n    \"\"\"doc\nstring\"\"\"  # c\n    return None", "python")
        #expect(has(r, "def", .keyword) && has(r, "return", .keyword) && has(r, "None", .keyword))
        #expect(has(r, "\"\"\"doc\nstring\"\"\"", .string) && has(r, "# c", .comment))
    }

    @Test func cPreprocessorOnlyAtLineStart() {
        let r = kinds("#include <stdio.h>\nint a = 1; // #not", "c")
        #expect(has(r, "#include <stdio.h>", .preprocessor) && has(r, "int", .keyword) && has(r, "// #not", .comment))
    }

    @Test func markupTagsAttributesAndComments() {
        let r = kinds("<!-- c --><a href=\"x\">t</a>", "markup")
        #expect(has(r, "<!-- c -->", .comment) && has(r, "<a", .tag) && has(r, "href", .attribute) && has(r, "\"x\"", .string) && has(r, "</a", .tag))
    }

    @Test func markdownHighlighting() {
        for e in ["md", "markdown", "MD", "mkd"] { #expect(SyntaxHighlighter.language(forFileName: "README.\(e)") == "markdown") }
        let text = "# Nadpis\n\n- položka s **tučným**, *kurzívou* a `kódem`\n1. [odkaz](https://x.cz) ~~pryč~~\n> citace\n\n```swift\nlet a = 1\n```\n\n| a | b |\n|---|---|\n\n---"
        let r = kinds(text, "markdown")
        #expect(has(r, "# Nadpis", .keyword) && has(r, "-", .preprocessor) && has(r, "1.", .preprocessor) && r.contains { $0.1 == .comment && $0.0.hasPrefix(">") })
        #expect(has(r, "**tučným**", .keyword) && has(r, "*kurzívou*", .type) && has(r, "`kódem`", .string) && has(r, "~~pryč~~", .comment))
        #expect(has(r, "[odkaz]", .tag) && has(r, "(https://x.cz)", .string))
        #expect(has(r, "```swift", .preprocessor) && has(r, "let", .keyword) && has(r, "1", .number) && has(r, "```", .preprocessor))   // kód v ohraničení se zvýrazní podle jazyka
        #expect(has(r, "|---|---|", .comment) && has(r, "---", .comment))
        let tokens = SyntaxHighlighter.tokens(in: text, language: "markdown")
        let len = (text as NSString).length
        var last = 0
        for t in tokens { #expect(t.range.location >= last && NSMaxRange(t.range) <= len, "\(t)"); last = NSMaxRange(t.range) }
    }

    @Test func markdownEdgeCases() {
        for t in ["", "```", "```swift", "``` x ```", "*", "**", "[", "![](", "|", "# ", ">", "- ", "~~", "```\n```", "a\r\nb\r\n```\r\nx\r\n```"] { _ = SyntaxHighlighter.tokens(in: t, language: "markdown") }
        let unclosed = kinds("```python\nx = 1\n", "markdown")
        #expect(has(unclosed, "x", .keyword) == false && has(unclosed, "1", .number))
        #expect(SyntaxHighlighter.languages.contains("markdown"))
    }

    @Test func sqlDialectsExtensionsTypesAndComments() {
        for ext in ["sql", "pgsql", "mysql", "tsql", "plsql", "ddl", "hql", "SQL"] { #expect(SyntaxHighlighter.language(forFileName: "x.\(ext)") == "sql", "\(ext)") }
        let r = kinds("CREATE TABLE `t` (id INT PRIMARY KEY, name varchar(20) DEFAULT 'a') -- c\n# mysql\nselect * from t where x ilike '%a%' /* b */", "sql")
        for k in ["CREATE", "TABLE", "INT", "PRIMARY", "KEY", "varchar", "DEFAULT", "select", "from", "where", "ilike"] { #expect(has(r, k, .keyword), "\(k)") }
        #expect(has(r, "`t`", .string) && has(r, "'a'", .string) && has(r, "-- c", .comment) && has(r, "# mysql", .comment) && has(r, "/* b */", .comment) && has(r, "20", .number))
    }

    @Test func adifFieldsLengthsAndRecordMarkers() {
        #expect(SyntaxHighlighter.language(forFileName: "log.ADI") == "adif" && SyntaxHighlighter.language(forFileName: "x.adif") == "adif")
        let text = "ADIF export by macTC\n<ADIF_VER:5>3.1.0\n<EOH>\n<CALL:5>OK1XO <BAND:3>20m <QSO_DATE:8:D>20261007 <EOR>\n<call:4>DL1A<eor>"
        let r = kinds(text, "adif")
        #expect(r.first?.1 == .comment && r.first?.0 == "ADIF export by macTC\n")                // komentář je jen volný text před prvním polem
        #expect(has(r, "<ADIF_VER", .tag) && has(r, "3.1.0", .string))                           // pole v hlavičce se zvýrazní jako ostatní
        #expect(has(r, "<EOH>", .keyword) && has(r, "<EOR>", .keyword) && has(r, "<eor>", .keyword))
        #expect(has(r, "<CALL", .tag) && has(r, "OK1XO", .string) && has(r, "20m", .string) && has(r, "20261007", .string) && has(r, "D", .type) && has(r, "5", .number) && has(r, "<call", .tag) && has(r, "DL1A", .string))
    }

    @Test func adifLengthInBytesDoesNotSwallowTheNextField() {
        // délka 8 je v bajtech (české „Příbram“ má 7 znaků, 9 bajtů); hodnota se ořízne na další značce
        let r = kinds("<QTH:9>Příbram <CALL:5>OK1XO <EOR>", "adif")
        #expect(has(r, "Příbram", .string) && has(r, "<CALL", .tag) && has(r, "OK1XO", .string))
        for t in ["<", "<A", "<A:", "<A:99>x", "<:5>", "<A:5:", "", "<EOH", "text <EOH>", "<A:5>ab<EOR"] { _ = SyntaxHighlighter.tokens(in: t, language: "adif") }
    }

    @Test func plantUMLDirectivesCommentsKeywordsAndArrows() {
        #expect(SyntaxHighlighter.language(forFileName: "a.puml") == "plantuml" && SyntaxHighlighter.language(forFileName: "a.wsd") == "plantuml")
        let r = kinds("@startuml\n' komentář\nparticipant \"A B\" as A\nA -> B : ahoj ' neni komentar\nB --> A\nA <|-- C\nnote left of A : x\n/' blok '/\n!include x.puml\n@enduml", "plantuml")
        #expect(has(r, "@startuml", .preprocessor) && has(r, "@enduml", .preprocessor) && has(r, "!include x.puml", .preprocessor))
        #expect(has(r, "' komentář", .comment) && has(r, "/' blok '/", .comment) && !r.contains { $0.1 == .comment && $0.0.contains("neni") })
        #expect(has(r, "participant", .keyword) && has(r, "as", .keyword) && has(r, "note", .keyword) && has(r, "\"A B\"", .string))
        #expect(has(r, "->", .attribute) && has(r, "-->", .attribute) && has(r, "<|--", .attribute))
    }

    @Test func yamlKeysAnchorsTagsDocumentsAndComments() {
        let y = "---\n# komentář\nname: macTC  # za mezerou\nurl: http://x.cz/#frag\nlist:\n  - a: 1\n  - \"k\": true\nbase: &b\n  x: *b\nt: !!str 5\n'q k': 'v'\nmsg: don't panic\n...\n"
        let r = kinds(y, "yaml")
        #expect(has(r, "---", .preprocessor) && has(r, "...", .preprocessor) && has(r, "# komentář", .comment) && has(r, "# za mezerou", .comment))
        for k in ["name", "url", "list", "a", "\"k\"", "base", "x", "t", "'q k'", "msg"] { #expect(has(r, k, .attribute), "klíč \(k)") }
        #expect(!r.contains { $0.1 == .comment && $0.0.contains("frag") })                  // # bez mezery před sebou není komentář
        #expect(has(r, "&b", .type) && has(r, "*b", .type) && has(r, "!!str", .type) && has(r, "true", .keyword) && has(r, "1", .number) && has(r, "'v'", .string))
        #expect(!r.contains { $0.1 == .string && $0.0.contains("t panic") })                // apostrof v prostém textu nezačíná řetězec
    }

    @Test func sqlKeywordsAreCaseInsensitiveAndJsonLiterals() {
        #expect(has(kinds("SELECT a FROM t -- x", "sql"), "SELECT", .keyword))
        let j = kinds("{\"a\": [1, 2.5, true, null]}", "json")
        #expect(has(j, "\"a\"", .string) && has(j, "2.5", .number) && has(j, "true", .keyword) && has(j, "null", .keyword))
    }

    @Test func tokensUseUTF16OffsetsAndNeverOverlapOrExceedText() {
        let text = "let s = \"žluťoučký 😀\" // kůň\nvar n = 1"
        let toks = SyntaxHighlighter.tokens(in: text, language: "swift")
        let len = (text as NSString).length
        var last = 0
        for t in toks { #expect(t.range.location >= last && NSMaxRange(t.range) <= len); last = NSMaxRange(t.range) }
        #expect((text as NSString).substring(with: toks.first { $0.kind == .string }!.range) == "\"žluťoučký 😀\"")
    }

    @Test func unterminatedConstructsDoNotCrash() {
        for l in SyntaxHighlighter.languages { for t in ["\"abc", "/* x", "'''x", "<a href=\"", "`x", "\\", "", "1.", "#"] { _ = SyntaxHighlighter.tokens(in: t, language: l) } }
    }
}
