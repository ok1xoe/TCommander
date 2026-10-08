import Testing
import Foundation
@testable import TCCore

@Suite struct MarkdownHTMLTests {
    func html(_ s: String, base: URL? = nil) -> String { MarkdownHTML.render(s, baseURL: base) }

    @Test func headingsAndParagraphs() {
        let h = html("# Nadpis\n\nPrvní řádek\ndruhý řádek\n\n## Podnadpis ##\n\nTitulek\n=======\n\nDalší\n-----")
        #expect(h.contains("<h1 id=\"nadpis\">Nadpis</h1>") && h.contains("<h2 id=\"podnadpis\">Podnadpis</h2>"))
        #expect(h.contains("<p>První řádek\ndruhý řádek</p>"))
        #expect(h.contains("<h1 id=\"titulek\">Titulek</h1>") && h.contains("<h2 id=\"dalsi\"><a id=\"další\"></a>Další</h2>"))
    }

    @Test func headingIdsAreAsciiWithTheUnicodeAnchorAlongside() {
        let h = html("## Hromadné přejmenování\n\n### Plain Title 2\n\n# Čeština – ukázka")
        #expect(h.contains("<h2 id=\"hromadne-prejmenovani\"><a id=\"hromadné-přejmenování\"></a>Hromadné přejmenování</h2>"))
        #expect(h.contains("<h3 id=\"plain-title-2\">Plain Title 2</h3>"), "bez diakritiky žádná druhá kotva")
        #expect(h.contains("id=\"cestina--ukazka\"") || h.contains("id=\"cestina-ukazka\""))
    }

    @Test func emphasisStrongStrikeAndCode() {
        let h = html("Je to *kurzíva*, **tučné**, ***obojí***, ~~přeškrtnuté~~ a `kód <b>`.")
        #expect(h.contains("<em>kurzíva</em>") && h.contains("<strong>tučné</strong>") && h.contains("<strong><em>obojí</em></strong>"))
        #expect(h.contains("<del>přeškrtnuté</del>") && h.contains("<code>kód &lt;b&gt;</code>"))
        #expect(html("snake_case_name a 2 * 3 * 4").contains("snake_case_name") && !html("snake_case_name").contains("<em>"))
        #expect(html("*a **b** c*").contains("<em>a <strong>b</strong> c</em>"))
        #expect(html("**tučné s *vnořenou* kurzívou**").contains("<strong>tučné s <em>vnořenou</em> kurzívou</strong>"))
        #expect(html("*nedokončené").contains("*nedokončené"))
    }

    @Test func linksImagesAndSafety() {
        let h = html("[web](https://example.com \"titulek\") a ![obr](img/a.png) <https://x.cz> https://auto.cz/a?b=1, [x](javascript:alert(1)) [m](mailto:a@b.cz)")
        #expect(h.contains("<a href=\"https://example.com\" title=\"titulek\">web</a>") && h.contains("<img src=\"img/a.png\" alt=\"obr\">"))
        #expect(h.contains("<a href=\"https://x.cz\">https://x.cz</a>") && h.contains("<a href=\"https://auto.cz/a?b=1\">"))
        #expect(!h.contains("javascript:") && h.contains("x ") && h.contains("mailto:a@b.cz"))
        let base = URL(fileURLWithPath: "/tmp/docs/")
        #expect(html("![a](pic one.png)", base: base).contains("<img src=\"file:///tmp/docs/pic%20one.png\"") || html("![a](pic%20one.png)", base: base).contains("file:///tmp/docs/pic%20one.png"))
        #expect(html("[odkaz](#sekce)").contains("href=\"#sekce\""))
    }

    @Test func rawHTMLIsEscaped() {
        let h = html("<script>alert(1)</script> a <b>tučné</b> & entita &amp; &copy;")
        #expect(!h.contains("<script") && h.contains("&lt;script&gt;") && h.contains("&lt;b&gt;") && h.contains("&amp; entita &amp; &copy;"))
    }

