#!/usr/bin/env bash
# Cyclone V synthesis entry point — currently tool discovery only.
#
# The RTL is substantial, but no Quartus project, device assignment, pin
# constraints, SDC, or report flow has been committed. This placeholder does
# not elaborate, map, fit, or time the design and must not be cited as
# synthesis evidence.
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
echo "  Add a reviewed QSF/SDC and map/fit/report flow before claiming synthesis."
exit 0
