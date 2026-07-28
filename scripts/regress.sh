#!/usr/bin/env bash
# Run every tracked self-checking testbench and require every PASS marker.
#
# Usage: scripts/regress.sh
#
# REGRESS_JOBS controls parallelism (default 1). Parallel Questa/ModelSim
# builds are unsafe because that flow uses one shared work library, so the
# runner automatically selects one job when a complete Questa toolchain wins.
# Per-test logs are written under work/regression/.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$ROOT/scripts/regress.sh"

if [ "${1:-}" = "--worker" ]; then
  if [ "$#" -ne 2 ]; then
    echo "regress.sh: internal worker requires one testbench name." >&2
    exit 64
  fi

  TB="$2"
  RUN_DIR="${REGRESSION_RUN_DIR:?regress.sh: missing worker run directory}"
  LOG="$RUN_DIR/${TB}.log"

  if SIM_CLEAN_BUILD=1 "$ROOT/scripts/sim.sh" "$TB" >"$LOG" 2>&1; then
    rm -f "$ROOT/work/sim_${TB}.log"
    echo "PASS $TB"
  else
    echo "FAIL $TB (see $LOG)"
  fi
  # The parent determines aggregate status from each authoritative sim log.
  exit 0
fi

if [ "$#" -ne 0 ]; then
  echo "usage: $0" >&2
  exit 64
fi

JOBS="${REGRESS_JOBS:-1}"
case "$JOBS" in
  ''|*[!0-9]*|0)
    echo "regress.sh: REGRESS_JOBS must be a positive integer." >&2
    exit 64
    ;;
esac

VLOG_BIN="${VLOG:-$(command -v vlog || true)}"
VSIM_BIN="${VSIM:-$(command -v vsim || true)}"
VLIB_BIN="${VLIB:-$(command -v vlib || true)}"
if [ -n "$VLOG_BIN" ] && [ -n "$VSIM_BIN" ] && [ -n "$VLIB_BIN" ] &&
   [ "$JOBS" -ne 1 ]; then
  echo "regress.sh: complete Questa/ModelSim toolchain detected; using one job."
  JOBS=1
fi

if ! command -v xargs >/dev/null 2>&1; then
  echo "regress.sh: xargs is required." >&2
  exit 69
fi

mapfile -t TESTS < <(
  find "$ROOT/sim/tb" -maxdepth 1 -type f -name 'tb_*.sv' -printf '%f\n' |
    sed 's/\.sv$//' |
    sort
)
if [ "${#TESTS[@]}" -eq 0 ]; then
  echo "regress.sh: no testbenches found under $ROOT/sim/tb." >&2
  exit 66
fi

RUN_DIR="$ROOT/work/regression"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
export REGRESSION_RUN_DIR="$RUN_DIR"

echo "regress.sh: running ${#TESTS[@]} testbenches with $JOBS job(s)."
printf '%s\0' "${TESTS[@]}" |
  xargs -0 -n 1 -P "$JOBS" "$SELF" --worker

PASS_COUNT=0
FAILED_TESTS=()
for TB in "${TESTS[@]}"; do
  if grep -q "^sim.sh: ${TB} PASS$" "$RUN_DIR/${TB}.log"; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAILED_TESTS+=("$TB")
  fi
done

if [ "${#FAILED_TESTS[@]}" -ne 0 ]; then
  echo "regress.sh: $PASS_COUNT/${#TESTS[@]} PASS; failures:"
  printf '  %s\n' "${FAILED_TESTS[@]}"
  echo "regress.sh: see per-test logs under $RUN_DIR." >&2
  exit 1
fi

echo "regress.sh: $PASS_COUNT/${#TESTS[@]} PASS"
