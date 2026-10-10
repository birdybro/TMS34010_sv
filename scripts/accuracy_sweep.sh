#!/usr/bin/env bash
# Compare the accurate core with a reference revision on the timing bench,
# cycle by cycle on the external bus, across memory latencies and host traffic.
# Usage: scripts/accuracy_sweep.sh REF_REV [ACK_DELAYS] [HOSTPERS] [HOLDS]
#   REF_REV     revision whose rtl/ is the reference (the bench is this tree's)
#   ACK_DELAYS  default "1 2 3 4 5 6 7 8 9 10 11 12 13 14"
#   HOSTPERS    host read every n clocks; default "211 207 37"
#   HOLDS       bus hold every n clocks for m clocks, "n:m"; default "97:20 211:8 389:3"
# Host traffic, bus hold, DRAM refresh (every case with CONTROL.RR=00) and
# screen refresh (every case with video timing and DPYCTL.SRE on) run at
# ACK_DELAY 1 and 9 (each only if in ACK_DELAYS).
# Exit 0 only if every run is identical (RUN lines and bus cycles).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="$1"
ACKS="${2:-1 2 3 4 5 6 7 8 9 10 11 12 13 14}"
HOSTPERS="${3-211 207 37}"
HOLDS="${4-97:20 211:8 389:3}"
WORK="$ROOT/work/sweep"
rm -rf "$WORK"; mkdir -p "$WORK/ref"
git -C "$ROOT" archive "$REF" rtl | tar -x -C "$WORK/ref"
python3 "$ROOT/tools/accuracy/cases.py" "$WORK/cases.txt" >/dev/null
python3 "$ROOT/tools/accuracy/cases.py" "$WORK/cases_refresh.txt" refresh >/dev/null
python3 "$ROOT/tools/accuracy/cases.py" "$WORK/cases_screen.txt" screen >/dev/null

build() {  # build <rtl root> <ack> <outdir>
  local srcs=("$1/rtl/tms34010_pkg.sv") f
  while IFS= read -r f; do
    [ "$f" = "$1/rtl/tms34010_pkg.sv" ] || srcs+=("$f")
  done < <(find "$1/rtl" -type f -name '*.sv' | sort)
  verilator --binary --timing -j 2 -Wno-fatal -Wno-TIMESCALEMOD \
    -GACK_DELAY="$2" -GCYCLE_ACCURATE=1 --top-module tb_accuracy --Mdir "$3" \
    "${srcs[@]}" "$ROOT/sim/accuracy/tb_accuracy.sv" > "$3.build.log" 2>&1
}

fail=0
compare() {  # compare <label> <ack> <plusargs...>  (CASES=<file> to change the cases)
  local label=$1 ack=$2 cases=${CASES:-$WORK/cases.txt}; shift 2
  local p1 p2
  "$WORK/new_$ack/Vtb_accuracy" "+CASES=$cases" +BUSLOG "$@" > "$WORK/new_$label.log" 2>&1 & p1=$!
  "$WORK/ref_$ack/Vtb_accuracy" "+CASES=$cases" +BUSLOG "$@" > "$WORK/ref_$label.log" 2>&1 & p2=$!
  wait $p1 || { echo "== $label: new run FAILED"; fail=1; }
  wait $p2 || { echo "== $label: ref run FAILED"; fail=1; }
  echo "== $label"
  python3 "$ROOT/tools/accuracy/buscmp.py" "$WORK/new_$label.log" "$WORK/ref_$label.log" || fail=1
}

for A in $ACKS; do
  build "$ROOT" "$A" "$WORK/new_$A" & b1=$!
  build "$WORK/ref" "$A" "$WORK/ref_$A" & b2=$!
  if ! wait $b1 || ! wait $b2; then echo "== ack$A: BUILD FAILED"; fail=1; continue; fi
  compare "ack$A" "$A"
  if [ "$A" = 1 ] || [ "$A" = 9 ]; then
    for H in $HOSTPERS; do compare "ack${A}_host$H" "$A" "+HOSTPER=$H"; done
    for H in $HOLDS; do
      compare "ack${A}_hold${H%%:*}x${H##*:}" "$A" "+HOLDPER=${H%%:*}" "+HOLDLEN=${H##*:}"
    done
    CASES="$WORK/cases_refresh.txt" compare "ack${A}_refresh" "$A"
    CASES="$WORK/cases_refresh.txt" compare "ack${A}_refresh_host211_hold97x20" "$A" \
      +HOSTPER=211 +HOLDPER=97 +HOLDLEN=20
    CASES="$WORK/cases_screen.txt" compare "ack${A}_screen" "$A"
    CASES="$WORK/cases_screen.txt" compare "ack${A}_screen_host211_hold97x20" "$A" \
      +HOSTPER=211 +HOLDPER=97 +HOLDLEN=20
  fi
  [ "$A" = 1 ] || rm -rf "$WORK/new_$A" "$WORK/ref_$A"
done
echo "sweep: $([ $fail = 0 ] && echo IDENTICAL || echo DIFFERENCES) (logs in $WORK)"
exit $fail
