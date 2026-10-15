#!/usr/bin/env bash
# Build and run sim/dropin/tb_host_sys.sv. Usage: tools/dropin/host_sys.sh <CYCLE_ACCURATE 0|1> [ACK_DELAY]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CA="${1:-1}"; ACK="${2:-$([ "$CA" = 1 ] && echo 1 || echo 16)}"
WORK="$ROOT/work"; mkdir -p "$WORK"
python3 "$ROOT/tools/dropin/host_prog.py" "$WORK/host_prog.txt"
SRCS=("$ROOT/rtl/tms34010_pkg.sv")
while IFS= read -r f; do [ "$f" = "$ROOT/rtl/tms34010_pkg.sv" ] || SRCS+=("$f"); done < <(find "$ROOT/rtl" -type f -name '*.sv' | sort)
VLT="$WORK/verilator_tb_host_sys_$CA"; rm -rf "$VLT"; mkdir -p "$VLT"
verilator --binary --timing -Wno-fatal -Wno-TIMESCALEMOD -GCYCLE_ACCURATE="$CA" -GACK_DELAY="$ACK" \
  --top-module tb_host_sys --Mdir "$VLT" "${SRCS[@]}" "$ROOT/sim/dropin/tb_host_sys.sv" > "$VLT/build.log" 2>&1
"$VLT/Vtb_host_sys" "+PROG=$WORK/host_prog.txt" | tee "$WORK/host_sys_$CA.log"
