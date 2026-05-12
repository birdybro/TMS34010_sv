#!/usr/bin/env bash
# Cyclone V synthesis check via Quartus quartus_map / quartus_fit.
#
# This is a placeholder until rtl/ has enough content to make a meaningful
# synthesis run. It currently elaborates the top entity to confirm Quartus
# accepts the source set. Real fit + timing reports become useful starting
# in Phase 1.
#
# Resolves quartus_sh via env or PATH:
#   $QUARTUS_SH   — explicit binary
#   PATH          — quartus_sh / quartus_map reachable

set -euo pipefail

QSH="${QUARTUS_SH:-$(command -v quartus_sh || true)}"
if [ -z "$QSH" ]; then
  cat >&2 <<EOF
synth_quartus.sh: quartus_sh not found.
  set \$QUARTUS_SH to the absolute path, or add Quartus bin/ to PATH.
EOF
  exit 69
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "synth_quartus.sh: Quartus integration not yet wired up — placeholder only."
echo "  Project root: $ROOT"
echo "  Run again once rtl/ contains a top entity worth synthesizing."
exit 0
