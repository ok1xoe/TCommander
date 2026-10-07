import Foundation
@testable import TCCore

/// Lokální proxy server (Python): SOCKS5 nebo HTTP CONNECT; počítá spojení do souboru, aby test ověřil, že provoz šel přes proxy.
final class MockProxy {
    static let script = #"""
import socket, sys, threading, struct

MODE = sys.argv[1]          # "socks5" | "connect"
COUNTFILE = sys.argv[2]
lock = threading.Lock()
count = 0

def bump(target):
    global count
    with lock:
        count += 1
        open(COUNTFILE, "w").write("%d %s" % (count, target))

def relay(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d: break
            b.sendall(d)
    except Exception: pass
    for s in (a, b):
        try: s.shutdown(socket.SHUT_RDWR)
        except Exception: pass

def recvn(c, n):
    buf = b""
    while len(buf) < n:
        d = c.recv(n - len(buf))
        if not d: raise EOFError
        buf += d
    return buf

def handle(c):
    try:
        if MODE == "socks5":
            ver, n = recvn(c, 2); recvn(c, n)
            c.sendall(b"\x05\x00")
            ver, cmd, _, atyp = recvn(c, 4)
            if atyp == 1: host = socket.inet_ntoa(recvn(c, 4))
            elif atyp == 3: host = recvn(c, recvn(c, 1)[0]).decode()
            else: c.close(); return
            port = struct.unpack(">H", recvn(c, 2))[0]
            up = socket.create_connection((host, port), timeout=10)
            c.sendall(b"\x05\x00\x00\x01\x00\x00\x00\x00\x00\x00")
        else:
            buf = b""
            while b"\r\n\r\n" not in buf: buf += c.recv(4096)
            first = buf.split(b"\r\n")[0].decode()
            _, target, _ = first.split(" ")
            host, port = target.rsplit(":", 1); port = int(port)
            up = socket.create_connection((host, port), timeout=10)
            c.sendall(b"HTTP/1.0 200 Connection established\r\n\r\n")
        bump("%s:%d" % (host, port))
        threading.Thread(target=relay, args=(c, up), daemon=True).start()
        relay(up, c)
    except Exception:
        pass
    finally:
        try: c.close()
        except Exception: pass

srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", 0)); srv.listen(50)
print("PORT %d" % srv.getsockname()[1], flush=True)
while True:
    c, _ = srv.accept()
    threading.Thread(target=handle, args=(c,), daemon=True).start()
"""#

    let process = Process()
    let port: Int
    private let scriptURL: URL
    private let countFile: URL

    init(mode: String, dir: URL) throws {
        scriptURL = dir.appendingPathComponent("mock_proxy-\(UUID().uuidString).py")
        countFile = dir.appendingPathComponent("proxy-count-\(UUID().uuidString).txt")
        try Self.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptURL.path, mode, countFile.path]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        var line = Data(); let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { Thread.sleep(forTimeInterval: 0.05); continue }
            line.append(chunk); if line.contains(10) { break }
        }
        guard let text = String(data: line, encoding: .utf8), text.hasPrefix("PORT "), let p = Int(text.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            process.terminate(); throw NSError(domain: "MockProxy", code: 1)
        }
        port = p
    }

    /// Počet spojení, která proxy zprostředkovala.
    var connections: Int { (try? String(contentsOf: countFile, encoding: .utf8)).flatMap { Int($0.split(separator: " ").first ?? "") } ?? 0 }

    func stop() { process.terminate(); process.waitUntilExit(); try? FileManager.default.removeItem(at: scriptURL); try? FileManager.default.removeItem(at: countFile) }
}
