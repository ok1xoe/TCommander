#!/bin/bash
# Sestaví release binárku TCommander pro arm64 i x86_64 (každou zvlášť, spojí lipem) a vypíše její cestu na posledním řádku.
# Společné sestavení obou architektur najednou (--arch … --arch …) selhává na Xcode 16.4, proto se sestavují zvlášť.
set -euo pipefail
cd "$(dirname "$0")/.."
BIN_DIR="$(mktemp -d)"
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx14.0" >&2
  # výstupní složka se podle nástrojů může u obou architektur shodovat, proto binárku hned zkopírujeme
  cp "$(swift build -c release --triple "$arch-apple-macosx14.0" --show-bin-path)/TCommander" "$BIN_DIR/TCommander-$arch"
done
lipo -create -output "$BIN_DIR/TCommander" "$BIN_DIR/TCommander-arm64" "$BIN_DIR/TCommander-x86_64"
lipo -info "$BIN_DIR/TCommander" >&2
echo "$BIN_DIR/TCommander"
