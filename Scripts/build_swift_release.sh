#!/bin/bash
#
# Compile la réimplémentation Swift de Deskew en mode release.
#
# Usage :
#   Scripts/build_swift_release.sh
#
# Le binaire est écrit dans .build/release/deskew.
#
# Note : le package requiert Swift >= 5.9. Si la commande `swift` du PATH est
# plus ancienne (p. ex. via swiftly), ce script utilise `xcrun swift` (Xcode).

set -eu

ROOTDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOTDIR"

# Choisit une toolchain Swift >= 5.9.
SWIFT=(swift)
if command -v xcrun >/dev/null 2>&1 && xcrun swift --version >/dev/null 2>&1; then
  SWIFT=(xcrun swift)
fi

echo "Toolchain : $("${SWIFT[@]}" --version | head -1)"

"${SWIFT[@]}" build -c release --product deskew

BIN_PATH="$("${SWIFT[@]}" build -c release --show-bin-path)/deskew"
echo
echo "Binaire généré : $BIN_PATH"
file "$BIN_PATH"
