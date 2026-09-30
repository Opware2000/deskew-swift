#!/bin/bash
#
# Exécute les tests sous ThreadSanitizer (data races) puis AddressSanitizer
# (débordements mémoire). Cible : les chemins parallèles et les E/S d'images.
#
# Usage :
#   Scripts/sanitizers.sh

set -eu

ROOTDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOTDIR"

SWIFT=(swift)
if command -v xcrun >/dev/null 2>&1 && xcrun swift --version >/dev/null 2>&1; then
  SWIFT=(xcrun swift)
fi

echo "== ThreadSanitizer (data races) =="
"${SWIFT[@]}" test --sanitize=thread --filter "ConcurrencyTests"

echo
echo "== AddressSanitizer (mémoire) =="
"${SWIFT[@]}" test --sanitize=address --filter "ConcurrencyTests|testLoadAllTestImages"

echo
echo "Sanitizers OK : aucune data-race, aucun débordement mémoire."
