#!/usr/bin/env bash
# Validate the complete Task 0160 Quartus report/output contract.
#
# This script is intentionally useful on an archived output directory without
# rerunning Quartus. The synthesis entry point invokes it automatically.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="tms34010_cyclone_v"
OUT_DIR="${QUARTUS_OUTPUT_DIR:-$ROOT/work/quartus/output_files}"
QSF="$ROOT/fpga/$PROJECT.qsf"
EVIDENCE_DIR="$ROOT/work/quartus/evidence"

MAP="$OUT_DIR/$PROJECT.map.rpt"
FIT="$OUT_DIR/$PROJECT.fit.rpt"
ASM="$OUT_DIR/$PROJECT.asm.rpt"
STA="$OUT_DIR/$PROJECT.sta.rpt"
STA_SUMMARY="$OUT_DIR/$PROJECT.sta.summary"
PIN="$OUT_DIR/$PROJECT.pin"
SOF="$OUT_DIR/$PROJECT.sof"
IGNORED_SDC="$OUT_DIR/$PROJECT.ignored_sdc.rpt"
SYNCHRONIZERS="$OUT_DIR/$PROJECT.synchronizers.rpt"

fail() {
  echo "check_quartus_reports.sh: FAIL: $*" >&2
  exit 1
}

require_file() {
  [ -s "$1" ] || fail "missing or empty output: $1"
}

require_text() {
  local file="$1"
  local text="$2"
  grep -Fq "$text" "$file" ||
    fail "$(basename "$file") lacks required evidence: $text"
}

for file in "$MAP" "$FIT" "$ASM" "$STA" "$STA_SUMMARY" "$PIN" "$SOF" \
            "$IGNORED_SDC" "$SYNCHRONIZERS"; do
  require_file "$file"
done

# Tool, device, revision, top, and all four mandatory phases.
for report in "$MAP" "$FIT" "$ASM" "$STA"; do
  require_text "$report" "Version 17.0.2 Build 602"
  require_text "$report" "Lite Edition"
done
require_text "$MAP" "; Top-level Entity Name           ; tms34010_cyclone_v_top"
require_text "$FIT" "; Device                          ; 5CSEBA6U23I7"
require_text "$STA" "Device Name           ; 5CSEBA6U23I7"
require_text "$MAP" "Analysis & Synthesis was successful. 0 errors, 0 warnings"
require_text "$FIT" "Fitter was successful. 0 errors, 3 warnings"
require_text "$ASM" "Assembler was successful. 0 errors, 0 warnings"
require_text "$STA" "TimeQuest Timing Analyzer was successful. 0 errors, 0 warnings"

# The Lite fitter emits exactly one unavailable-LogicLock-license warning and
# one no-compensation-clock warning per direct-mode PLL. They are reviewed,
# unavoidable for this project/tool edition, and the only warnings accepted.
for report in "$MAP" "$ASM" "$STA"; do
  warning_count="$(grep -Ec '^[[:space:]]*(Critical )?Warning \([0-9]+\):' \
      "$report" || true)"
  [ "$warning_count" -eq 0 ] ||
    fail "unexpected warning in $(basename "$report")"
done
fit_warning_ids="$(
  grep -E '^[[:space:]]*Warning \([0-9]+\):' "$FIT" |
    sed -E 's/^[[:space:]]*Warning \(([0-9]+)\):.*/\1/' |
    sort |
    tr '\n' ' '
)"
[ "$fit_warning_ids" = "177007 177007 292013 " ] ||
  fail "unexpected fitter warning set: ${fit_warning_ids:-<none>}"

# QSF assignment integrity and fitted pin realization.
qsf_pin_count="$(awk '$1 == "set_location_assignment" {count++} END {print count+0}' "$QSF")"
[ "$qsf_pin_count" -eq 63 ] ||
  fail "QSF location count is $qsf_pin_count, expected 63"
qsf_unique_locations="$(
  awk '$1 == "set_location_assignment" {print $2}' "$QSF" | sort -u | wc -l
)"
qsf_unique_ports="$(
  awk '$1 == "set_location_assignment" {print $4}' "$QSF" | sort -u | wc -l
)"
[ "$qsf_unique_locations" -eq 63 ] ||
  fail "QSF contains a duplicate physical pin"
[ "$qsf_unique_ports" -eq 63 ] ||
  fail "QSF contains a duplicate or missing top-level port assignment"
