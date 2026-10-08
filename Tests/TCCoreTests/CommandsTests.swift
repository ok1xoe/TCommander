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

@Suite struct SettingsCompatibilityTests {
    @Test func olderSettingsFileKeepsUserValuesAndGetsNewDefaults() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let store = JSONStore<AppSettings>(name: "settings", directory: d)
        // soubor vytvořený starší verzí: bez columnSets, panelsStacked a colorRules
        try #"{"editorApp": "/Applications/Typora.app", "fontSize": 15, "deleteToTrash": false, "showHidden": true}"#.write(to: store.file, atomically: true, encoding: .utf8)
        let s = store.load(default: AppSettings())
        #expect(s.editorApp == "/Applications/Typora.app" && s.fontSize == 15 && !s.deleteToTrash && s.showHidden)
        #expect(s.columnSets == ColumnSet.defaults && s.colorRules == ColorRule.defaults && !s.panelsStacked && s.language == "en")
        #expect(s.columnSets.contains { $0.name == "Média" })
        store.save(s)
        #expect(store.load(default: AppSettings()) == s)          // zápis a čtení nových dat zůstává konzistentní
    }
}

@Suite struct ShortcutRoundTripTests {
    @Test func everyRegistryShortcutSurvivesTextRoundTrip() {
        for c in CommandRegistry.all { for s in c.defaultShortcuts { #expect(Shortcut(s.description) == s, "\(c.id): \(s)") } }
        #expect(Shortcut("kp+") == Shortcut(key: "kp+") && Shortcut("ctrl+kp-")?.modifiers == [.ctrl])
        #expect(Shortcut("ctrl++")?.key == "+" && Shortcut("+")?.key == "+")
    }
}

@Suite struct LocalizationTests {
    @Test func translatesOnlyWhenEnglishIsSelected() {
        #expect(Localization.translate("Soubor", language: "cs") == "Soubor" && Localization.translate("Soubor", language: "en") == "File")
        #expect(Localization.translate("Neznámý text", language: "en") == "Neznámý text")
    }

    @Test func everyEntryHasARealTranslation() {
        for (cs, en) in Localization.en {
            #expect(!en.isEmpty && (en != cs || Localization.untranslated.contains(cs)), "\(cs)")
            #expect(!en.contains(where: { "ěščřžýáíéúůťďň".contains($0) }), "\(en) obsahuje českou diakritiku")
        }
        #expect(Localization.en.count > 100)
    }

    @Test func menuStringsInSourcesAreCovered() throws {
        // každý český řetězec předaný funkci L(...) v aplikaci musí mít překlad
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/TCApp")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        let re = try NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)"\)"#)
        var missing: [String] = []
        for f in files where f.hasSuffix(".swift") {
            let text = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let key = (text as NSString).substring(with: m.range(at: 1))
                if key.contains("\\(") { continue }                       // složené texty překládají fráze
                if Localization.en[key] == nil && Localization.enMore[key] == nil && !Localization.untranslated.contains(key) { missing.append("\(f): \(key)") }
            }
        }
        #expect(missing.isEmpty, "\(missing)")
    }
}

@Suite struct FileOpenPolicyTests {
    let bin = Data([0, 1, 2, 3]), text = Data("hello".utf8)

