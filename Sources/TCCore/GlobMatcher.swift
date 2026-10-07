import Foundation

/// Masky ve stylu TC: "*.txt;*.doc", "a*", "?x.*"; velikost písmen se neřeší.
public enum GlobMatcher {
    public static func patterns(_ masks: String) -> [String] {
        masks.split(whereSeparator: { $0 == ";" || $0 == " " || $0 == "," }).map { p in
            p == "*.*" ? "*" : String(p)
        }
    }

    public static func matches(_ name: String, masks: String) -> Bool {
        patterns(masks).contains { fnmatch($0, name, FNM_CASEFOLD) == 0 }
    }
}
