#!/usr/bin/env bash
# Negative XY / window clipping against the guide's rules (tools/dropin/negxy.py), through
# tms34010_system. Usage: tools/dropin/negxy_sys.sh <CYCLE_ACCURATE 0|1>
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CA="${1:-1}"
WORK="$ROOT/work"; mkdir -p "$WORK"
python3 "$ROOT/tools/dropin/negxy.py" gen "$WORK/negxy"
SRCS=("$ROOT/rtl/tms34010_pkg.sv")
while IFS= read -r f; do [ "$f" = "$ROOT/rtl/tms34010_pkg.sv" ] || SRCS+=("$f"); done < <(find "$ROOT/rtl" -type f -name '*.sv' | sort)
VLT="$WORK/verilator_tb_negxy_sys_$CA"; rm -rf "$VLT"; mkdir -p "$VLT"
verilator --binary --timing -Wno-fatal -Wno-TIMESCALEMOD -GCYCLE_ACCURATE="$CA" \
  --top-module tb_negxy_sys --Mdir "$VLT" "${SRCS[@]}" "$ROOT/sim/dropin/tb_negxy_sys.sv" > "$VLT/build.log" 2>&1
"$VLT/Vtb_negxy_sys" "+CASES=$WORK/negxy_cases.txt" > "$WORK/negxy_sys_$CA.log"
grep -E "^RAN|^TIMEOUT" "$WORK/negxy_sys_$CA.log" || true
python3 "$ROOT/tools/dropin/negxy.py" check "$WORK/negxy" "$WORK/negxy_sys_$CA.log"
