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
