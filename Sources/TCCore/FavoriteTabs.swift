import Foundation

/// Uložená sada karet obou panelů (Favorite tabs).
public struct FavoriteTabSet: Codable, Hashable, Identifiable, Sendable {
    public struct Tab: Codable, Hashable, Sendable {
        public var path: String
        public var locked: Bool
        public init(path: String, locked: Bool = false) { self.path = path; self.locked = locked }
    }
    public var id: UUID
    public var name: String
    public var left: [Tab]
    public var right: [Tab]
    public var leftActive: Int
    public var rightActive: Int

    public init(id: UUID = UUID(), name: String, left: [Tab], right: [Tab], leftActive: Int = 0, rightActive: Int = 0) {
        self.id = id; self.name = name; self.left = left; self.right = right
        self.leftActive = leftActive; self.rightActive = rightActive
    }
}

/// Pojmenovaná sada sloupců (vlastní pohled).
public struct ColumnSet: Codable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var columns: [PanelColumn]
    public init(name: String, columns: [PanelColumn]) { self.name = name; self.columns = columns }

    public static let defaults: [ColumnSet] = [
        ColumnSet(name: "Plný", columns: PanelColumn.standard),
        ColumnSet(name: "Rozšířený", columns: [.name, .ext, .size, .date, .created, .kind, .owner, .attr]),
        ColumnSet(name: "Kompaktní", columns: [.name, .size, .date]),
    ]

    /// Z textu "name, size, date" (neznámé názvy se přeskočí; název je vždy první).
    public static func parse(_ text: String) -> [PanelColumn] {
        var cols = text.split(separator: ",").compactMap { PanelColumn(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
        cols.removeAll { $0 == .name }
        var seen = Set<PanelColumn>()
        return [.name] + cols.filter { seen.insert($0).inserted }
    }
}
