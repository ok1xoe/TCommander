import Testing
import Foundation
@testable import TCCore

@Suite struct WincmdImportTests {
    let ini = """
    [Configuration]
    Editor=notepad.exe
    [Buttonbar]
    Buttoncount=5
    button1=%COMMANDER_PATH%\\TOTALCMD.EXE,10
    cmd1=cm_copy
    menu1=Kopie
    button2=x
    cmd2=cm_renmov
    menu2=Přesun
    button3=x
    cmd3=notepad.exe
    menu3=Poznámkový blok
    button4=x
    cmd4=em_mytool
    menu4=Můj nástroj
    button5=x
    cmd5=cm_weirdunknown
    menu5=Divné
    [Shortcuts]
    F5=cm_copy
    C+B=cm_dirbranch
    CA+X=cm_syncdirs
    ENTER=cm_list
    A+ENTER=cm_properties
    NUM+=cm_selectbymask
    S+F5=cm_nonexistentcmd
    CS+BOGUSKEY=cm_copy
    [DirMenu]
    menu1=&Dokumenty
    cmd1=cd /Users/me/Documents
    menu2=-
    menu3=Disk C
    cmd3=cd C:\\Users\\me
    menu4=Tmp
    cmd4=/tmp
    """

    let usercmd = """
    [em_gitstatus]
    cmd=git
    param=status %P
    path=%P
    menu=Git status
    [em_notepad]
    cmd=C:\\Windows\\notepad.exe
    param=%N
    menu=Notepad
    [em_copyit]
    cmd=cm_copy
    menu=Kopíruj
    """

    @Test func importsButtonBarShortcutsUserCommandsAndHotlist() {
        let r = WincmdImporter.parse(ini: ini, userCommands: usercmd, pathExists: { $0 == "/Users/me/Documents" || $0 == "/tmp" })
        #expect(r.buttonBar.map(\.command) == ["cm_copy", "cm_move", "em_mytool"])
        #expect(r.buttonBar[0].title == "Kopie" && r.buttonBar[0].icon == "doc.on.doc")
        #expect(r.shortcuts["cm_copy"] == [Shortcut("f5")!] && r.shortcuts["cm_branchview"] == [Shortcut("ctrl+b")!])
        #expect(r.shortcuts["cm_sync"] == [Shortcut("ctrl+alt+x")!] && r.shortcuts["cm_view"] == [Shortcut("return")!])
        #expect(r.shortcuts["cm_properties"] == [Shortcut("alt+return")!] && r.shortcuts["cm_markmask"] == [Shortcut("kp+")!])
        #expect(r.userCommands.map(\.name) == ["em_copyit", "em_gitstatus"])
        #expect(r.userCommands[1].command == "git" && r.userCommands[1].parameters == "status %P" && r.userCommands[0].command == "cm_copy")
        #expect(r.hotlist == [HotlistEntry(name: "Dokumenty", path: "/Users/me/Documents"), HotlistEntry(name: "Tmp", path: "/tmp")])
    }

    @Test func reportsWhatCouldNotBeConverted() {
        let r = WincmdImporter.parse(ini: ini, userCommands: usercmd, pathExists: { _ in false })
        let text = r.skipped.joined(separator: "\n")
        #expect(text.contains("Poznámkový blok") && text.contains("Divné") && text.contains("cm_nonexistentcmd") && text.contains("BOGUSKEY"))
        #expect(text.contains("Notepad") && text.contains("Disk C") && r.hotlist.isEmpty)
        #expect(!WincmdImporter.parse(ini: "", userCommands: nil).skipped.isEmpty == false)
        #expect(WincmdImporter.parse(ini: "garbage without sections").isEmpty)
    }

    @Test func parsesShortcutNotation() {
        #expect(WincmdImporter.parseShortcut("C+F5") == Shortcut("ctrl+f5"))
        #expect(WincmdImporter.parseShortcut("CAS+X") == Shortcut("ctrl+alt+shift+x"))
        #expect(WincmdImporter.parseShortcut("NUM+") == Shortcut("kp+") && WincmdImporter.parseShortcut("C+NUM-") == Shortcut("ctrl+kp-"))
        #expect(WincmdImporter.parseShortcut("DEL") == Shortcut("delete") && WincmdImporter.parseShortcut("S+DEL") == Shortcut("shift+delete"))
        #expect(WincmdImporter.parseShortcut("PGUP") == Shortcut("pageup") && WincmdImporter.parseShortcut("W+K") == Shortcut("cmd+k"))
        #expect(WincmdImporter.parseShortcut("XYZZY") == nil)
    }

    @Test func loadsFilesIncludingWindows1250AndSiblingUsercmd() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        // „Přesun“ ve Windows-1250
        let cp1250 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsLatin2.rawValue)))
        let text = "[Buttonbar]\nButtoncount=1\ncmd1=cm_renmov\nmenu1=P\u{159}esun\n"
        try text.data(using: cp1250)!.write(to: d.appendingPathComponent("wincmd.ini"))
        try usercmd.write(to: d.appendingPathComponent("usercmd.ini"), atomically: true, encoding: .utf8)
        let r = try WincmdImporter.load(from: d.appendingPathComponent("wincmd.ini"))
        #expect(r.buttonBar.first?.title == "Přesun" && r.userCommands.contains { $0.name == "em_gitstatus" })
    }

    @Test func everyMappedCommandExistsInRegistry() {
        let missing = Set(WincmdImporter.commandMap.values).filter { CommandRegistry.byID[$0] == nil }
        #expect(missing.isEmpty, "\(missing)")
    }
}
