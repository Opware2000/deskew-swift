#!/bin/bash
#
# Génère les "golden files" (fichiers de référence) pour les tests de parité
# entre l'implémentation Pascal de Deskew et sa réimplémentation Swift.
#
# Les références sont produites en exécutant le binaire Pascal (v1.33 du dépôt)
# sur les images de TestImages/ et en capturant :
#   - la sortie console (stdout.txt), chemins absolus normalisés en <ROOT>
#   - l'image de sortie (out.png / out.jpg / out.tif) quand il y en a une
#   - l'image de travail binarisée (work-image.png) quand -s w est utilisé
#   - le code de sortie (exit_code.txt)
#   - la ligne de commande (cmd.txt)
#
# Les timings (-s t) ne sont volontairement jamais utilisés : non déterministes.
#
# Usage:
#   Tests/DeskewParityTests/generate_reference.sh [chemin/vers/deskew]
#
# Par défaut le binaire est Bin/deskew (compilé avec Scripts/compile_local.sh).

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DESKEW="${1:-$ROOT/Bin/deskew}"
REF="$ROOT/Tests/DeskewParityTests/reference"

if [[ ! -x "$DESKEW" ]]; then
  echo "ERROR: binaire introuvable ou non exécutable : $DESKEW" >&2
  echo "       compile-le d'abord (voir Scripts/compile_local.sh) ou passe son chemin." >&2
  exit 1
fi

DESKEW="$(cd "$(dirname "$DESKEW")" && pwd)/$(basename "$DESKEW")"

