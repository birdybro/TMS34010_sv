#!/usr/bin/env bash
# Run the instruction-timing bench (sim/accuracy/tb_accuracy.sv) and write the
# report. Usage: scripts/accuracy.sh [ACK_DELAY] [CYCLE_ACCURATE]
#   upstream timing:  scripts/accuracy.sh 16 0  (memory takes 2 states)
#   accurate core:    scripts/accuracy.sh 1 1   (the core times the bus)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/work"
ACK_DELAY="${1:-16}"
ACCURATE="${2:-0}"
mkdir -p "$WORK"
python3 "$ROOT/tools/accuracy/cases.py" "$WORK/accuracy_cases.txt"
SRCS=("$ROOT/rtl/tms34010_pkg.sv")
while IFS= read -r f; do
  [ "$f" = "$ROOT/rtl/tms34010_pkg.sv" ] && continue
  SRCS+=("$f")
done < <(find "$ROOT/rtl" -type f -name '*.sv' | sort)
VLT="$WORK/verilator_tb_accuracy"
rm -rf "$VLT"; mkdir -p "$VLT"
verilator --binary --timing -Wno-fatal -Wno-TIMESCALEMOD \
  -GACK_DELAY="$ACK_DELAY" -GCYCLE_ACCURATE="$ACCURATE" --top-module tb_accuracy --Mdir "$VLT" \
  "${SRCS[@]}" "$ROOT/sim/accuracy/tb_accuracy.sv"
"$VLT/Vtb_accuracy" "+CASES=$WORK/accuracy_cases.txt" | tee "$WORK/accuracy_${ACCURATE}.log"
python3 "$ROOT/tools/accuracy/report.py" "$WORK/accuracy_${ACCURATE}.log" > "$WORK/accuracy_report_${ACCURATE}.md"
echo "report: $WORK/accuracy_report.md"
