import Foundation

/// Podpora synchronizace adresáře s archivem: archiv se rozbalí do dočasné složky a po synchronizaci znovu zabalí.
public enum ArchiveSyncSupport {
    public struct Staged: Sendable {
        public let archive: URL
        public let directory: URL
        public let format: ArchiveFormat?
    }

    public static func extractToTemporary(_ archive: URL, control: OperationControl = OperationControl()) throws -> Staged {
        let fs = try ArchiveFileSystem(archiveURL: archive)
        let dir = ArchiveFileSystem.temporaryRoot.appendingPathComponent("sync-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let r = fs.extractAll(to: dir, control: control)
        if let f = r.failures.first { try? FileManager.default.removeItem(at: dir); throw ArchiveError(message: f.message) }
        return Staged(archive: archive, directory: dir, format: ArchiveFormat.detect(fileName: archive.lastPathComponent))
    }

    /// Znovu vytvoří archiv z obsahu dočasné složky (formát zůstane stejný).
    public static func repack(_ staged: Staged, control: OperationControl = OperationControl(),
                              progress: (@Sendable (TransferProgress) -> Void)? = nil) -> OperationReport {
        guard let format = staged.format else {
            var r = OperationReport(); r.failures.append(.init(url: staged.archive, message: "Tento formát archivu nelze upravovat (jen čtení)")); return r
        }
        let children = ((try? FileManager.default.contentsOfDirectory(at: staged.directory, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return ArchiveWriter.create(staged.archive, format: format, sources: children, control: control, progress: progress)
    }

    public static func cleanup(_ staged: Staged) { try? FileManager.default.removeItem(at: staged.directory) }
}
