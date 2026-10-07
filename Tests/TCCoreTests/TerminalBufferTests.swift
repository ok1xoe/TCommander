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

@Suite struct TerminalColorTests {
    func runs(_ s: String) -> [TerminalTextBuffer.Run] { var b = TerminalTextBuffer(); b.append(Data(s.utf8)); return b.runs }

    @Test func keepsForegroundColorsAndBold() {
        let r = runs("plain \u{1B}[31mred\u{1B}[0m \u{1B}[1;32mbold green\u{1B}[0m end")
        #expect(r.map(\.text) == ["plain ", "red", " ", "bold green", " end"])
        #expect(r[0].style == TerminalStyle() && r[1].style.foreground == 1 && r[3].style == TerminalStyle(foreground: 2, bold: true) && r[4].style == TerminalStyle())
        #expect(r[1].style.rgb() == 0xCC0000)
    }

    @Test func brightAnd256AndTrueColor() {
        #expect(runs("\u{1B}[91mx")[0].style.foreground == 9)
        #expect(runs("\u{1B}[38;5;196mx")[0].style.rgb() == 0xFF0000)          // 196 = čistě červená v kostce 6×6×6
        #expect(runs("\u{1B}[38;5;244mx")[0].style.rgb() == 0x808080)          // stupně šedi
        #expect(runs("\u{1B}[38;2;10;20;30mx")[0].style.rgb() == 0x0A141E)
        #expect(runs("\u{1B}[31m\u{1B}[39mx")[0].style == TerminalStyle())
        #expect(runs("\u{1B}[mx")[0].style == TerminalStyle())                 // prázdné parametry = reset
    }

    @Test func plainTextIsUnchangedAndColorsSurviveLineBreaksAndOverwrites() {
        var b = TerminalTextBuffer()
        b.append(Data("\u{1B}[34mblue line\r\nnext\u{1B}[0m\r\nab\rX".utf8))
        #expect(b.text == "blue line\nnext\nXb")
        let r = b.runs
        #expect(r.first?.style.foreground == 4 && r.first?.text == "blue line")
        #expect(r.map(\.text).joined() == b.text)
    }
}

@Suite struct TerminalLineEditingTests {
    func text(_ chunks: [String]) -> String { var b = TerminalTextBuffer(); for c in chunks { b.append(Data(c.utf8)) }; return b.text }

    @Test func eraseToEndOfLineAndCursorMoves() {
        #expect(text(["abcdef\u{1B}[3D\u{1B}[K"]) == "abc")                                // doleva o 3 a smazat zbytek
        #expect(text(["abcdef\u{1B}[2D\u{1B}[CX"]) == "abcdeX")                           // doleva 2, doprava 1, přepis
        #expect(text(["hello\u{1B}[1GJ"]) == "Jello")                                      // absolutní sloupec
        #expect(text(["abcdef\u{1B}[4D\u{1B}[2P"]) == "abef")                              // smazání 2 znaků
        #expect(text(["abcdef\u{1B}[2K"]) == "")
        #expect(text(["abcdef\u{1B}[3D\u{1B}[1K"]) == "    ef")                            // smazáno od začátku po kurzor včetně
    }

    @Test func zshStyleLineRedrawAfterHistoryRecall() {
        // prompt, napsáno "ls", Backspace („\b“ + smazání), znovu napsáno "pwd"
        #expect(text(["% ls", "\u{08}\u{1B}[K", "\u{08}\u{1B}[K", "pwd"]) == "% pwd")
        // překreslení celého řádku
        #expect(text(["% old command", "\r\u{1B}[K% new"]) == "% new")
    }

    @Test func privateModesAreIgnored() {
        #expect(text(["\u{1B}[?2004hprompt\u{1B}[?2004l\u{1B}[?25h"]) == "prompt")
        #expect(text(["a\u{1B}[0K\u{1B}[0mb"]) == "ab")
    }
}
