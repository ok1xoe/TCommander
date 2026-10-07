import Foundation
@testable import TCCore

/// Testovací FTP server (Python, jen localhost) – umožňuje ověřit klienta bez externí služby.
final class MockFTP {
    static let script = #"""
import socket, socketserver, sys, os, time, threading, posixpath

ROOT = os.path.realpath(sys.argv[1])
NO_MLSD = "--no-mlsd" in sys.argv
PASSWORD = "secret"

class H(socketserver.StreamRequestHandler):
    def send(self, s):
        self.wfile.write((s + "\r\n").encode("utf-8")); self.wfile.flush()

    def real(self, p):
        p = p if p.startswith("/") else posixpath.join(self.cwd, p)
        n = posixpath.normpath(p)
        full = os.path.realpath(os.path.join(ROOT, n.lstrip("/")))
        if not (full == ROOT or full.startswith(ROOT + os.sep)): raise Exception("outside root")
        return full

    def handle(self):
        self.cwd = "/"; self.authed = False; self.user = None; self.rest = 0; self.pasv = None; self.rnfr = None
        self.send("220 mock ready")
        while True:
            line = self.rfile.readline()
            if not line: break
            line = line.decode("utf-8", "replace").rstrip("\r\n")
            cmd, _, arg = line.partition(" ")
            cmd = cmd.upper()
            fn = getattr(self, "do_" + cmd, None)
            if fn is None: self.send("502 not implemented"); continue
            if cmd not in ("USER", "PASS", "QUIT", "FEAT", "SYST", "OPTS", "AUTH") and not self.authed:
                self.send("530 login first"); continue
            try: fn(arg)
            except SystemExit: break
            except Exception as e: self.send("550 " + str(e))

    def do_USER(self, a): self.user = a; self.send("331 password please")
    def do_PASS(self, a):
        if self.user == "tester" and a == PASSWORD: self.authed = True; self.send("230 ok")
        else: self.send("530 login incorrect")
    def do_AUTH(self, a): self.send("502 no tls")
    def do_SYST(self, a): self.send("215 UNIX Type: L8")
    def do_FEAT(self, a): self.send("211-Features:\r\n UTF8\r\n MDTM\r\n SIZE\r\n REST STREAM\r\n211 End")
    def do_OPTS(self, a): self.send("200 ok")
    def do_NOOP(self, a): self.send("200 ok")
    def do_QUIT(self, a): self.send("221 bye"); raise SystemExit
    def do_PWD(self, a): self.send('257 "%s" is current' % self.cwd)
    def do_TYPE(self, a): self.send("200 type set")
    def do_CWD(self, a):
        p = self.real(a)
        if not os.path.isdir(p): self.send("550 no such directory"); return
        self.cwd = posixpath.normpath(a if a.startswith("/") else posixpath.join(self.cwd, a)); self.send("250 ok")
    def do_CDUP(self, a): self.do_CWD("..")
    def do_SIZE(self, a):
        p = self.real(a)
        if os.path.isfile(p): self.send("213 %d" % os.path.getsize(p))
        else: self.send("550 not a file")
    def do_MDTM(self, a):
        p = self.real(a)
        if os.path.exists(p): self.send("213 " + time.strftime("%Y%m%d%H%M%S", time.gmtime(os.path.getmtime(p))))
        else: self.send("550 no such file")
    def do_REST(self, a): self.rest = int(a); self.send("350 restarting")

    def open_pasv(self):
        s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(1); s.settimeout(10)
        if self.pasv: self.pasv.close()
        self.pasv = s; return s.getsockname()[1]
    def do_PASV(self, a):
        port = self.open_pasv(); self.send("227 Entering Passive Mode (127,0,0,1,%d,%d)" % (port >> 8, port & 255))
    def do_EPSV(self, a):
        port = self.open_pasv(); self.send("229 Entering Extended Passive Mode (|||%d|)" % port)
    def data(self):
        if not self.pasv: raise Exception("no data connection")
        c, _ = self.pasv.accept(); self.pasv.close(); self.pasv = None; return c

