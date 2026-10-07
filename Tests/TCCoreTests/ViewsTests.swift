import Testing
import Foundation
@testable import TCCore

@MainActor @Suite struct TabLockAndSetsTests {
    func tree() throws -> URL {
        let d = try makeTempDir()
        try write(d, "a.txt"); try write(d, "sub/b.txt"); try write(d, "other/c.txt")
        return d
    }

    @Test func lockedTabOpensNewTabInsteadOfNavigating() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let g = PanelGroup(paths: [d])
        g.active.locked = true
        g.active.navigate(to: d.appendingPathComponent("sub"))
        #expect(g.tabs.count == 2 && g.activeIndex == 1 && g.active.path.lastPathComponent == "sub" && g.tabs[0].path == d.standardizedFileURL)
        // obnovení stejného adresáře (reload) nová karta nevyvolá
        g.tabs[0].reload()
        #expect(g.tabs.count == 2)
        // odemčená karta naviguje normálně
        g.active.navigate(to: d)
        #expect(g.tabs.count == 2 && g.active.path == d.standardizedFileURL)
        // zamčená karta: „nahoru“ také otevře novou
        g.tabs[0].locked = true; g.select(0)
        g.active.navigate(to: d.appendingPathComponent("other"))
        #expect(g.tabs.count == 3)
    }

    @Test func replaceTabsRestoresLockedFlagsAndActive() throws {
        let d = try tree(); defer { try? FileManager.default.removeItem(at: d) }
        let g = PanelGroup(paths: [d])
        g.replaceTabs([(d, true), (d.appendingPathComponent("sub"), false)], active: 1)
        #expect(g.tabs.map(\.locked) == [true, false] && g.activeIndex == 1 && g.active.path.lastPathComponent == "sub")
        g.tabs[0].navigate(to: d.appendingPathComponent("other"))        // nové karty mají obsluhu zámku
        #expect(g.tabs.count == 3)
        g.replaceTabs([], active: 5)
        #expect(g.tabs.count == 1 && g.activeIndex == 0)
    }

    @Test func favoriteSetRoundTripsAsJSON() throws {
        let set = FavoriteTabSet(name: "Práce", left: [.init(path: "/Users/me/a", locked: true), .init(path: "/tmp")], right: [.init(path: "/")], leftActive: 1, rightActive: 0)
        let back = try JSONDecoder().decode(FavoriteTabSet.self, from: JSONEncoder().encode(set))
        #expect(back == set)
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let store = JSONStore<[FavoriteTabSet]>(name: "fav", directory: d)
        store.save([set]); #expect(store.load(default: []) == [set])
    }
}

@Suite struct ColumnsAndEntryTests {
    @Test func parsesColumnSets() {
        #expect(ColumnSet.parse("size, name, date, size, bogus, KIND") == [.name, .size, .date, .kind])
        #expect(ColumnSet.parse("") == [.name])
        #expect(ColumnSet.defaults.allSatisfy { $0.columns.first == .name })
        #expect(PanelColumn.allCases.allSatisfy { !$0.title.isEmpty && $0.defaultWidth > 0 })
    }

    @Test func statProvidesCreationAccessAndOwner() throws {
        let d = try makeTempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let f = try write(d, "f.txt", "x")
        let e = try LocalFileSystem().stat(f)
        #expect(e.ownerID == getuid())
        #expect(abs((e.created ?? .distantPast).timeIntervalSinceNow) < 60 && abs((e.accessed ?? .distantPast).timeIntervalSinceNow) < 60)
        #expect(e.modified != nil && e.permissions != 0)
    }

    @Test func viewModesIncludeTree() {
        #expect(ViewMode.allCases == [.full, .brief, .thumbnails, .tree])
        #expect(AppSettings().columnSets == ColumnSet.defaults)
    }
}
