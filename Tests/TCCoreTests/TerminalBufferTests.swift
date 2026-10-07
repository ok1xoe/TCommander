import Testing
import Foundation
@testable import TCCore

@Suite struct TerminalBufferTests {
    func run(_ chunks: [String]) -> String {
        var b = TerminalTextBuffer()
        for c in chunks { b.append(Data(c.utf8)) }
        return b.text
    }

    @Test func plainTextAndNewlines() {
        #expect(run(["hello\r\nworld\r\n"]) == "hello\nworld\n")
    }

    @Test func stripsEscapeSequences() {
        #expect(run(["\u{1B}[1;32mgreen\u{1B}[0m plain \u{1B}]0;title\u{07}ok"]) == "green plain ok")
        #expect(run(["a\u{1B}[", "31mb"]) == "ab")                    // sekvence rozdělená mezi bloky
    }

    @Test func carriageReturnOverwritesTheLine() {
        #expect(run(["echo hi"]) == "echo hi")
        #expect(run(["prompt % ec", "\rprompt % echo hi\r\nhi\r\n"]) == "prompt % echo hi\nhi\n")   // zsh překreslí řádek
        #expect(run(["progress 10%\rprogress 99%"]) == "progress 99%")
        #expect(run(["long line\rab"]) == "abng line")
    }

    @Test func backspaceEditing() {
        #expect(run(["abc\u{08} \u{08}d"]) == "abd")                  // "\b \b" jako smazání znaku
        #expect(run(["\u{08}\u{08}x"]) == "x")                        // zpětný posun nepřeteče před začátek
    }

    @Test func utf8SplitAcrossChunks() {
        let bytes = Array("příliš žluťoučký 🐎".utf8)
        for cut in 1..<bytes.count {
            var b = TerminalTextBuffer()
            b.append(Data(bytes[0..<cut])); b.append(Data(bytes[cut...]))
            #expect(b.text == "příliš žluťoučký 🐎", "řez na \(cut)")
        }
    }

    @Test func tabsAndTrimming() {
        #expect(run(["a\tb"]) == "a       b")
        var b = TerminalTextBuffer(maxCharacters: 100)
        for i in 0..<200 { b.append(Data("line \(i) padding padding\n".utf8)) }
        #expect(b.text.count <= 400 && b.text.hasSuffix("line 199 padding padding\n"))
    }
}