fitted_pin_count="$(grep -Ec ': Y[[:space:]]*$' "$PIN" || true)"
[ "$fitted_pin_count" -eq 63 ] ||
  fail "fitted pin file has $fitted_pin_count user assignments, expected 63"
require_text "$PIN" 'CHIP  "tms34010_cyclone_v"  ASSIGNED TO AN: 5CSEBA6U23I7'
non_lvttl_pin_count="$(
  grep -E ': Y[[:space:]]*$' "$PIN" |
    grep -Fvc '3.3-V LVTTL' || true
)"
[ "$non_lvttl_pin_count" -eq 0 ] ||
  fail "$non_lvttl_pin_count assigned pins are not fitted as 3.3-V LVTTL"

# Exact clock realization and complete constraint application.
require_text "$STA" '; FPGA_CLK1_50                                                ; Base      ; 20.000  ; 50.0 MHz'
require_text "$STA" '; FPGA_CLK2_50                                                ; Base      ; 20.000  ; 50.0 MHz'
require_text "$STA" '; u_clock_pll|u_pll|general[0].gpll~PLL_OUTPUT_COUNTER|divclk ; Generated ; 20.000  ; 50.0 MHz'
require_text "$STA" '; u_clock_pll|u_pll|general[1].gpll~PLL_OUTPUT_COUNTER|divclk ; Generated ; 5.000   ; 200.0 MHz'
require_text "$STA" '; u_video_pll|u_pll|general[0].gpll~PLL_OUTPUT_COUNTER|divclk ; Generated ; 20.000  ; 50.0 MHz'
require_text "$STA" '; u_video_pll|u_pll|general[1].gpll~PLL_OUTPUT_COUNTER|divclk ; Generated ; 20.000  ; 50.0 MHz   ; 10.000 ; 20.000'
require_text "$STA" "Design is fully constrained for setup requirements"
require_text "$STA" "Design is fully constrained for hold requirements"
for property in \
  "Illegal Clocks" \
  "Unconstrained Clocks" \
  "Unconstrained Input Ports" \
  "Unconstrained Input Port Paths" \
  "Unconstrained Output Ports" \
  "Unconstrained Output Port Paths"; do
  grep -E "; $property[[:space:]]*; 0[[:space:]]*; 0[[:space:]]*;" "$STA" >/dev/null ||
    fail "$property is nonzero or absent"
done
require_text "$IGNORED_SDC" "No constraints were ignored."

# Every reported slack must be nonnegative and every endpoint TNS must be zero.
if awk '
  /^Slack :/ && ($3 + 0.0) < 0.0 {bad=1}
  /^TNS   :/ && ($3 + 0.0) != 0.0 {bad=1}
  END {exit bad ? 0 : 1}
' "$STA_SUMMARY"; then
  fail "negative slack or nonzero TNS in multicorner timing summary"
fi
require_text "$STA" "No Recovery paths to report"
require_text "$STA" "No Removal paths to report"
for panel in \
  "Task 0160 Global Setup Paths" \
  "Task 0160 Core Setup Paths" \
  "Task 0160 Bus Setup Paths" \
  "Task 0160 Video Setup Paths" \
  "Task 0160 Local Output Paths" \
  "Task 0160 All Output Paths" \
  "Task 0160 Detailed Hold Paths"; do
  require_text "$STA" "$panel"
done
if grep -Eq 'Report Timing: Found [0-9]+ (setup|hold) paths \([1-9][0-9]* violated\)' "$STA"; then
  fail "a detailed TimeQuest panel contains violated paths"
fi

# Required synchronizer invariant: 27 elaborated chains, two protected stages
# each, all included in MTBF calculation. Auto-detected bundled MCP payload
# paths are reported separately and intentionally are not claimed as chains.
forced_stage_count="$(
  grep -Fc 'SYNCHRONIZER_IDENTIFICATION ; FORCED IF ASYNCHRONOUS' "$MAP"
)"
[ "$forced_stage_count" -eq 54 ] ||
  fail "found $forced_stage_count forced synchronizer stages, expected 54"
