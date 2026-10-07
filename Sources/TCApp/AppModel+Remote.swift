import AppKit
import TCCore

/// Zdroj přenosu: místní soubory, položky v archivu nebo na serveru.
enum StagedSource: @unchecked Sendable {
    case local([URL])
    case archive(ArchiveFileSystem, [String])
    case remote(RemoteFileSystem, [String])

    /// Připraví místní kopie (u archivu rozbalí, u serveru stáhne do dočasného adresáře).
    /// Vrací URL k dalšímu zpracování, dočasný adresář k úklidu a případně hotovou zprávu při chybě/zrušení.
    func stage(control: OperationControl, progress: (@Sendable (TransferProgress) -> Void)?) -> (locals: [URL], temp: URL?, early: OperationReport?) {
        switch self {
        case .local(let urls):
            return (urls, nil, nil)
        case .archive(let fs, let paths):
            let t = ArchiveFileSystem.temporaryRoot.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: t, withIntermediateDirectories: true)
            let r = fs.extract(paths, to: t, control: control, progress: progress)
            if !r.failures.isEmpty || r.cancelled { try? FileManager.default.removeItem(at: t); return ([], nil, r) }
            return (paths.map { t.appendingPathComponent(($0 as NSString).lastPathComponent) }, t, nil)
        case .remote(let fs, let paths):
            let t = ArchiveFileSystem.temporaryRoot.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: t, withIntermediateDirectories: true)
            let r = RemoteTransfer.download(fs, paths, to: t, control: control, progress: progress)
            if !r.failures.isEmpty || r.cancelled { try? FileManager.default.removeItem(at: t); return ([], nil, r) }
            return (paths.map { t.appendingPathComponent(($0 as NSString).lastPathComponent) }, t, nil)
        }
    }

    /// Po úspěšném přesunu smaže zdroj (u archivu se nepoužívá – z archivu se jen kopíruje).
    func deleteSources() {
        switch self {
        case .local(let urls): _ = FileOperations().delete(urls, toTrash: false)
        case .remote(let fs, let paths): for p in paths { try? fs.remove(URL(fileURLWithPath: p)) }
        case .archive: break
        }
    }
}

extension AppModel {
    func stagedSource() -> StagedSource? {
        let entries = source.targets
        guard !entries.isEmpty else { return nil }
        if let a = source.archiveFS { return .archive(a, entries.map(\.url.path)) }
        if let r = source.remote { return .remote(r, entries.map(\.url.path)) }
        return .local(entries.map(\.url))
    }

    // MARK: Přenosy

    func virtualTransfer(_ kind: TransferKind) {
        if target.insideArchive { copyIntoArchive(kind); return }
        if target.remote != nil { copyIntoRemote(kind); return }
        if source.insideArchive { extractFromArchive(kind); return }
        if source.remote != nil { downloadFromRemote(kind) }
    }

    private func copyIntoRemote(_ kind: TransferKind) {
        guard let dst = target.remote, let staged = stagedSource() else { return }
        let entries = source.targets
        let move = kind == .move
        if case .archive = staged, move { Dialogs.error("Archiv", "Z archivu lze jen kopírovat."); return }
        let what = entries.count == 1 ? "„\(entries[0].name)“" : "\(entries.count) položek"
        guard Dialogs.confirm(title: (move ? "Přesunout " : "Nahrát ") + what + " na server?",
                              message: dst.connection.displayName + target.path.path, ok: move ? "Přesunout" : "Nahrát") else { return }
        let existing = entries.filter { e in target.entries.contains { $0.name == e.name && !$0.isParentLink } }
        var policy = ConflictPolicy.overwrite
        if !existing.isEmpty {
            guard let p = Dialogs.conflictPolicy(count: existing.count, example: existing[0].name) else { return }
            policy = p
        }
        let chosen = policy, destDir = target.path.path
        jobs.enqueue(title: "\(move ? "Přesunout" : "Nahrát") \(what) na server", work: { control, progress in
            let (locals, temp, early) = staged.stage(control: control, progress: progress)
            if let early { return early }
            defer { if let temp { try? FileManager.default.removeItem(at: temp) } }
            let r = RemoteTransfer.upload(dst, locals, into: destDir, policy: chosen, control: control, progress: progress)
            if move && r.failures.isEmpty && !r.cancelled { staged.deleteSources() }
            return r
        }, onFinish: { [weak self] r in self?.finish(r, success: move ? "Přesunuto na server" : "Nahráno") })
    }

