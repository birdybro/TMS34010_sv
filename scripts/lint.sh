#!/usr/bin/env bash
# Compile/lint every synthesizable SystemVerilog source.
#
# Tool preference:
#   1. Questa/ModelSim vlog + vlib
#   2. Verilator --lint-only

set -euo pipefail

VLOG_BIN="${VLOG:-$(command -v vlog || true)}"
VLIB_BIN="${VLIB:-$(command -v vlib || true)}"
VERILATOR_BIN="${VERILATOR:-$(command -v verilator || true)}"

if { [ -z "$VLOG_BIN" ] || [ -z "$VLIB_BIN" ]; } && [ -z "$VERILATOR_BIN" ]; then
  echo "lint.sh: no supported lint tool found." >&2
  echo "  Install vlog+vlib or Verilator, or set \$VLOG/\$VLIB/\$VERILATOR." >&2
  exit 69
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Collect every .sv under rtl/ in package-first order.
SRCS=(
  "$ROOT/rtl/tms34010_pkg.sv"
)
while IFS= read -r f; do
  [ "$f" = "$ROOT/rtl/tms34010_pkg.sv" ] && continue
  SRCS+=("$f")
done < <(find "$ROOT/rtl" -type f -name '*.sv' | sort)

if [ -n "$VLOG_BIN" ] && [ -n "$VLIB_BIN" ]; then
  WORK="$ROOT/work_lint"
  mkdir -p "$WORK"
  cd "$WORK"
  rm -rf work
  "$VLIB_BIN" work >/dev/null
  "$VLOG_BIN" -sv -quiet "${SRCS[@]}"
  echo "lint.sh: Questa/ModelSim compile clean."
  exit 0
fi

# Multiple top modules are intentional: the core, video timing, and refresh
# blocks are independently instantiable. Keep other Verilator diagnostics
# visible, but do not make an existing warning fatal.
"$VERILATOR_BIN" --lint-only -Wno-fatal -Wno-MULTITOP "${SRCS[@]}"
echo "lint.sh: Verilator lint completed (review warnings above)."
