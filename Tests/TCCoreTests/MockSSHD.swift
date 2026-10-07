import Foundation
@testable import TCCore

/// Uživatelský `sshd` na localhostu (bez roota, jen klíčová autentizace) pro testy SFTP.
final class MockSSHD {
    let port: Int
    let dir: URL
    let clientKey: String
    let knownHosts: String
    private let process = Process()

    /// Lze na tomto stroji `sshd` spustit? (zjistí se jednou; testy se jinak přeskočí)
    static let available: Bool = {
        guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/sshd"), FileManager.default.isExecutableFile(atPath: "/usr/bin/sftp") else { return false }
        guard let s = try? MockSSHD() else { return false }
        s.stop(); return true
    }()

    init() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tcommander-sshd-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func sh(_ c: String) throws {
            let r = Shell.run(c, in: dir)
            guard r.status == 0 else { throw NSError(domain: "MockSSHD", code: Int(r.status), userInfo: [NSLocalizedDescriptionKey: r.output]) }
        }
        self.dir = dir
        try sh("ssh-keygen -q -t ed25519 -N '' -f hostkey && ssh-keygen -q -t ed25519 -N '' -f clientkey && cp clientkey.pub authorized_keys && chmod 600 authorized_keys hostkey clientkey")
        let freePort = Shell.run("python3 -c \"import socket;s=socket.socket();s.bind(('127.0.0.1',0));print(s.getsockname()[1])\"", in: dir).output
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = Int(freePort) else { throw NSError(domain: "MockSSHD", code: 2) }
        self.port = p
        self.clientKey = dir.appendingPathComponent("clientkey").path
        self.knownHosts = dir.appendingPathComponent("known_hosts").path
        try """
        ListenAddress 127.0.0.1
        Port \(p)
        HostKey \(dir.path)/hostkey
        PidFile \(dir.path)/sshd.pid
        AuthorizedKeysFile \(dir.path)/authorized_keys
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        PubkeyAuthentication yes
        UsePAM no
        StrictModes no
        Subsystem sftp /usr/libexec/sftp-server
        """.write(to: dir.appendingPathComponent("sshd_config"), atomically: true, encoding: .utf8)
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/sshd")
        process.arguments = ["-D", "-e", "-f", dir.appendingPathComponent("sshd_config").path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        // čekání na naslouchání
        var ok = false
        for _ in 0..<60 { if Shell.run("nc -z 127.0.0.1 \(p)", in: dir).status == 0 { ok = true; break }; Thread.sleep(forTimeInterval: 0.1) }
        guard ok, process.isRunning else { process.terminate(); throw NSError(domain: "MockSSHD", code: 3, userInfo: [NSLocalizedDescriptionKey: "sshd se nespustil"]) }
    }

    func connection(multiplex: Bool = false, identity: String? = nil) -> SFTPConnection {
        SFTPConnection(host: "127.0.0.1", port: port, user: NSUserName(), identityFile: identity ?? clientKey,
                       knownHostsFile: knownHosts, strictHostKeyChecking: "no", multiplex: multiplex)
    }

    func stop() { process.terminate(); process.waitUntilExit(); try? FileManager.default.removeItem(at: dir) }
}
