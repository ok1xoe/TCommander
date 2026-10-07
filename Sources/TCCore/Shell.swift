import Foundation

public enum Shell {
    public struct Result: Sendable { public let output: String; public let status: Int32; public let timedOut: Bool }

    /// Spustí příkaz v zsh v daném adresáři; stdout i stderr dohromady, s časovým limitem.
    public static func run(_ command: String, in dir: URL, timeout: TimeInterval = 60) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", command]
        p.currentDirectoryURL = dir
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return Result(output: error.localizedDescription, status: -1, timedOut: false)
        }
        nonisolated(unsafe) var timedOut = false
        let item = DispatchWorkItem { timedOut = true; p.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        item.cancel()
        let limit = 200_000
        let text = String(decoding: data.prefix(limit), as: UTF8.self)
        return Result(output: data.count > limit ? text + "\n… (výstup zkrácen)" : text, status: p.terminationStatus, timedOut: timedOut)
    }
}
