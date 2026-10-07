import Foundation

/// Ukázkové pluginy dodávané s aplikací (složka `PluginExamples` v balíčku, ve vývoji `docs/plugin-examples`) a jejich instalace.
public enum PluginExamples {
    public struct Result: Equatable, Sendable {
        public var installed: [String] = []
        public var alreadyPresent: [String] = []
        public var failed: [String] = []
    }

    /// Najde složku s ukázkami: v balíčku aplikace, jinak od spustitelného souboru směrem nahoru (`docs/plugin-examples` ve zdrojích).
    public static func sourceDirectory(resources: URL? = Bundle.main.resourceURL, executable: URL? = Bundle.main.executableURL) -> URL? {
        let fm = FileManager.default
        if let r = resources?.appendingPathComponent("PluginExamples"), fm.fileExists(atPath: r.path) { return r }
        var dir = executable?.deletingLastPathComponent()
        for _ in 0..<8 {
            guard let d = dir else { break }
            let candidate = d.appendingPathComponent("docs/plugin-examples")
            if fm.fileExists(atPath: candidate.path) { return candidate }
            dir = d.deletingLastPathComponent()
        }
        return nil
    }

    /// Názvy ukázkových pluginů (podsložky s `plugin.json`).
    public static func available(in source: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: source.path)) ?? []
        return names.filter { FileManager.default.fileExists(atPath: source.appendingPathComponent($0).appendingPathComponent("plugin.json").path) }.sorted()
    }

    /// Zkopíruje ukázkové pluginy do `destination`; již existující složky se nepřepisují (uživatelské úpravy zůstanou).
    public static func install(from source: URL, to destination: URL) -> Result {
        let fm = FileManager.default
        var result = Result()
        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in available(in: source) {
            let target = destination.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path) { result.alreadyPresent.append(name); continue }
            do {
                try fm.copyItem(at: source.appendingPathComponent(name), to: target)
                try? fm.removeItem(at: target.appendingPathComponent("__pycache__"))
                result.installed.append(name)
            } catch { result.failed.append(name) }
        }
        return result
    }
}