    private func downloadFromRemote(_ kind: TransferKind) {
        guard let fs = source.remote else { return }
        let entries = source.targets
        guard !entries.isEmpty else { return }
        let move = kind == .move
        let what = entries.count == 1 ? "„\(entries[0].name)“" : "\(entries.count) položek"
        guard let text = Dialogs.prompt(title: (move ? "Přesunout " : "Stáhnout ") + what, message: "Cíl:", initial: target.path.path + "/", ok: move ? "Přesunout" : "Stáhnout"),
              let dest = resolveDirectory(text, base: target.path) else { return }
        let paths = entries.map(\.url.path)
        let existing = entries.filter { FileManager.default.fileExists(atPath: dest.appendingPathComponent($0.name).path) }
        var policy = ConflictPolicy.overwrite
        if !existing.isEmpty {
            guard let p = Dialogs.conflictPolicy(count: existing.count, example: dest.appendingPathComponent(existing[0].name).path) else { return }
            policy = p
        }
        let chosen = policy
        jobs.enqueue(title: "\(move ? "Přesunout" : "Stáhnout") \(what) ze serveru", work: { control, progress in
            let r = RemoteTransfer.download(fs, paths, to: dest, policy: chosen, control: control, progress: progress)
            if move && r.failures.isEmpty && !r.cancelled { for p in paths { try? fs.remove(URL(fileURLWithPath: p)) } }
            return r
        }, onFinish: { [weak self] r in self?.finish(r, success: move ? "Přesunuto ze serveru" : "Staženo") })
    }

    // MARK: Úpravy na serveru

    func deleteFromRemote() {
        guard let fs = source.remote else { return }
        let targets = source.targets
        guard !targets.isEmpty else { return }
        let urls = targets.map(\.url)
        let what = targets.count == 1 ? "„\(targets[0].name)“" : "\(targets.count) položek"
        guard Dialogs.confirm(title: "Smazat na serveru?", message: "\(what) bude trvale odstraněno (nelze vrátit).", ok: "Smazat", destructive: true) else { return }
        jobs.enqueue(title: "Smazat na serveru: \(what)", work: { control, progress in
            var rep = OperationReport()
            var p = TransferProgress(); p.filesTotal = urls.count
            for u in urls {
                guard control.checkpoint() else { rep.cancelled = true; break }
                p.current = u.lastPathComponent
                do { try fs.remove(u); rep.succeeded += 1 } catch { rep.failures.append(.init(url: u, message: error.localizedDescription)) }
                p.filesDone += 1; progress(p)
            }
            return rep
        }, onFinish: { [weak self] r in self?.finish(r, success: "Smazáno na serveru") })
    }

    func renameOnRemote() {
        guard let fs = source.remote, let e = source.targets.first, source.targets.count == 1 else { return }
        guard let name = Dialogs.prompt(title: "Přejmenovat na serveru", message: "Nový název:", initial: e.name, ok: "Přejmenovat") else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !n.contains("/"), n != e.name else { return }
        let from = e.url, to = e.url.deletingLastPathComponent().appendingPathComponent(n)
        busy = "Přejmenovávám…"
        Task {
            let r = await Task.detached { Result { try fs.move(from, to: to) } }.value
            self.busy = nil
            if case .failure(let err) = r { Dialogs.error("Přejmenování selhalo", err.localizedDescription) }
            self.source.unmarkAll(); self.source.reload(select: to)
        }
    }

