import Testing
import Foundation
@testable import TCCore

@Suite struct ShortcutTests {
    @Test func parsesAndPrints() throws {
        #expect(Shortcut("F5") == Shortcut(key: "f5"))
        #expect(Shortcut("Ctrl+Shift+C")?.description == "ctrl+shift+c")
        #expect(Shortcut("shift+ctrl+c") == Shortcut("ctrl+shift+c"))
        #expect(Shortcut("option+return")?.modifiers == [.alt] && Shortcut("command+k")?.modifiers == [.cmd])
        #expect(Shortcut("ctrl++")?.key == "+")
        #expect(Shortcut("") == nil && Shortcut("ctrl+") == nil && Shortcut("hyper+x") == nil && Shortcut("ctrl+notakey") == nil)
        let data = try JSONEncoder().encode(Shortcut("alt+f7")!)
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == Shortcut("alt+f7"))
        #expect(Shortcut.macKeyCodes[96] == "f5" && Shortcut.macKeyCodes[36] == "return")
    }
}

@Suite struct KeymapTests {
    @Test func registryHasUniqueIDsAndNoDefaultConflicts() {
        let ids = CommandRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count && ids.allSatisfy { $0.hasPrefix("cm_") })
        #expect(Keymap().conflicts().isEmpty, "\(Keymap().conflicts())")
    }

    @Test func defaultsOverridesAndConflicts() {
        var k = Keymap()
        #expect(k.command(for: Shortcut("f5")!) == "cm_copy" && k.command(for: Shortcut("alt+f7")!) == "cm_search")
        #expect(k.command(for: Shortcut("ctrl+shift+9")!) == nil)
        k.set([Shortcut("ctrl+shift+9")!], for: "cm_copy")
        #expect(k.command(for: Shortcut("ctrl+shift+9")!) == "cm_copy" && k.command(for: Shortcut("f5")!) == nil)   // výchozí F5 uvolněno
        k.set([Shortcut("f5")!], for: "cm_move")
        #expect(k.conflicts().isEmpty)
        k.set([Shortcut("f5")!], for: "cm_copy")
        #expect(k.conflicts().map { $0.1.sorted() } == [["cm_copy", "cm_move"]])
        k.reset("cm_move"); k.reset("cm_copy")
        #expect(k == Keymap())                                      // návrat k výchozímu stavu = prázdné úpravy
        k.set([], for: "cm_delete")
        #expect(k.command(for: Shortcut("f8")!) == nil && k.shortcuts(for: "cm_delete").isEmpty)
        let data = try! JSONEncoder().encode(k)
        #expect(try! JSONDecoder().decode(Keymap.self, from: data) == k)
    }
}

@Suite struct PlaceholderTests {
    let ctx = PlaceholderContext(sourcePath: "/Users/me/My Docs", targetPath: "/tmp", cursorName: "it's here.txt", selectedNames: ["a b.txt", "c.txt"], listFile: "/tmp/list.lst")

    @Test func expandsAndQuotes() {
        #expect(PlaceholderExpander.expand("ls %P", ctx) == "ls '/Users/me/My Docs/'")
        #expect(PlaceholderExpander.expand("cp %N %T", ctx) == "cp 'it'\\''s here.txt' /tmp/")
        #expect(PlaceholderExpander.expand("tar cf x.tar %S", ctx) == "tar cf x.tar 'a b.txt' c.txt")
        #expect(PlaceholderExpander.expand("%F|%L|100%%|%Z", ctx) == "'/Users/me/My Docs/it'\\''s here.txt'|/tmp/list.lst|100%|%Z")
        #expect(PlaceholderExpander.expand("%P%N", ctx, quote: false) == "/Users/me/My Docs/it's here.txt")
        #expect(PlaceholderExpander.expand("trailing %", ctx) == "trailing %")
    }

    @Test func injectionIsNeutralized() {
        let evil = PlaceholderContext(sourcePath: "/x", targetPath: "/y", cursorName: "a; rm -rf ~ #.txt")
        let out = PlaceholderExpander.expand("echo %N", evil)
        #expect(out == "echo 'a; rm -rf ~ #.txt'")
        let r = Shell.run(out, in: FileManager.default.temporaryDirectory)
        #expect(r.output.trimmingCharacters(in: .whitespacesAndNewlines) == "a; rm -rf ~ #.txt")      // vypsáno doslovně, nic se nespustilo
    }
}

@Suite struct AssociationsAndSettingsTests {
    @Test func matchesByExtensionCaseInsensitively() {
        let list = [FileAssociation(extensions: ["JPG", "png"], command: "/Applications/Preview.app"), FileAssociation(extensions: ["md"], command: "typora")]
        #expect(Associations.match("Photo.JPG", in: list)?.command == "/Applications/Preview.app")
        #expect(Associations.match("notes.md", in: list)?.command == "typora")
        #expect(Associations.match("README", in: list) == nil && Associations.match("a.txt", in: list) == nil)
    }

    @Test func colorRules() {
        let rules = ColorRule.defaults
        #expect(ColorRule.color(for: "Backup.ZIP", isDirectory: false, rules: rules) == "#a64ca6")
        #expect(ColorRule.color(for: "a.txt", isDirectory: false, rules: rules) == nil)
        #expect(ColorRule.color(for: "photos.zip", isDirectory: true, rules: rules) == nil)
    }

    @Test func jsonStoreRoundTripAndDefaults() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let store = JSONStore<AppSettings>(name: "settings", directory: d)
        #expect(store.load(default: AppSettings()) == AppSettings())
        var s = AppSettings(); s.fontSize = 14; s.language = "en"; s.colorRules.append(ColorRule(masks: "*.log", hex: "#808080"))
        store.save(s)
        #expect(store.load(default: AppSettings()) == s)
        try "not json".write(to: store.file, atomically: true, encoding: .utf8)
        #expect(store.load(default: AppSettings()) == AppSettings())          // poškozený soubor = výchozí hodnoty
        let bar = JSONStore<[ButtonBarItem]>(name: "bar", directory: d)
        bar.save([ButtonBarItem(title: "Kopie", icon: "doc.on.doc", command: "cm_copy")])
        #expect(bar.load(default: []).first?.command == "cm_copy")
    }
}