    def fmt_list(self, d):
        out = []
        for n in sorted(os.listdir(d)):
            p = os.path.join(d, n); s = os.lstat(p)
            kind = "d" if os.path.isdir(p) else "-"
            t = time.strftime("%b %e %H:%M", time.gmtime(s.st_mtime))
            out.append("%srw-r--r--   1 owner group %12d %s %s" % (kind, s.st_size, t, n))
        return "\r\n".join(out) + ("\r\n" if out else "")
    def fmt_mlsd(self, d):
        out = []
        for n in sorted(os.listdir(d)):
            p = os.path.join(d, n); s = os.lstat(p)
            kind = "dir" if os.path.isdir(p) else "file"
            out.append("type=%s;size=%d;modify=%s; %s" % (kind, s.st_size, time.strftime("%Y%m%d%H%M%S", time.gmtime(s.st_mtime)), n))
        return "\r\n".join(out) + ("\r\n" if out else "")
    def send_listing(self, a, fmt):
        a = "" if a.startswith("-") else a
        d = self.real(a or ".")
        if not os.path.isdir(d): self.send("550 not a directory"); return
        self.send("150 here comes the listing")
        c = self.data(); c.sendall(fmt(d).encode("utf-8")); c.close(); self.send("226 done")
    def do_LIST(self, a): self.send_listing(a, self.fmt_list)
    def do_NLST(self, a): self.send_listing(a, lambda d: "\r\n".join(sorted(os.listdir(d))) + "\r\n")
    def do_MLSD(self, a):
        if NO_MLSD: self.send("500 MLSD not understood"); return
        self.send_listing(a, self.fmt_mlsd)

    def do_RETR(self, a):
        p = self.real(a)
        if not os.path.isfile(p): self.send("550 no such file"); return
        self.send("150 opening data connection")
        c = self.data()
        with open(p, "rb") as f:
            f.seek(self.rest); self.rest = 0
            while True:
                b = f.read(65536)
                if not b: break
                try: c.sendall(b)
                except Exception: break
        c.close(); self.send("226 transfer complete")
    def do_STOR(self, a):
        p = self.real(a)
        if not os.path.isdir(os.path.dirname(p)): self.send("550 no such directory"); return
        self.send("150 ok to send")
        c = self.data()
        with open(p, "wb") as f:
            while True:
                b = c.recv(65536)
                if not b: break
                f.write(b)
        c.close(); self.send("226 stored")
    def do_DELE(self, a):
        p = self.real(a)
        if os.path.isfile(p): os.remove(p); self.send("250 deleted")
        else: self.send("550 no such file")
    def do_MKD(self, a):
        p = self.real(a)
        if os.path.exists(p): self.send("550 exists"); return
        os.mkdir(p); self.send('257 "%s" created' % a)
    def do_RMD(self, a):
        p = self.real(a)
        try: os.rmdir(p); self.send("250 removed")
        except OSError as e: self.send("550 " + str(e))
    def do_RNFR(self, a):
        if not os.path.exists(self.real(a)): self.send("550 no such file"); return
        self.rnfr = self.real(a); self.send("350 ready for RNTO")
    def do_RNTO(self, a):
        if not self.rnfr: self.send("503 RNFR first"); return
        os.rename(self.rnfr, self.real(a)); self.rnfr = None; self.send("250 renamed")

class S(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True

srv = S(("127.0.0.1", 0), H)
print("PORT %d" % srv.server_address[1], flush=True)
srv.serve_forever()
"""#

    let process = Process()
    let port: Int
    let root: URL
    private let scriptURL: URL

    init(root: URL, noMLSD: Bool = false) throws {
        self.root = root
        scriptURL = root.deletingLastPathComponent().appendingPathComponent("mock_ftpd-\(UUID().uuidString).py")
        try Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path, root.path] + (noMLSD ? ["--no-mlsd"] : [])
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        // první řádek: "PORT n"
        var line = Data()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { Thread.sleep(forTimeInterval: 0.05); continue }
            line.append(chunk)
            if line.contains(10) { break }
        }
        guard let text = String(data: line, encoding: .utf8), text.hasPrefix("PORT "), let p = Int(text.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            process.terminate(); throw NSError(domain: "MockFTP", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server se nespustil"])
        }
        port = p
    }

    func connection(user: String = "tester", password: String = "secret") -> RemoteConnection {
        RemoteConnection(host: "127.0.0.1", port: port, user: user, password: password)
    }

    func stop() { process.terminate(); process.waitUntilExit(); try? FileManager.default.removeItem(at: scriptURL) }
}