    @Test func listsNestedOrderedAndTasks() {
        let h = html("- jedna\n- dvě\n  - vnořená\n  - druhá\n- tři\n\n1. první\n2. druhá\n\n3) začíná od tří\n4) další\n\n- [ ] úkol\n- [x] hotovo")
        #expect(h.contains("<ul>\n<li>jedna</li>") && h.contains("<li>dvě\n<ul>\n<li>vnořená</li>\n<li>druhá</li>\n</ul></li>") && h.contains("<li>tři</li>"))
        #expect(h.contains("<ol>\n<li>první</li>\n<li>druhá</li>\n</ol>") && h.contains("<ol start=\"3\">"))
        #expect(h.contains("class=\"tasks\"") && h.contains("<input type=\"checkbox\" disabled> úkol") && h.contains("<input type=\"checkbox\" checked disabled> hotovo"))
    }

    @Test func looseListsKeepParagraphs() {
        let h = html("- a\n\n- b")
        #expect(h.contains("<li><p>a</p></li>") && h.contains("<li><p>b</p></li>"))
    }

    @Test func blockquotesAndRules() {
        let h = html("> citace\n> pokračuje\n>\n> > vnořená\n\n---\n\n***")
        #expect(h.contains("<blockquote>\n<p>citace\npokračuje</p>\n<blockquote>\n<p>vnořená</p>\n</blockquote>\n</blockquote>"))
        #expect(h.components(separatedBy: "<hr>").count == 3)
    }

    @Test func codeBlocksFencedIndentedAndHighlighted() {
        let h = html("```swift\nlet a = 1 // c\n```\n\n```\n<raw> & text\n```\n\n    odsazený\n    kód\n\nzase text")
        #expect(h.contains("<span class=\"k\">let</span>") && h.contains("<span class=\"n\">1</span>") && h.contains("<span class=\"c\">// c</span>") && h.contains("class=\"language-swift\""))
        #expect(h.contains("<pre><code>&lt;raw&gt; &amp; text</code></pre>"))
        #expect(h.contains("<pre><code>odsazený\nkód</code></pre>") && h.contains("<p>zase text</p>"))
        #expect(html("```\nnezavřený\nkód").contains("<pre><code>nezavřený\nkód</code></pre>"))
        #expect(html("````\n```\nuvnitř\n```\n````").contains("```\nuvnitř\n```"))
    }

    @Test func tablesWithAlignment() {
        let h = html("| Název | Počet | Cena |\n|:--|:-:|--:|\n| a | 1 | 2,5 |\n| b \\| c | 2 |")
        #expect(h.contains("<th>Název</th>") || h.contains("<th style=\"text-align:left\">Název</th>"))
        #expect(h.contains("<th style=\"text-align:center\">Počet</th>") && h.contains("<th style=\"text-align:right\">Cena</th>"))
        #expect(h.contains("<td style=\"text-align:right\">2,5</td>") && h.contains("<td>b | c</td>") || h.contains("b | c"))
        #expect(h.contains("<td style=\"text-align:right\"></td>"))                       // chybějící buňka se doplní
    }

    @Test func hardBreaksAndEscapes() {
        #expect(html("řádek  \nzlom").contains("řádek<br>\nzlom") && html("a\\\nb").contains("a<br>\nb"))
        #expect(html("\\*ne kurzíva\\*").contains("*ne kurzíva*") && !html("\\*ne\\*").contains("<em>"))
    }

    @Test func pageWrapsBodyWithStylesAndEscapesTheTitle() {
        let p = MarkdownHTML.page("# Ahoj", title: "a<b>")
        #expect(p.hasPrefix("<!doctype html>") && p.contains("<title>a&lt;b&gt;</title>") && p.contains("prefers-color-scheme:dark") && p.contains("<h1 id=\"ahoj\">Ahoj</h1>"))
    }

    @Test func degenerateInputDoesNotCrashOrHang() {
        for s in ["", "\n\n", "#", "# ", "[", "[]()", "![](", "**", "***", "`", "``a`", "> ", "- ", "1.", "|", "|a|\n|-|", "<", "&", "\\", "[a](b", "~~", "_", "* * *", "-\n-"] { _ = html(s) }
        let big = String(repeating: "*a _b_ `c` [d](e)\n", count: 3000)
        _ = html(big)
    }
}
