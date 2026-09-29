#!/bin/bash
#
# Compile Deskew (v1.33 du dépôt) nativement sur la machine courante avec FPC.
# Sert à produire le binaire "oracle" pour les tests de parité.
#
# Prérequis : Free Pascal (brew install fpc).
#
# Usage :
#   Scripts/compile_local.sh
#
# Le binaire est écrit dans Bin/deskew.

set -eu

ROOTDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOTDIR"

if ! command -v fpc >/dev/null 2>&1; then
  echo "ERROR: fpc introuvable. Installe Free Pascal (brew install fpc)." >&2
  exit 1
fi

mkdir -p Dcu Bin

fpc -B -O3 -Mdelphi -vn- \
  -FiImaging \
  -FuImaging -FuImaging/ZLib -FuImaging/JpegLib -FuImaging/LibTiff \
  -FE./Bin -FU./Dcu \
  deskew.lpr

echo
echo "Binaire généré : $ROOTDIR/Bin/deskew"