    func makeDirectoryOnRemote() {
        guard let fs = source.remote else { return }
        guard let name = Dialogs.prompt(title: "Nový adresář na serveru", message: "Název (lze i vnořený a/b/c):", initial: "", ok: "Vytvořit") else { return }
        let n = name.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !n.isEmpty else { return }
        let dir = source.path.appendingPathComponent(n)
        let top = source.path.appendingPathComponent(String(n.split(separator: "/").first ?? ""))
        busy = "Vytvářím adresář…"
        Task {
            let r = await Task.detached { Result { try fs.createDirectory(dir) } }.value
            self.busy = nil
            if case .failure(let err) = r { Dialogs.error("Vytvoření adresáře selhalo", err.localizedDescription) }
            self.source.reload(select: top)
        }
    }

    /// Soubor ze serveru se stáhne do dočasného adresáře a předá dál (otevření, Lister, editor).
    func withRemoteFile(_ entry: FileEntry, _ then: @escaping (URL) -> Void) {
        guard let fs = source.remote, !entry.isDirectory else { return }
        busy = "Stahuji „\(entry.name)“…"
        let remote = entry.url.path, name = entry.name
        Task {
            let r = await Task.detached { () -> Result<URL, Error> in
                Result {
                    let dir = ArchiveFileSystem.temporaryRoot.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    let local = dir.appendingPathComponent(name)
                    try fs.downloadFile(remotePath: remote, local: local)
                    return local
                }
            }.value
            self.busy = nil
            switch r {
            case .success(let url): then(url)
            case .failure(let e): Dialogs.error("Soubor nelze stáhnout", e.localizedDescription)
            }
        }
    }

    // MARK: Připojení

    func connectToServer() {
        guard let r = ConnectForm(saved: connections.items).run() else { return }
        if r.save { connections.upsert(r.connection); Keychain.set(r.password, for: r.connection.id) }
        open(connection: r.connection, password: r.password)
    }

    func connect(saved c: SavedConnection) {
        var pw = Keychain.password(for: c.id) ?? ""
        if pw.isEmpty && !c.user.isEmpty && c.kind != .smb {
            guard let p = Dialogs.prompt(title: "Heslo pro \(c.name)", message: "\(c.user)@\(c.host)", initial: "", ok: "Připojit", secure: true) else { return }
            pw = p
        }
        open(connection: c, password: pw)
    }

    func disconnect() { source.leaveRemote() }

    func forget(_ c: SavedConnection) { connections.remove(c); Keychain.delete(c.id) }

    private func open(connection c: SavedConnection, password: String) {
        switch c.kind {
        case .ftp, .ftpExplicitTLS, .ftpsImplicit: connectFTP(c, password)
        case .sftp: Dialogs.error("SFTP", "SFTP přijde v další části.")
        case .smb, .webdav, .webdavs: mountVolume(c, password)
        }
    }

    func connectFTP(_ c: SavedConnection, _ password: String) {
        let conn = c.ftpConnection(password: password)
        let fs = RemoteFileSystem(connection: conn)
        let hidden = showHidden
        let tab = source
        busy = "Připojuji k \(c.host)…"
        Task {
            let result = await Task.detached { () -> Result<(String, [FileEntry]), Error> in
                let initial = RemoteFileSystem.normalize(conn.initialPath)
                do { return .success((initial, try fs.list(URL(fileURLWithPath: initial), includeHidden: hidden))) }
                catch {
                    if initial != "/", let items = try? fs.list(URL(fileURLWithPath: "/"), includeHidden: hidden) { return .success(("/", items)) }
                    return .failure(error)
                }
            }.value
            self.busy = nil
            switch result {
            case .success(let (path, items)):
                tab.attachRemote(fs, path: path, items: items)
                self.status = "Připojeno: \(conn.displayName)"
            case .failure(let e):
                Dialogs.error("Připojení k serveru selhalo", e.localizedDescription)
            }
        }
    }

    private func mountVolume(_ c: SavedConnection, _ password: String) {
        guard let url = c.mountURL() else { return }
        busy = "Připojuji svazek \(c.host)…"
        let tab = source
        Task {
            do {
                let mp = try await NetworkMounts.mount(url, user: c.user, password: password)
                self.busy = nil
                tab.navigateLocal(mp)
                self.status = "Připojeno: \(mp.path)"
            } catch {
                self.busy = nil
                Dialogs.error("Připojení svazku selhalo", error.localizedDescription)
            }
        }
    }
}
