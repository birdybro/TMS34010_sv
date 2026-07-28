#!/usr/bin/env bash
# Run one self-checking testbench through Questa/ModelSim or Verilator.
#
# Usage:   scripts/sim.sh <tb_name>
# Example: scripts/sim.sh tb_smoke
#
# Resolves the simulator via env or PATH:
#   $VLOG, $VSIM, $VLIB  — explicit binaries (highest precedence)
#   $VERILATOR            — explicit Verilator binary
#   PATH                  — a complete Questa/ModelSim set wins; otherwise
#                           Verilator is used
#
# On Windows, install paths commonly seen on this project's dev box:
#   /c/altera_pro/25.1.1/questa_fse/win64/   (Questa FSE 25.1.1)
#   /c/intelFPGA_lite/17.0/modelsim_ase/win32aloem/  (ModelSim ASE 17.0)
#
# Exits non-zero if no simulator is found or the testbench fails.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <tb_name>" >&2
  exit 64
fi
TB="$1"
case "$TB" in
  *[!A-Za-z0-9_]*)
    echo "sim.sh: testbench name may contain only letters, digits, and underscores." >&2
    exit 64
    ;;
esac

# Locate tools.
VLOG_BIN="${VLOG:-$(command -v vlog || true)}"
VSIM_BIN="${VSIM:-$(command -v vsim || true)}"
VLIB_BIN="${VLIB:-$(command -v vlib || true)}"
VERILATOR_BIN="${VERILATOR:-$(command -v verilator || true)}"

QUESTA_AVAILABLE=1
if [ -z "$VLOG_BIN" ] || [ -z "$VSIM_BIN" ] || [ -z "$VLIB_BIN" ]; then
  QUESTA_AVAILABLE=0
fi

if [ "$QUESTA_AVAILABLE" -eq 0 ] && [ -z "$VERILATOR_BIN" ]; then
  cat >&2 <<EOF
sim.sh: simulator not found.
  Install Verilator, set \$VERILATOR, or set \$VLOG/\$VSIM/\$VLIB to a
  complete Questa/ModelSim toolchain. Tried:
    VLOG=${VLOG:-<unset>}    -> ${VLOG_BIN:-<not found>}
    VSIM=${VSIM:-<unset>}    -> ${VSIM_BIN:-<not found>}
    VLIB=${VLIB:-<unset>}    -> ${VLIB_BIN:-<not found>}
    VERILATOR=${VERILATOR:-<unset>} -> ${VERILATOR_BIN:-<not found>}
EOF
  exit 69
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work"
mkdir -p "$WORK"

# Collect sources. Order matters: package first, then RTL modules, then
# behavioral sim models, then TB.
SRCS=("$ROOT/rtl/tms34010_pkg.sv")
while IFS= read -r f; do
  [ "$f" = "$ROOT/rtl/tms34010_pkg.sv" ] && continue
  SRCS+=("$f")
done < <(find "$ROOT/rtl" -type f -name '*.sv' | sort)

if [ -d "$ROOT/sim/models" ]; then
  while IFS= read -r f; do
    SRCS+=("$f")
  done < <(find "$ROOT/sim/models" -type f -name '*.sv' | sort)
fi

TB_FILE="$ROOT/sim/tb/${TB}.sv"
if [ ! -f "$TB_FILE" ]; then
  echo "sim.sh: missing testbench: $TB_FILE" >&2
  exit 66
fi
SRCS+=("$TB_FILE")

LOG="$WORK/sim_${TB}.log"

if [ "$QUESTA_AVAILABLE" -eq 1 ]; then
  cd "$WORK"

  # Reset the Questa/ModelSim work library for determinism.
  rm -rf work
  "$VLIB_BIN" work >/dev/null
  "$VLOG_BIN" -sv -quiet "${SRCS[@]}"
  # vsim's batch exit code is not a reliable test-status signal, so the
  # TEST_RESULT marker below remains authoritative.
  "$VSIM_BIN" -c -do "run -all; quit -f" "work.$TB" 2>&1 | tee "$LOG"
else
  VLT_WORK="$WORK/verilator_${TB}"
  rm -rf "$VLT_WORK"
  mkdir -p "$VLT_WORK"
  "$VERILATOR_BIN" \
    --binary \
    --timing \
    --quiet-build \
    -Wno-fatal \
    -Wno-TIMESCALEMOD \
    --top-module "$TB" \
    --Mdir "$VLT_WORK" \
    "${SRCS[@]}"
  "$VLT_WORK/V${TB}" 2>&1 | tee "$LOG"
fi

if grep -q "TEST_RESULT: PASS" "$LOG"; then
  echo "sim.sh: $TB PASS"
  exit 0
fi
echo "sim.sh: $TB did not print 'TEST_RESULT: PASS'. See $LOG." >&2
exit 1
