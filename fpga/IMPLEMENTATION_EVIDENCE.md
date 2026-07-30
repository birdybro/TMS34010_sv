# Cyclone V implementation evidence

Task 0174 re-signs the reproducible FPGA implementation gate for
`tms34010_cyclone_v_top` after the complete production-revision GPU closure.
The checked-in project is the source of truth; full generated reports remain
ignored build artifacts.

## Reproduce

```sh
QUARTUS_SH=/path/to/quartus-17.0/quartus/bin/quartus_sh \
  scripts/synth_quartus.sh
```

The script removes only this project's generated Quartus database, output,
and log directories, then runs Analysis & Synthesis, Fitter, Assembler,
TimeQuest, and `scripts/check_quartus_reports.sh`. The validator rejects a
missing phase or artifact, tool/device/top drift, unexpected warning,
pin/clock/constraint mismatch, negative timing slack, nonzero TNS,
unrecognized required synchronizer, or resource-budget violation. It writes a
timestamp-free summary to
`work/quartus/evidence/implementation-evidence.txt`.

## Accepted implementation

| Property | Accepted result |
|---|---:|
| Tool | Quartus Prime Lite 17.0.2 Build 602 |
| Device | `5CSEBA6U23I7` |
| Top | `tms34010_cyclone_v_top` |
| Assigned/fitted user pins | 63 / 63 |
| Core / bus / VCLK | 50 / 200 / 50 MHz |
| Logic utilization | 12,645 / 41,910 ALMs (30%) |
| Registers | 10,479 |
| Block memory | 0 bits |
| DSP blocks | 6 / 112 (5%) |
| PLLs | 2 / 6 (33%) |
| Worst setup slack | +0.556 ns |
| Worst hold slack | +0.147 ns |
| Worst minimum-pulse-width slack | +1.250 ns |
| Ignored SDC constraints | 0 |
| Programming file | `tms34010_cyclone_v.sof` |

Analysis & Synthesis, Assembler, and TimeQuest each complete with zero errors
and zero warnings. The Fitter completes with zero errors and exactly three
reviewed warnings: one LogicLock Lite-license warning (`292013`) and one
direct-mode PLL compensation warning (`177007`) for each PLL. The report
validator accepts no other warning set.

All reported setup and hold paths are fully constrained and have zero TNS in
the slow 100 °C, slow -40 °C, fast 100 °C, and fast -40 °C models.
Recovery/removal reports contain no paths because asynchronous reset
assertion is intentionally cut at the first stage and every reset release is
synchronized through the attributed two-register destination-domain chain;
this is an explicit reset protocol result, not an unconstrained-path result.

## CDC evidence

Quartus finds 375 candidate synchronizer chains with a minimum length of two
registers. The source attributes identify exactly 54 required stages forming
27 required two-register chains, and all 27 are included in the
metastability calculation. The validator's worst required-chain result across
the analyzed corners is 242 years. The remaining auto-detected candidates
include stable bundled-payload and ordinary shift structures and are not
claimed as architectural synchronizers. The validator checks the required
source-attributed chain and stage counts independently of the broader
automatic report.

## Refresh-service bound

`tb_fpga_refresh_ratio` composes the real refresh generator, fabric, MCP
bridge, and physical local-bus engine at the final 50/200 MHz ratio while
VCLK runs independently at 50 MHz. Each of four minimum-interval RR=`00`
requests completes its physical RAS-only cycle before the next 32-core-clock
event; the observed worst case is 11 core clocks. The proof deliberately
holds external HOLD inactive and LRDY ready. As on the original interface,
an external agent that holds the bus indefinitely or supplies an unbounded
LRDY wait can prevent refresh and remains an environmental system constraint.

## Physical boundary

Every top-level location and 3.3-V LVTTL assignment is listed in
[`PINOUT.md`](PINOUT.md). The header mapping is a logical processor interface;
external VRAM/DRAM/host hardware, bidirectional level translation, buffering,
termination, pull-ups, power, and signal-integrity validation remain
surrounding-board responsibilities.
