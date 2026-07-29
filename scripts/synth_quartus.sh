#!/usr/bin/env bash
# Deterministic Quartus Prime Lite 17 implementation/sign-off flow.
#
# Usage:
#   QUARTUS_SH=/path/to/quartus_sh scripts/synth_quartus.sh
#
# Tool discovery order:
#   1. $QUARTUS_SH
#   2. $QUARTUS_ROOTDIR/bin/quartus_sh
#   3. quartus_sh on PATH
#
# The project is rebuilt from an empty Quartus database with fixed project
# seed/effort settings. Each phase has its own log under work/quartus/logs;
# check_quartus_reports.sh then rejects incomplete phases, report drift,
# timing/constraint/CDC/pin failures, and resource-budget violations.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/fpga"
PROJECT="tms34010_cyclone_v"
OUT_DIR="$ROOT/work/quartus/output_files"
LOG_DIR="$ROOT/work/quartus/logs"
REPORT_SCRIPT="$PROJECT_DIR/report_timing.tcl"

resolve_executable() {
  local candidate="$1"
  if [[ "$candidate" == */* ]]; then
    [ -x "$candidate" ] && printf '%s\n' "$candidate"
  else
    command -v "$candidate" 2>/dev/null || true
  fi
}

QSH_CANDIDATE="${QUARTUS_SH:-}"
if [ -z "$QSH_CANDIDATE" ] && [ -n "${QUARTUS_ROOTDIR:-}" ]; then
  QSH_CANDIDATE="$QUARTUS_ROOTDIR/bin/quartus_sh"
fi
if [ -z "$QSH_CANDIDATE" ]; then
  QSH_CANDIDATE="quartus_sh"
fi
QSH="$(resolve_executable "$QSH_CANDIDATE")"

if [ -z "$QSH" ]; then
  cat >&2 <<EOF
synth_quartus.sh: Quartus Prime Lite 17 was not found.
  Set \$QUARTUS_SH to its quartus_sh binary, set \$QUARTUS_ROOTDIR, or add
  the Quartus bin directory to PATH.
EOF
  exit 69
fi

QUARTUS_BIN="$(cd "$(dirname "$QSH")" && pwd)"
QMAP="$QUARTUS_BIN/quartus_map"
QFIT="$QUARTUS_BIN/quartus_fit"
QASM="$QUARTUS_BIN/quartus_asm"
QSTA="$QUARTUS_BIN/quartus_sta"

for tool in "$QSH" "$QMAP" "$QFIT" "$QASM" "$QSTA"; do
  if [ ! -x "$tool" ]; then
    echo "synth_quartus.sh: required tool is not executable: $tool" >&2
    exit 69
  fi
done

VERSION="$("$QSH" --version 2>&1)"
if ! grep -Fq "Version 17.0.2" <<<"$VERSION" ||
   ! grep -Fq "Lite Edition" <<<"$VERSION"; then
  echo "synth_quartus.sh: this sign-off flow requires Quartus Prime Lite 17.0.2." >&2
  echo "$VERSION" >&2
  exit 65
fi

# These are the only build-artifact roots this script owns.
rm -rf "$PROJECT_DIR/db"
rm -rf "$PROJECT_DIR/incremental_db"
rm -rf "$OUT_DIR"
rm -rf "$LOG_DIR"
mkdir -p "$OUT_DIR" "$LOG_DIR"

run_phase() {
  local phase="$1"
  shift
  echo "synth_quartus.sh: $phase"
  "$@" 2>&1 | tee "$LOG_DIR/$phase.log"
}

cd "$PROJECT_DIR"
COMMON_ARGS=(
  "$PROJECT"
  --read_settings_files=on
  --write_settings_files=off
)

run_phase map "$QMAP" "${COMMON_ARGS[@]}"
run_phase fit "$QFIT" "${COMMON_ARGS[@]}"
run_phase asm "$QASM" "${COMMON_ARGS[@]}"
run_phase sta "$QSTA" "$PROJECT" \
  --report_script="$REPORT_SCRIPT"

"$ROOT/scripts/check_quartus_reports.sh"

echo "synth_quartus.sh: PASS — map, fit, assembly, TimeQuest, and report validation complete."