# Sous macOS, Deskew charge libtiff dynamiquement (dlopen "libtiff.dylib").
# On ajoute le préfixe Homebrew à DYLD_LIBRARY_PATH pour activer le support TIFF.
if [[ "$(uname)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
  TIFF_PREFIX="$(brew --prefix libtiff 2>/dev/null || true)"
  if [[ -n "$TIFF_PREFIX" && -d "$TIFF_PREFIX/lib" ]]; then
    export DYLD_LIBRARY_PATH="$TIFF_PREFIX/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
  fi
fi

rm -rf "$REF"
mkdir -p "$REF"

# Cas de test : nom|extension_sortie|arguments
#   extension_sortie : png | jpg | tif | none (aucune sortie -> detect-only)
#   @OUT@            : remplacé par le chemin de sortie du cas
#   Les chemins d'entrée sont relatifs à la racine du dépôt.
CASES=$(cat <<'EOF'
detect-1big|none|-g d -s s TestImages/1big.png
detect-1-g4|none|-g d -s s TestImages/1-g4.tif
detect-1-lzw|none|-g d -s s TestImages/1-lzw.tif
detect-2|none|-g d -s s TestImages/2.png
detect-3|none|-g d -s s TestImages/3.png
detect-4|none|-g d -s s TestImages/4.png
detect-5|none|-g d -s s TestImages/5.png
detect-6|none|-g d -s s TestImages/6.png
detect-F1550|none|-g d -s s TestImages/F1550.jpg
detect-tiff-jpeg|none|-g d -s s TestImages/tiff-jpeg.tif
detect-4-rect|none|-g d -s s -r 214,266,933,1040 TestImages/4.png
detect-4-rect-explicit|none|-g d -s s -t 100 -r 214,266,933,1040 TestImages/4.png
detect-5-explicit|none|-g d -s s -t 128 TestImages/5.png
rot-2-default|png|-o @OUT@ TestImages/2.png
rot-2-otsu-a10|png|-t a -a 10 -o @OUT@ TestImages/2.png
rot-3|png|-a 10 -o @OUT@ TestImages/3.png
rot-4|png|-o @OUT@ TestImages/4.png
rot-5-lanczos|png|-q lanczos -a 10 -o @OUT@ TestImages/5.png
rot-1big-cubic|png|-q cubic -o @OUT@ TestImages/1big.png
rot-F1550-crop|jpg|-g c -o @OUT@ TestImages/F1550.jpg
rot-2-t128|png|-t 128 -o @OUT@ TestImages/2.png
rot-F1550-t180|jpg|-t 180 -o @OUT@ TestImages/F1550.jpg
rot-5-nearest-bg|png|-q nearest -b 00FFFF -o @OUT@ TestImages/5.png
rot-4-rect|png|-r 214,266,933,1040 -o @OUT@ TestImages/4.png
rot-4-rect-stats|png|-t 100 -a 11 -b aa55cc -r 314,366,833,940 -s sp -o @OUT@ TestImages/4.png
rot-2-b1|png|-f b1 -o @OUT@ TestImages/2.png
rot-6-rgba|png|-f rgba32 -b 40ff00ff -o @OUT@ TestImages/6.png
rot-6-g8|png|-f g8 -b 77 -s sp -o @OUT@ TestImages/6.png
rot-5-skip|png|-a 10 -l 20 -o @OUT@ TestImages/5.png
work-2|png|-s w -o @OUT@ TestImages/2.png
work-4-rect|png|-s w -t 100 -r 214,266,933,1040 -o @OUT@ TestImages/4.png
rot-1-lzw-tiff|tif|-t a -a 5 -o @OUT@ TestImages/1-lzw.tif
rot-tiff-jpeg|tif|-b DD -c j95,tjpeg -o @OUT@ TestImages/tiff-jpeg.tif
rot-1-g4-input|tif|-t 128 -c tinput -o @OUT@ TestImages/1-g4.tif
rot-1-deflate|tif|-b FF0000 -c tdeflate -o @OUT@ TestImages/1-lzw.tif
rot-1-b1-tiff|tif|-f b1 -o @OUT@ TestImages/1-lzw.tif
rot-1-skip-tiff|tif|-a 5 -l 2 -o @OUT@ TestImages/1-lzw.tif
EOF
)

: > "$REF/index.tsv"
printf '%-24s %-6s %s\n' "CAS" "EXIT" "ANGLE" > "$REF/summary.txt"

cd "$ROOT"

FAILED=0
while IFS='|' read -r name ext args; do
  [[ -z "$name" ]] && continue
  dir="$REF/$name"
  mkdir -p "$dir"

  if [[ "$ext" == "none" ]]; then
    outpath=""
  else
    outpath="Tests/DeskewParityTests/reference/$name/out.$ext"
    args="${args//@OUT@/$outpath}"
  fi

  printf '%s\n' "$args" > "$dir/cmd.txt"

  set +e
  "$DESKEW" $args > "$dir/stdout.raw" 2>&1
  code=$?
  set -e

  # Normalise les chemins absolus pour rendre les golden files portables.
  sed "s|$ROOT|<ROOT>|g" "$dir/stdout.raw" > "$dir/stdout.txt"
  rm -f "$dir/stdout.raw"
  printf '%s\n' "$code" > "$dir/exit_code.txt"

  angle="$(grep -o 'Skew angle found \[deg\]: .*' "$dir/stdout.txt" | sed 's/.*: //' || true)"
  printf '%-24s %-6s %s\n' "$name" "$code" "$angle" >> "$REF/summary.txt"
  printf '%s\t%s\t%s\n' "$name" "$ext" "$args" >> "$REF/index.tsv"

  if [[ "$code" != "0" ]]; then
    echo "!! cas en échec : $name (exit $code)" >&2
    sed -n '1,6p' "$dir/stdout.txt" | sed 's/^/   /' >&2
    FAILED=$((FAILED + 1))
  fi
done <<< "$CASES"

echo
echo "Golden files générés dans : $REF"

# Déduplique les sorties identiques (liens symboliques) pour limiter la taille.
echo "Déduplication des sorties identiques..."
find "$REF" -type f \( -name 'out.*' -o -name 'work-image.png' \) -print0 \
  | xargs -0 shasum -a 256 | sort > "$REF/.hashes"
prev=""
prevf=""
while read -r hash file; do
  if [[ "$hash" == "$prev" ]]; then
    rel="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], os.path.dirname(sys.argv[2])))' "$prevf" "$file")"
    rm -f "$file"
    ln -s "$rel" "$file"
  else
    prev="$hash"
    prevf="$file"
  fi
done < "$REF/.hashes"
rm -f "$REF/.hashes"

# Le filtre `nearest` de l'original lit hors du buffer (comportement indéfini) :
# sa sortie n'est PAS reproductible (vérifié : hashes différents à chaque run).
# On ne conserve donc pas l'image ; le stdout.txt (angle, stats) reste, lui,
# déterministe.
for case in rot-5-nearest-bg; do
  rm -f "$REF/$case"/out.*
done

echo "Résumé : $REF/summary.txt"
if [[ "$FAILED" != "0" ]]; then
  echo "ATTENTION : $FAILED cas en échec." >&2
  exit 1
fi
