#!/bin/bash
#
# Compile la réimplémentation Swift de Deskew en mode release.
#
# Produit un binaire **universel** (arm64 + x86_64) si la toolchain le permet,
# sinon un binaire natif.
#
# Usage :
#   Scripts/build_swift_release.sh
#
# Le binaire est écrit dans .build/release/deskew.

set -eu

ROOTDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOTDIR"

# Choisit une toolchain Swift >= 5.9.
SWIFT=(swift)
if command -v xcrun >/dev/null 2>&1 && xcrun swift --version >/dev/null 2>&1; then
  SWIFT=(xcrun swift)
fi

echo "Toolchain : $("${SWIFT[@]}" --version | head -1)"

ARCHS=()
if "${SWIFT[@]}" build -c release --arch arm64 --arch x86_64 --product deskew >/dev/null 2>&1; then
  ARCHS=(--arch arm64 --arch x86_64)
  echo "Cible : universelle (arm64 + x86_64)"
else
  "${SWIFT[@]}" build -c release --product deskew
  echo "Cible : native (compilation universelle indisponible)"
fi

BIN_PATH="$("${SWIFT[@]}" build -c release "${ARCHS[@]}" --show-bin-path)/deskew"
echo
echo "Binaire généré : $BIN_PATH"
file "$BIN_PATH"
