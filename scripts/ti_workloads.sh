#!/usr/bin/env bash
# Rebuild vectors, run preserved TI software on pinned MAME and RTL, and compare.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PINNED_COMMIT="70725158b4e9d2e1230c0515faec754f9cee86a2"
UPSTREAM_URL="https://github.com/mamedev/mame.git"
MAME_DIR="${MAME_CACHE_DIR:-$ROOT/work/mame-70725158}"
SETUP=0
BUILD_ROM=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --setup)
      SETUP=1
      ;;
    --build-rom)
      BUILD_ROM=1
      ;;
    *)
      echo "usage: $0 [--setup] [--build-rom]" >&2
      exit 64
      ;;
  esac
  shift
done

if [ ! -d "$MAME_DIR/.git" ]; then
  if [ "$SETUP" -ne 1 ]; then
    cat >&2 <<EOF
ti_workloads.sh: pinned MAME cache is absent:
  $MAME_DIR
Run this explicit network/setup step once:
  scripts/ti_workloads.sh --setup
EOF
    exit 69
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "ti_workloads.sh: git is required for --setup." >&2
    exit 69
  fi
  git clone --filter=blob:none --no-checkout "$UPSTREAM_URL" "$MAME_DIR"
  git -C "$MAME_DIR" fetch origin "$PINNED_COMMIT"
  git -C "$MAME_DIR" checkout --detach "$PINNED_COMMIT"
fi

ACTUAL_COMMIT="$(git -C "$MAME_DIR" rev-parse HEAD)"
if [ "$ACTUAL_COMMIT" != "$PINNED_COMMIT" ]; then
  cat >&2 <<EOF
ti_workloads.sh: wrong MAME revision.
  expected: $PINNED_COMMIT
  actual:   $ACTUAL_COMMIT
Use a separate cache or restore this checkout to the pinned revision.
EOF
  exit 65
fi

python3 "$ROOT/tools/ti/prepare_workloads.py" --check
if [ "$BUILD_ROM" -eq 1 ]; then
  python3 "$ROOT/tools/ti/build_rom_demo.py"
fi

mkdir -p "$MAME_DIR/src/mame/tms34010ti"
cp "$ROOT/tools/mame/tms34010_ti_workloads.cpp" \
  "$MAME_DIR/src/mame/tms34010ti/tms34010_ti_workloads.cpp"
if ! grep -q '^@source:tms34010ti/tms34010_ti_workloads.cpp$' \
    "$MAME_DIR/src/mame/mame.lst"; then
  printf '\n@source:tms34010ti/tms34010_ti_workloads.cpp\ntms34010ti\n' \
    >>"$MAME_DIR/src/mame/mame.lst"
fi

BUILD_JOBS="${MAME_BUILD_JOBS:-4}"
case "$BUILD_JOBS" in
  ''|*[!0-9]*|0)
    echo "ti_workloads.sh: MAME_BUILD_JOBS must be positive." >&2
    exit 64
    ;;
esac

make -C "$MAME_DIR" -j"$BUILD_JOBS" \
  REGENIE=1 NOWERROR=1 SUBTARGET=tms34010ti \
  SOURCES=src/mame/tms34010ti/tms34010_ti_workloads.cpp \
  NO_USE_PORTAUDIO=1 USE_WAYLAND=0 USE_X11=0

LIVE_MAME="$ROOT/work/mame_ti_workload_actual.txt"
LIVE_RTL="$ROOT/work/rtl_ti_workload_actual.txt"
TMS34010_TI_INPUT="$ROOT/work/ti_workloads/ti_workload_vectors.txt" \
TMS34010_TI_OUTPUT="$LIVE_MAME" \
  "$MAME_DIR/tms34010ti" tms34010ti \
    -video none -sound none -nothrottle -skip_gameinfo -seconds_to_run 30

"$ROOT/scripts/sim.sh" tb_ti_workload_replay
python3 "$ROOT/tools/ti/compare_workloads.py" \
  --mame "$LIVE_MAME" --rtl "$LIVE_RTL"
echo "ti_workloads.sh: pinned live TI workload comparison PASS"