require_text "$SYNCHRONIZERS" "Number of Synchronizer Chains Found: 375"
require_text "$SYNCHRONIZERS" "Shortest Synchronizer Chain: 2 Registers"
required_chain_count="$(
  awk '
    /; Synchronizer Summary/ {inside=1}
    /^Synchronizer Chain #1:/ {inside=0}
    inside && /; Yes[[:space:]]*;/ {count++}
    END {print count+0}
  ' "$SYNCHRONIZERS"
)"
[ "$required_chain_count" -eq 27 ] ||
  fail "$required_chain_count required chains entered MTBF, expected 27"

# Fixed resource envelope. These bounds leave implementation margin while
# turning an accidental architecture/resource explosion into a hard failure.
resource_percent() {
  local label="$1"
  grep -Fm1 "$label" "$FIT" |
    sed -E 's/.*\( *([0-9]+) % *\).*/\1/'
}
alm_percent="$(resource_percent 'Logic utilization (in ALMs)')"
dsp_percent="$(resource_percent 'Total DSP Blocks')"
pll_percent="$(resource_percent 'Total PLLs')"
register_count="$(
  grep -m1 '; Total registers' "$FIT" |
    awk -F';' '{gsub(/[[:space:]]/, "", $3); print $3}'
)"
[ -n "$alm_percent" ] && [ "$alm_percent" -le 30 ] ||
  fail "ALM utilization exceeds 30% budget"
[ -n "$dsp_percent" ] && [ "$dsp_percent" -le 10 ] ||
  fail "DSP utilization exceeds 10% budget"
[ -n "$pll_percent" ] && [ "$pll_percent" -le 50 ] ||
  fail "PLL utilization exceeds 50% budget"
[ -n "$register_count" ] && [ "$register_count" -le 12000 ] ||
  fail "register utilization exceeds 12,000-register budget"
require_text "$FIT" '; Total block memory bits         ; 0 / 5,662,720 ( 0 % )'

# Preserve a compact, timestamp-free evidence record beside the full reports.
mkdir -p "$EVIDENCE_DIR"
minimum_setup="$(
  awk '
    /^Type  :/ {kind=$0}
    /^Slack :/ && kind ~ / Setup / {
      if (!seen || $3 < minimum) minimum=$3
      seen=1
    }
    END {if (seen) printf "%.3f", minimum}
  ' "$STA_SUMMARY"
)"
minimum_hold="$(
  awk '
    /^Type  :/ {kind=$0}
    /^Slack :/ && kind ~ / Hold / {
      if (!seen || $3 < minimum) minimum=$3
      seen=1
    }
    END {if (seen) printf "%.3f", minimum}
  ' "$STA_SUMMARY"
)"
minimum_pulse="$(
  awk '
    /^Type  :/ {kind=$0}
    /^Slack :/ && kind ~ /Minimum Pulse Width/ {
      if (!seen || $3 < minimum) minimum=$3
      seen=1
    }
    END {if (seen) printf "%.3f", minimum}
  ' "$STA_SUMMARY"
)"
worst_mtbf="$(
  grep 'Worst-Case MTBF of Design is' "$STA" |
    sed -E 's/.*is ([^ ]+) years.*/\1/' |
    sort -g |
    head -1
)"

{
  echo "tool=Quartus Prime Lite 17.0.2 Build 602"
  echo "device=5CSEBA6U23I7"
  echo "top=tms34010_cyclone_v_top"
  echo "assigned_pins=63"
  echo "clocks_mhz=50/200/50"
  echo "alms_percent=$alm_percent"
  echo "registers=$register_count"
  echo "block_memory_bits=0"
  echo "dsp_percent=$dsp_percent"
  echo "pll_percent=$pll_percent"
  echo "forced_synchronizer_chains=$required_chain_count"
  echo "forced_synchronizer_stages=$forced_stage_count"
  echo "all_detected_chains=375"
  echo "worst_case_mtbf_years=$worst_mtbf"
  echo "worst_setup_slack_ns=$minimum_setup"
  echo "worst_hold_slack_ns=$minimum_hold"
  echo "recovery_slack_ns=N/A-no-paths"
  echo "removal_slack_ns=N/A-no-paths"
  echo "worst_minimum_pulse_width_slack_ns=$minimum_pulse"
  echo "ignored_sdc_constraints=0"
  echo "fitter_warning_ids=177007,177007,292013"
  echo "programming_file=$PROJECT.sof"
} >"$EVIDENCE_DIR/implementation-evidence.txt"

echo "check_quartus_reports.sh: PASS — reports, timing, CDC, pins, and resources accepted."
