#!/bin/bash
# Spustí testy. S pouhými Command Line Tools (bez Xcode) musí být cesta k pluginu Swift Testing zadána ručně.
cd "$(dirname "$0")/.."
PLUGINS="$(dirname "$(xcrun --find swift 2>/dev/null)")/../lib/swift/host/plugins/testing"
if [ -d "$PLUGINS" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
