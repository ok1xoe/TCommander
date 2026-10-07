import sys, os, json, shutil
root = sys.argv[2]
cmd = sys.argv[3]
def real(p): return os.path.join(root, p.lstrip("/"))
if cmd == "list":
    d = real(sys.argv[4])
    if not os.path.isdir(d): sys.stderr.write("no such directory"); sys.exit(2)
    out = []
    for n in sorted(os.listdir(d)):
        s = os.stat(os.path.join(d, n))
        out.append({"name": n, "dir": os.path.isdir(os.path.join(d, n)), "size": s.st_size, "mtime": s.st_mtime, "mode": s.st_mode & 0o777})
    print(json.dumps(out))
elif cmd == "get": shutil.copyfile(real(sys.argv[4]), sys.argv[5])
elif cmd == "put": shutil.copyfile(sys.argv[4], real(sys.argv[5]))
elif cmd == "rm":
    p = real(sys.argv[4])
    if os.path.isdir(p): os.rmdir(p)
    else: os.remove(p)
elif cmd == "mkdir": os.makedirs(real(sys.argv[4]), exist_ok=True)
elif cmd == "mv": os.rename(real(sys.argv[4]), real(sys.argv[5]))
