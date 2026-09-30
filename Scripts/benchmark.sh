#!/bin/bash
#
# Compare les temps d'exécution du binaire Swift (release) et de l'oracle Pascal.
#
# Usage :
#   Scripts/benchmark.sh [nb_répétitions]

set -eu

ROOTDIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOTDIR"

REPEATS="${1:-3}"
SWIFT_BIN="$(xcrun swift build -c release --show-bin-path)/deskew"
PASCAL_BIN="$ROOTDIR/Bin/deskew"

if [[ ! -x "$PASCAL_BIN" ]]; then
  echo "Oracle Pascal absent : compiler avec Scripts/compile_local.sh" >&2
  exit 1
fi

# nom|arguments
CASES=$(cat <<'EOF'
détection 1big|-g d TestImages/1big.png
cubic 1big|-q cubic -o /tmp/bench-big.png TestImages/1big.png
lanczos 5|-q lanczos -o /tmp/bench-5.png TestImages/5.png
linear 3|-o /tmp/bench-3.png TestImages/3.png
détection F1550|-g d TestImages/F1550.jpg
EOF
)

now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }

run_best() {
  local bin="$1" args="$2" best="" t0 t1 dt
  for ((i = 0; i < REPEATS; i++)); do
    t0=$(now)
    # shellcheck disable=SC2086
    "$bin" $args >/dev/null 2>&1 || true
    t1=$(now)
    dt=$(perl -e "printf '%.3f', $t1 - $t0")
    if [[ -z "$best" ]] || perl -e "exit !($dt < $best)"; then best="$dt"; fi
  done
  echo "$best"
}

printf '%-18s %10s %10s %8s\n' "cas" "Pascal(s)" "Swift(s)" "gain"
printf '%s\n' "--------------------------------------------------------"

while IFS='|' read -r name args; do
  [[ -z "$name" ]] && continue
  p=$(run_best "$PASCAL_BIN" "$args")
  s=$(run_best "$SWIFT_BIN" "$args")
  gain=$(perl -e "printf '%.2fx', ($s > 0) ? $p / $s : 0")
  printf '%-18s %10s %10s %8s\n' "$name" "$p" "$s" "$gain"
done <<< "$CASES"
