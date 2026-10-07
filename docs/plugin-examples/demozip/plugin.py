import sys, os
if sys.argv[1] == "unpack":
    for line in open(sys.argv[2], encoding="utf-8").read().splitlines():
        name, _, content = line.partition("\t")
        path = os.path.join(sys.argv[3], name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, "w", encoding="utf-8").write(content)
