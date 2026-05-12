#!/usr/bin/env bash
# Run a single testbench through Questa/ModelSim.
#
# Usage:   scripts/sim.sh <tb_name>
# Example: scripts/sim.sh tb_smoke
#
# Resolves the simulator via env or PATH:
#   $VLOG, $VSIM, $VLIB  — explicit binaries (highest precedence)
#   PATH                 — vlog/vsim must be reachable
#
# On Windows, install paths commonly seen on this project's dev box:
#   /c/altera_pro/25.1.1/questa_fse/win64/   (Questa FSE 25.1.1)
#   /c/intelFPGA_lite/17.0/modelsim_ase/win32aloem/  (ModelSim ASE 17.0)
#
# Exits non-zero if the simulator is not found or the testbench fails.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <tb_name>" >&2
  exit 64
fi
TB="$1"

# Locate tools.
VLOG_BIN="${VLOG:-$(command -v vlog || true)}"
VSIM_BIN="${VSIM:-$(command -v vsim || true)}"
VLIB_BIN="${VLIB:-$(command -v vlib || true)}"

if [ -z "$VLOG_BIN" ] || [ -z "$VSIM_BIN" ] || [ -z "$VLIB_BIN" ]; then
  cat >&2 <<EOF
sim.sh: simulator not found.
  set \$VLOG, \$VSIM, \$VLIB to point at vlog/vsim/vlib binaries,
  or add them to PATH. Tried:
    VLOG=${VLOG:-<unset>}    -> ${VLOG_BIN:-<not found>}
    VSIM=${VSIM:-<unset>}    -> ${VSIM_BIN:-<not found>}
    VLIB=${VLIB:-<unset>}    -> ${VLIB_BIN:-<not found>}
EOF
  exit 69
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work"
mkdir -p "$WORK"

cd "$WORK"

# Reset work library each run for determinism.
rm -rf work
"$VLIB_BIN" work >/dev/null

# Collect sources. Order matters: package first, then RTL modules, then TB.
SRCS=("$ROOT/rtl/tms34010_pkg.sv")
while IFS= read -r f; do
  [ "$f" = "$ROOT/rtl/tms34010_pkg.sv" ] && continue
  SRCS+=("$f")
done < <(find "$ROOT/rtl" -type f -name '*.sv' | sort)

TB_FILE="$ROOT/sim/tb/${TB}.sv"
if [ ! -f "$TB_FILE" ]; then
  echo "sim.sh: missing testbench: $TB_FILE" >&2
  exit 66
fi
SRCS+=("$TB_FILE")

"$VLOG_BIN" -sv -quiet "${SRCS[@]}"

# Run vsim. Capture transcript so we can decide PASS/FAIL by string match —
# vsim's exit code in batch mode is unreliable for test status.
LOG="$WORK/sim.log"
"$VSIM_BIN" -c -do "run -all; quit -f" "work.$TB" 2>&1 | tee "$LOG"

if grep -q "TEST_RESULT: PASS" "$LOG"; then
  echo "sim.sh: $TB PASS"
  exit 0
fi
echo "sim.sh: $TB did not print 'TEST_RESULT: PASS'. See $LOG." >&2
exit 1
