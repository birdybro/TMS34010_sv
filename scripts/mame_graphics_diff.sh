#!/usr/bin/env bash
# Build/run the exact pinned MAME graphics adapter and compare it with RTL.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PINNED_COMMIT="70725158b4e9d2e1230c0515faec754f9cee86a2"
UPSTREAM_URL="https://github.com/mamedev/mame.git"
MAME_DIR="${MAME_CACHE_DIR:-$ROOT/work/mame-70725158}"
SETUP=0

if [ "${1:-}" = "--setup" ]; then
  SETUP=1
  shift
fi
if [ "$#" -ne 0 ]; then
  echo "usage: $0 [--setup]" >&2
  exit 64
fi

if [ ! -d "$MAME_DIR/.git" ]; then
  if [ "$SETUP" -ne 1 ]; then
    cat >&2 <<EOF
mame_graphics_diff.sh: pinned MAME cache is absent:
  $MAME_DIR
Run this explicit network/setup step once:
  scripts/mame_graphics_diff.sh --setup
EOF
    exit 69
  fi
  if ! command -v git >/dev/null 2>&1; then
    echo "mame_graphics_diff.sh: git is required for --setup." >&2
    exit 69
  fi
  git clone --filter=blob:none --no-checkout "$UPSTREAM_URL" "$MAME_DIR"
  git -C "$MAME_DIR" fetch origin "$PINNED_COMMIT"
  git -C "$MAME_DIR" checkout --detach "$PINNED_COMMIT"
fi

ACTUAL_COMMIT="$(git -C "$MAME_DIR" rev-parse HEAD)"
if [ "$ACTUAL_COMMIT" != "$PINNED_COMMIT" ]; then
  cat >&2 <<EOF
mame_graphics_diff.sh: wrong MAME revision.
  expected: $PINNED_COMMIT
  actual:   $ACTUAL_COMMIT
Use a separate cache or restore this checkout to the pinned revision.
EOF
  exit 65
fi

python3 "$ROOT/tools/mame/generate_graphics_vectors.py" --check
mkdir -p "$MAME_DIR/src/mame/tms34010diff"
cp "$ROOT/tools/mame/tms34010_graphics_diff.cpp" \
  "$MAME_DIR/src/mame/tms34010diff/tms34010_graphics_diff.cpp"
if ! grep -q '^@source:tms34010diff/tms34010_graphics_diff.cpp$' \
    "$MAME_DIR/src/mame/mame.lst"; then
  printf '\n@source:tms34010diff/tms34010_graphics_diff.cpp\ntms34010diff\n' \
    >>"$MAME_DIR/src/mame/mame.lst"
fi

BUILD_JOBS="${MAME_BUILD_JOBS:-4}"
case "$BUILD_JOBS" in
  ''|*[!0-9]*|0)
    echo "mame_graphics_diff.sh: MAME_BUILD_JOBS must be positive." >&2
    exit 64
    ;;
esac

make -C "$MAME_DIR" -j"$BUILD_JOBS" \
  REGENIE=1 NOWERROR=1 SUBTARGET=tms34010diff \
  SOURCES=src/mame/tms34010diff/tms34010_graphics_diff.cpp \
  NO_USE_PORTAUDIO=1 USE_WAYLAND=0 USE_X11=0

LIVE_MAME="$ROOT/work/mame_graphics_live.txt"
LIVE_RTL="$ROOT/work/rtl_graphics_actual.txt"
TMS34010_DIFF_INPUT="$ROOT/sim/vectors/mame_graphics_vectors.txt" \
TMS34010_DIFF_OUTPUT="$LIVE_MAME" \
  "$MAME_DIR/tms34010diff" tms34010diff \
    -video none -sound none -nothrottle -skip_gameinfo -seconds_to_run 2

"$ROOT/scripts/sim.sh" tb_mame_graphics_replay
python3 "$ROOT/tools/mame/compare_graphics_results.py" \
  --mame "$LIVE_MAME" --rtl "$LIVE_RTL"
echo "mame_graphics_diff.sh: pinned live differential PASS"