    @Test func viewByFileType() {
        func v(_ n: String, _ s: Data = Data()) -> FileOpenPolicy.ViewAction { FileOpenPolicy.viewAction(fileName: n, sample: s, associations: []) }
        for n in ["a.txt", "a.swift", "a.json", "a.md", "a.png", "a.jpg", "a.pdf", "a.mp3", "a.mp4", "a.html", "README", "a.unknownext"] { #expect(v(n) == .lister, "\(n)") }
        for n in ["a.docx", "a.xlsx", "a.pptx", "a.pages", "a.numbers", "a.key"] { #expect(v(n) == .quickLook, "\(n)") }
    }

    @Test func editByFileType() {
        func e(_ n: String, _ s: Data = Data()) -> FileOpenPolicy.EditAction { FileOpenPolicy.editAction(fileName: n, sample: s, associations: []) }
        for n in ["a.txt", "a.swift", "a.json", "a.md", "a.xml", "a.sh", "a.yaml", "a.plist", "a.py", "a.css", "a.html"] { #expect(e(n) == .editor, "\(n)") }
        for n in ["a.png", "a.jpg", "a.pdf", "a.docx", "a.mp4", "a.mp3", "a.zip"] { #expect(e(n) == .systemDefault, "\(n)") }
        #expect(e("Makefile", text) == .editor && e("data.zzqq", text) == .editor)          // neznámé: podle obsahu
        #expect(e("blob.zzqq", bin) == .systemDefault && e("noext", bin) == .systemDefault)
    }

    @Test func associationsOverrideDefaults() {
        let list = [FileAssociation(extensions: ["png"], command: "", viewCommand: "open -a Preview %F", editCommand: "/Applications/Pixelmator Pro.app"),
                    FileAssociation(extensions: ["txt"], command: "x", editCommand: "")]
        #expect(FileOpenPolicy.viewAction(fileName: "A.PNG", associations: list) == .command("open -a Preview %F"))
        #expect(FileOpenPolicy.editAction(fileName: "a.png", associations: list) == .command("/Applications/Pixelmator Pro.app"))
        #expect(FileOpenPolicy.editAction(fileName: "a.txt", associations: list) == .editor)        // prázdný příkaz = výchozí pravidla
        #expect(FileOpenPolicy.viewAction(fileName: "a.docx", associations: list) == .quickLook)
    }

    @Test func olderAssociationsDecode() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","extensions":["md"],"command":"typora","parameters":""}]"#
        let list = try JSONDecoder().decode([FileAssociation].self, from: Data(json.utf8))
        #expect(list.count == 1 && list[0].viewCommand.isEmpty && list[0].editCommand.isEmpty && list[0].command == "typora")
    }
}

@Suite struct PhraseTranslationTests {
    func en(_ s: String) -> String { Localization.translate(s, language: "en") }

    @Test func allPhrasePatternsCompile() {
        #expect(Localization.phrases.count > 100)
        for p in Localization.phrases { #expect((try? NSRegularExpression(pattern: p.pattern)) != nil, "\(p.pattern)") }
    }

    @Test func translatesStaticAndCompositeTexts() {
        #expect(en("Zrušit") == "Cancel" && en("Přesunout do koše?") == "Move to Trash?" && en("Soubor nelze otevřít") == "The file cannot be opened")
        #expect(en("37 souborů, 42 adresářů · 1,1 MB") == "37 files, 42 folders · 1,1 MB")
        #expect(en("Označeno 3 z 40 · 12 KB") == "Marked 3 of 40 · 12 KB")
        #expect(en("„report.pdf“ bude trvale odstraněno (nelze vrátit).") == "“report.pdf” will be permanently removed (cannot be undone).")
        #expect(en("Kopírovat 5 položek") == "Copy 5 items" && en("Přesunout „a.txt“") == "Move “a.txt”")
        #expect(en("Archiv je v pořádku (12 souborů).") == "The archive is OK (12 files).")
        #expect(en("Rozdílů: 4 · k provedení: 3 (kopií: 2, smazání: 1)") == "Differences: 4 · to perform: 3 (copies: 2, deletions: 1)")
        #expect(en("Připojuji k ftp.example.com…") == "Connecting to ftp.example.com…")
        #expect(en("Offset je mimo soubor (velikost 100 bajtů)") == "Offset is outside the file (size 100 bytes)")
        #expect(en("Část 2 z 5 (bajty 100–200)") == "Part 2 of 5 (bytes 100–200)")
        #expect(Localization.translate("Zrušit", language: "cs") == "Zrušit")            // čeština se nemění
        #expect(en("report-final.pdf") == "report-final.pdf")                               // názvy souborů zůstávají
    }

    @Test func translationsContainNoCzechLettersExceptTheLanguageName() {
        for (cs, t) in Localization.enMore where cs != "Čeština" {
            #expect(!t.isEmpty, "\(cs)")
            #expect(!t.contains(where: { "ěščřžýáíéúůťďňĚŠČŘŽÝÁÍÉÚŮŤĎŇ".contains($0) }), "\(cs) → \(t)")
        }
    }
}

@Suite struct CommandTranslationTests {
    @Test func everyCommandTitleHasAnEnglishTranslation() {
        for c in CommandRegistry.all {
            #expect(Localization.en[c.title] != nil || Localization.enMore[c.title] != nil, "chybí překlad příkazu „\(c.title)“")
        }
    }
}

@Suite struct LocalizationTableIntegrityTests {
    /// Slovník s duplicitním klíčem v literálu shodí aplikaci při startu (fatalError), proto se klíče kontrolují ve zdroji.
    @Test func dictionaryLiteralsHaveNoDuplicateKeys() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/TCCore/Localization.swift")
        let text = try String(contentsOf: file, encoding: .utf8)
        let pair = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)"\s*:\s*""#)
        for name in ["public static let en: [String: String] = [", "public static let enMore: [String: String] = ["] {
            let start = try #require(text.range(of: name)).upperBound
            let end = try #require(text.range(of: "\n    ]\n", range: start..<text.endIndex)).lowerBound
            let body = String(text[start..<end])
            var seen = Set<String>(), dups: [String] = []
            for m in pair.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                let k = (body as NSString).substring(with: m.range(at: 1))
                if !seen.insert(k).inserted { dups.append(k) }
            }
            #expect(dups.isEmpty, "\(name): \(dups)")
        }
    }
}
