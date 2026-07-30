#!/usr/bin/env bash
# Optional readiness check for legally supplied arcade ROMs (never downloaded).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PINNED_COMMIT="70725158b4e9d2e1230c0515faec754f9cee86a2"
MAME_DIR="${MAME_CACHE_DIR:-$ROOT/work/mame-70725158}"

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <MAME-driver> <user-ROM-directory>" >&2
  exit 64
fi
DRIVER="$1"
ROM_DIR="$2"
MAME_BIN="${MAME_ARCADE_BIN:-$MAME_DIR/mame}"

if [ ! -d "$MAME_DIR/.git" ] ||
   [ "$(git -C "$MAME_DIR" rev-parse HEAD 2>/dev/null || true)" != "$PINNED_COMMIT" ]; then
  echo "mame_arcade_smoke.sh: the pinned MAME checkout is unavailable." >&2
  echo "Run scripts/ti_workloads.sh --setup first." >&2
  exit 69
fi
if [ ! -x "$MAME_BIN" ]; then
  echo "mame_arcade_smoke.sh: full MAME executable is unavailable: $MAME_BIN" >&2
  echo "Set MAME_ARCADE_BIN to a build from the pinned checkout." >&2
  exit 69
fi
if [ ! -d "$ROM_DIR" ]; then
  echo "mame_arcade_smoke.sh: ROM directory is unavailable: $ROM_DIR" >&2
  exit 66
fi

"$MAME_BIN" "$DRIVER" -rompath "$ROM_DIR" -verifyroms
"$MAME_BIN" "$DRIVER" -rompath "$ROM_DIR" \
  -video none -sound none -nothrottle -skip_gameinfo -seconds_to_run 10
echo "mame_arcade_smoke.sh: $DRIVER readiness smoke PASS"
