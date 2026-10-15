#!/usr/bin/env bash
# Build and run sim/dropin/tb_two_gsp_sys.sv. Usage: tools/dropin/two_gsp_sys.sh <CYCLE_ACCURATE 0|1> [plusargs...]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CA="${1:-1}"; shift || true
WORK="$ROOT/work"; mkdir -p "$WORK"
python3 "$ROOT/tools/dropin/two_gsp_prog.py" "$WORK/two_gsp_prog"
SRCS=("$ROOT/rtl/tms34010_pkg.sv")
while IFS= read -r f; do [ "$f" = "$ROOT/rtl/tms34010_pkg.sv" ] || SRCS+=("$f"); done < <(find "$ROOT/rtl" -type f -name '*.sv' | sort)
VLT="$WORK/verilator_tb_two_gsp_sys_$CA"; rm -rf "$VLT"; mkdir -p "$VLT"
verilator --binary --timing -Wno-fatal -Wno-TIMESCALEMOD -GCYCLE_ACCURATE="$CA" \
  --top-module tb_two_gsp_sys --Mdir "$VLT" "${SRCS[@]}" "$ROOT/sim/dropin/tb_two_gsp_sys.sv" > "$VLT/build.log" 2>&1
"$VLT/Vtb_two_gsp_sys" "+PROG1=$WORK/two_gsp_prog_1.txt" "+PROG2=$WORK/two_gsp_prog_2.txt" "$@" | tee "$WORK/two_gsp_sys_$CA.log"
