#!/usr/bin/env bash
# VCLK_CEN against a divided VCLK (sim/dropin/tb_vclk_cen_sys.sv), at all six divider phases.
# Usage: tools/dropin/vclk_cen_sys.sh [frames]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FRAMES="${1:-2}"
WORK="$ROOT/work"; mkdir -p "$WORK"
python3 "$ROOT/tools/dropin/two_gsp_prog.py" "$WORK/two_gsp_prog"
SRCS=("$ROOT/rtl/tms34010_pkg.sv")
while IFS= read -r f; do [ "$f" = "$ROOT/rtl/tms34010_pkg.sv" ] || SRCS+=("$f"); done < <(find "$ROOT/rtl" -type f -name '*.sv' | sort)
VLT="$WORK/verilator_tb_vclk_cen_sys"; rm -rf "$VLT"; mkdir -p "$VLT"
verilator --binary --timing -Wno-fatal -Wno-TIMESCALEMOD --top-module tb_vclk_cen_sys --Mdir "$VLT" \
  "${SRCS[@]}" "$ROOT/sim/dropin/tb_vclk_cen_sys.sv" > "$VLT/build.log" 2>&1
for ph in 0 1 2 3 4 5; do
  echo "== divider phase $ph"
  "$VLT/Vtb_vclk_cen_sys" "+PROG1=$WORK/two_gsp_prog_1.txt" "+DIV_FRAMES=$FRAMES" +CEN_BEFORE "+DIV_PHASE=$ph" \
    | grep -E "^ok|^FAIL|TEST_RESULT|start clock"
done
