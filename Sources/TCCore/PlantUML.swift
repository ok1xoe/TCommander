import Foundation

/// Vykreslení diagramů PlantUML pomocí skutečného PlantUML (příkaz `plantuml` nebo `plantuml.jar` + Java).
public enum PlantUML {
    public static let extensions: Set<String> = ["puml", "plantuml", "pu", "wsd", "iuml"]

    public static func isDiagramFile(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }

    /// Jak PlantUML spustit: samostatný příkaz, nebo `java -jar plantuml.jar`.
    public struct Launcher: Equatable, Sendable {
        public var executable: String
        public var prefixArguments: [String]
        public var description: String { prefixArguments.isEmpty ? executable : prefixArguments.last ?? executable }
    }

    public struct RenderError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    static let commandCandidates = ["/opt/homebrew/bin/plantuml", "/usr/local/bin/plantuml", "/usr/bin/plantuml", "/opt/local/bin/plantuml"]
    static let jarCandidates = ["/opt/homebrew/opt/plantuml/libexec/plantuml.jar", "/usr/local/opt/plantuml/libexec/plantuml.jar", "/usr/share/plantuml/plantuml.jar"]

    /// Cesta ke spustitelné Javě (JDK nainstalovaná v systému), nebo nil. Zástupný `/usr/bin/java` bez JDK se nepočítá.
    public static func javaExecutable() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        let out = Pipe(); p.standardOutput = out; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0, let home = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !home.isEmpty else { return nil }
        let java = home + "/bin/java"
        return FileManager.default.isExecutableFile(atPath: java) ? java : nil
    }

    /// Najde PlantUML: `configured` (příkaz nebo .jar z Nastavení; prázdné = automaticky), pak známá umístění (Homebrew, MacPorts, Application Support).
    public static func locate(configured: String = "", extraJarDirectories: [String] = []) -> Launcher? {
        if Sandbox.isSandboxed { return nil }                                          // sandbox neumožňuje spouštět Javu a cizí .jar
        let fm = FileManager.default
        func launcher(for path: String) -> Launcher? {
            let p = (path as NSString).expandingTildeInPath
            guard fm.fileExists(atPath: p) else { return nil }
            if p.lowercased().hasSuffix(".jar") {
                guard let java = javaExecutable() else { return nil }
                return Launcher(executable: java, prefixArguments: ["-Djava.awt.headless=true", "-jar", p])
            }
            return fm.isExecutableFile(atPath: p) ? Launcher(executable: p, prefixArguments: []) : nil
        }
        let trimmed = configured.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return launcher(for: trimmed) }                       // zadaná cesta se nepřebíjí automatikou
        for c in commandCandidates + jarCandidates { if let l = launcher(for: c) { return l } }
        for d in extraJarDirectories { if let l = launcher(for: (d as NSString).appendingPathComponent("plantuml.jar")) { return l } }
        return nil
    }

    /// Pořadí diagramu z názvu obrázku: `soubor.png` je první, další jsou `soubor_001.png`, `soubor_002.png` …
    static func diagramIndex(of url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent
        guard let r = name.range(of: #"_(\d+)$"#, options: .regularExpression), let n = Int(name[r].dropFirst()) else { return 0 }
        return n
    }

    /// Vykreslí všechny diagramy v souboru do PNG v dané složce (soubor se nekopíruje, takže fungují relativní `!include`).
    /// Vrací obrázky podle pořadí diagramů. Bez obrázku skončí chybou s výstupem PlantUML.
    public static func render(file: URL, into outputDirectory: URL, launcher: Launcher, timeout: TimeInterval = 90, dpi: Int = 144) throws -> [URL] {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launcher.executable)
        p.arguments = launcher.prefixArguments + ["-tpng", "-charset", "UTF-8", "-Sdpi=\(dpi)", "-output", outputDirectory.path, file.path]
        var env = ProcessInfo.processInfo.environment
        env["PLANTUML_LIMIT_SIZE"] = "16384"
        p.environment = env
        p.currentDirectoryURL = file.deletingLastPathComponent()
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        do { try p.run() } catch { throw RenderError(message: "PlantUML se nepodařilo spustit: \(error.localizedDescription)") }
        let deadline = Date().addingTimeInterval(timeout)
        var collected = Data()
        let reader = DispatchQueue(label: "plantuml.out")
        let group = DispatchGroup(); group.enter()
        reader.async { collected = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        while p.isRunning { if Date() > deadline { p.terminate(); throw RenderError(message: "PlantUML neodpověděl do \(Int(timeout)) s.") }; Thread.sleep(forTimeInterval: 0.05) }
        group.wait()
        let images = ((try? FileManager.default.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { diagramIndex(of: $0) < diagramIndex(of: $1) }
        if images.isEmpty {
            let text = String(decoding: collected, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw RenderError(message: text.isEmpty ? "PlantUML nevytvořil žádný diagram (soubor neobsahuje @startuml … @enduml?)." : text)
        }
        return images
    }
}
