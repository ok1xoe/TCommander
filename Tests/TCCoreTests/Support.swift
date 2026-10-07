import Foundation

func makeTempDir() throws -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("tcommander-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u.resolvingSymlinksInPath()
}

@discardableResult
func write(_ dir: URL, _ name: String, _ content: String = "x", mtime: Date? = nil) throws -> URL {
    let u = dir.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.write(to: u, atomically: true, encoding: .utf8)
    if let mtime { try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: u.path) }
    return u
}
