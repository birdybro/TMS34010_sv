#!/usr/bin/env bash
# Lint pass — currently uses Questa/ModelSim vlog as a compile-only check.
# When Verilator support is added, this script switches to verilator --lint-only.

set -euo pipefail

VLOG_BIN="${VLOG:-$(command -v vlog || true)}"
VLIB_BIN="${VLIB:-$(command -v vlib || true)}"

if [ -z "$VLOG_BIN" ] || [ -z "$VLIB_BIN" ]; then
  echo "lint.sh: vlog/vlib not found (set \$VLOG, \$VLIB or add to PATH)." >&2
  exit 69
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work_lint"
mkdir -p "$WORK"
cd "$WORK"
rm -rf work
"$VLIB_BIN" work >/dev/null

# Compile every .sv under rtl/ in package-first order.
SRCS=(
  "$ROOT/rtl/tms34010_pkg.sv"
)
while IFS= read -r f; do
  [ "$f" = "$ROOT/rtl/tms34010_pkg.sv" ] && continue
  SRCS+=("$f")
done < <(find "$ROOT/rtl" -type f -name '*.sv' | sort)

"$VLOG_BIN" -sv -quiet "${SRCS[@]}"
echo "lint.sh: compile clean."
