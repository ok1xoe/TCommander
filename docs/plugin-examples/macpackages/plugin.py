#!/usr/bin/env python3
"""Archivní plugin pro balíčky macOS.

Volání: plugin.py unpack <soubor.pkg|soubor.dmg> <cílová složka>
  .pkg  →  pkgutil --expand-full (rozbalí i obsah Payload)
  .dmg  →  hdiutil attach (jen pro čtení, bez zobrazení ve Finderu), zkopíruje obsah a obraz zase odpojí
"""
import sys, os, shutil, subprocess, tempfile


def fail(msg):
    sys.stderr.write(msg.strip() + "\n"); sys.exit(1)


def unpack_pkg(src, dest):
    tmp = tempfile.mkdtemp(prefix="tc-pkg-")
    try:
        target = os.path.join(tmp, "x")                              # pkgutil vyžaduje neexistující cílovou složku
        r = subprocess.run(["/usr/sbin/pkgutil", "--expand-full", src, target], capture_output=True, text=True)
        if r.returncode != 0:
            fail(r.stderr or "pkgutil selhal")
        for name in os.listdir(target):
            shutil.move(os.path.join(target, name), os.path.join(dest, name))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def unpack_dmg(src, dest):
    mnt = tempfile.mkdtemp(prefix="tc-dmg-")
    attached = False
    try:
        # „Y“ na vstupu odpoví na případnou licenční smlouvu uvnitř obrazu
        r = subprocess.run(["/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-noverify", "-mountpoint", mnt, src],
                           input=b"Y\n", capture_output=True)
        if r.returncode != 0:
            fail(r.stderr.decode("utf-8", "replace") or "hdiutil selhal")
        attached = True
        r = subprocess.run(["/usr/bin/ditto", mnt, dest], capture_output=True)
        if r.returncode != 0:
            fail(r.stderr.decode("utf-8", "replace") or "kopírování selhalo")
    finally:
        if attached:
            subprocess.run(["/usr/bin/hdiutil", "detach", "-force", mnt], capture_output=True)
        shutil.rmtree(mnt, ignore_errors=True)


if __name__ == "__main__":
    if len(sys.argv) < 4 or sys.argv[1] != "unpack":
        fail("použití: plugin.py unpack <archiv> <cílová složka>")
    src, dest = sys.argv[2], sys.argv[3]
    os.makedirs(dest, exist_ok=True)
    ext = os.path.splitext(src)[1].lower()
    if ext == ".pkg": unpack_pkg(src, dest)
    elif ext == ".dmg": unpack_dmg(src, dest)
    else: fail("nepodporovaná přípona: " + ext)
