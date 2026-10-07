import Foundation

/// Sleduje změny v obsahu adresáře (vznik, smazání, přejmenování položek) a po krátké prodlevě zavolá `handler`.
public final class DirectoryWatcher: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "macTC.DirectoryWatcher")

    public init?(url: URL, debounce: TimeInterval = 0.25, handler: @escaping @Sendable () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: queue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.pending?.cancel()
            let item = DispatchWorkItem(block: handler)
            self.pending = item
            self.queue.asyncAfter(deadline: .now() + debounce, execute: item)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    public func stop() { pending?.cancel(); source.cancel() }
    deinit { stop() }
}
