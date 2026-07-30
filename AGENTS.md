# AGENTS.md

Repository-wide instructions for coding agents working on this project.

## Project

This repository is a synthesizable FPGA reimplementation of the Texas
Instruments TMS34010 Graphics System Processor in SystemVerilog. The initial
target is Intel/Altera Cyclone V.

This is RTL, not a software emulator. Model explicit hardware structure:
datapaths, muxes, registers, FSMs, counters, and memory transactions. Do not
translate a software implementation into one large procedural HDL block.

The original processor and Cyclone V implementation baseline is complete
through Task 0160. Task 0161's production-revision GPU re-audit found
remaining programmer-visible graphics work; do not claim GPU completion until
the ordered Task 0162–0174 closure plan in `tasks.md` passes. Task 0124
audited the complete official instruction summary and system integration
scope; Task 0125 corrected and verified the complete logical family's status
semantics, and Tasks 0126–0127 implemented both missing memory-to-memory MOVE
forms with destination postincrement. Task 0128 implemented RUN/EMU sampling,
active-low EMUA acknowledgement, halt, and resume, closing the last
unimplemented official instruction-summary row. Task 0129 corrected and
verified the MOVK/ADDK/SUBK encoded-zero constant as architectural value 32.
Task 0130 corrected and verified the complete shift family's count encodings,
SLA overflow, and individual status masks. Task 0131 corrected and verified
MOVI status behavior for both immediate widths. Task 0132 primary-spec
verified REV's revision value, EXGPC's low-nibble PC alignment, and both
instructions' status preservation. Task 0133 primary-spec verified FILL XY's
linear DADDR writeback and W=0 status preservation. Task 0134 corrected
SUBXY's greater-than flags to signed XY comparisons. Task 0135 completed the
individual-page N/C/Z/V audit, resolved A0009, corrected DIVS/MODS and
odd-result multiply edge cases, and completed array W=3 plus PIXT XY-to-XY
window status behavior. Task 0136 resolved A0005 and added synthesizable
sequencing from architectural fields onto aligned 16-bit words, including
all seven specification cases, partial-word RMW locking, and word-side wait
states. Task 0137 implemented source-specific INTPEND/INTENB behavior,
dedicated LINT1/LINT2 synchronizers, every maskable pending source, and direct
external-interrupt entry coverage. Task 0138 corrected and integrated the
continuous REFCNT interval/row down-counter and exported the refresh request,
row, and mode for the future memory fabric. Task 0139 integrated same-clock
internal/noninterlaced video timing, made HCOUNT/VCOUNT live, corrected the
display-interrupt point to HSBLNK, and exported the timing intervals. Task
0140 corrected the sync/blank endpoints for the specified one-VCLK delay
after each equality compare. Task 0141 made DPYADR live and added held
screen-refresh request/acknowledge scheduling with frame reload, line cadence,
and DUDATE/ORG completion updates. Task 0142 completed the direct synchronous
HSTCTL boundary, per-side message/interrupt ownership, active-low HINT,
HCS-selected reset halt, and instruction-boundary HLT/NMI behavior. Task 0143
landed the synchronous HSTADR/HSTDATA register and indirect-memory engine,
including LBL byte ordering, INCR/INCW sequencing, prefetch buffering,
backpressure, and held local-word requests. Task 0144 integrated that engine
with the I/O/core hierarchy, shared its state with processor accesses,
generalized the core boundary to all four host registers, and exposed its
held local-word client for the memory arbiter. Task 0145 landed the
specification-priority HOLD/screen/DRAM/host/CPU arbiter, retained pulsed
DRAM-refresh events, reserved CPU partial-word RMW pairs, and implemented the
required complete-pair restart when HOLD intervenes between read and write.
Task 0146's functional-system wrapper connects the core's CPU/graphics, screen,
DRAM-refresh, and host-indirect clients through the field sequencer and
arbiter to one abstract controller boundary. Task 0147's standalone
`tms34010_local_bus` runs from an 8× timing clock and emits the original
LCLK/LAD/RAS/CAS/LAL/DEN/DDOUT/W phases for ordinary word, screen-transfer,
DRAM-refresh, and I/O cycles, including LRDY waits and eight reset
initialization cycles. Task 0148's `tms34010_local_bus_bridge` uses a
two-phase multi-cycle-path
handshake to transfer complete commands and returned read data coherently
between the core and 8× domains. `tms34010_pin_system` connects that bridge
to the functional system and local-bus engine, with IAQ and captured screen
ORG propagated end to end. Task 0149 registers and classifies each processor
memory request in the memory fabric, bypasses field splitting for on-chip
I/O addresses, selects
the dedicated I/O cycle kinds, carries on-chip read data through the bridge,
and qualifies every processor I/O write with returned physical completion.
Task 0150 gives the held host-indirect client the same I/O decode/cycle path,
samples its live internal read word at arbitration, and commits host-side
register writes only when physical completion returns.
Task 0151 samples active-low HOLD at the documented end-Q1 boundary, crosses
the request and quiescent arbiter grant as synchronized levels, emits the
Q3/Q4 active-low HOLDA component, and sequences LAD/control output enables
off and back on at their specified Q2/Q3 boundaries.
Task 0152 synchronizes physical RUN/EMU into the core, bridges each EMU
execution and the emulator-halt level into the 8× domain, and drives the
original shared pin as exact Q1/Q2 EMUA plus Q3/Q4 HLDA.
Task 0153 wraps the synchronous four-register host engine with the original
active-low HCS/HREAD/HWRITE/HLDS/HUDS controls, HFS selection, immediate HRDY
waits, coherent bundled capture, latched read data, and byte-lane HD output
enables.
Task 0154 masks the remaining CONTROL/DPYCTL/DPYTAP reserved fields and makes
all four reserved I/O register locations ignore processor/host-indirect writes
and read as zero.
Task 0155 moves HCOUNT/VCOUNT, timing compares, DPYADR, and the automatic
screen scheduler into a dedicated VCLK domain. Atomic MCP mailboxes carry
configuration, coalesced live-register commands, and coherent status
snapshots; separate held handshakes return DIP and completed bundled screen
transactions to the core domain.
Task 0156 consumes DPYCTL.NIL for internally generated interlace: even-to-odd
starts at HTOTAL/2 without resetting HCOUNT, the odd VESYNC half-line compare
advances VCOUNT, odd-to-even returns at the full-line boundary, and the
display owner applies signed DUDATE/2 before each even field.
Task 0157 consumes DPYCTL.DXV/HSD for external synchronization. Individually
synchronized active-low HSYNC/VSYNC inputs receive the specified recognition
delay; external edges or total-register fallbacks control the counters;
external interlace classifies the next field at the recognition edge; and
split sync output enables reach the pin-system boundary.
Task 0158 consumes DPYCTL.SRT only for graphics pixel traffic. PIXT, DRAV,
LINE, FILL, and PIXBLT pixel reads/writes become explicit VRAM
memory-to-register/register-to-memory local cycles with the documented
TR/QE/W/address-status phases; ordinary instruction, data, I/O, and host
traffic are unchanged. Direct replace operations avoid unnecessary
destination reads. The TMS34010 itself has no pixel-data output pins:
external VRAM serial ports supply pixels.
Task 0159 adds the isolated Cyclone V adapter layer: a 50/200 MHz core/bus
PLL, an independent phase-separated video PLL, three synchronized active-high
reset releases, top-level-only host/local/video tri-states, and active-low
sync conversion. Separate reset ports now reach the core, 8× bus, and VCLK
owners; ordinary unit benches intentionally tie them together.
Task 0160 adds the Quartus Prime Lite 17.0.2 project, complete DE10-Nano
pin/3.3-V LVTTL assignments and SDC, deterministic map/fit/assembly/TimeQuest
plus report validation, measured timing/resource/CDC evidence, and an
end-to-end final-clock-ratio refresh-service proof. The complete task gate is
147 self-checking benches, zero-diagnostic RTL lint, and the real Quartus
flow.
Task 0161 defines the current milestone: correct empty arrays and terminal
PIXBLT context, implement PBH/PBV direction and exact W=1/W=3 array
semantics, add resumable FILL/PIXBLT/LINE interrupt paths, close exhaustive
graphics and video matrices, reclose SRT/local-bus integration, validate
against pinned MAME and TI software, then rerun full simulation and Quartus
sign-off. Task 0162 corrected empty-array handling for all FILL/PIXBLT forms
and the distinct terminal-context rules: PIXBLT returns hypothetical
next-row SADDR/DADDR, while FILL returns final-row next-X DADDR. It is locked
by the stalled-memory `tb_graphics_array_edges` matrix. Task 0163 directional
PIXBLT traversal implements all PBH/PBV combinations: L,L accepts
software-adjusted corners, mixed/XY full-color forms adjust automatically,
and binary-source forms ignore both bits. `tb_pixblt_direction` locks exact
pixels/context, degenerate edges, stalls, and overlap-safe forward/reverse
copies. Task 0164 completes W=1 common-rectangle results for FILL XY and all
XY-destination PIXBLTs: hit geometry writes DADDR/DYDX without pixel traffic,
directional full-color forms encode the selected common corner, binary/FILL
use the lowest-address corner, and V/WVP retain their specified meanings.
`tb_window_common_rect` covers every geometry class, form, and direction under
stalls. Task 0165 implements true W=3 preclipping before the first request:
FILL intersects its destination geometry, while B,XY/L,XY/XY,XY offset source
and destination consistently and traverse only the effective rectangle.
`tb_window_preclip` compares exact read/write/SRT request sequences and
framebuffer correspondence across every edge/corner, all PBH/PBV directions,
PSIZE 1/2/4/8/16, independent legal pitches, PPOP/PMASK reads, full exclusion,
and injected waits. It also locks original-array completion context, V-only
status, no WVP, and binary direction isolation. Task 0166 checkpointable
FILL/PIXBLT execution is next. The optional instruction
cache, exact original-silicon instruction timing, first-silicon mode, external
VRAM serial output, TMS34020/TMS34082, and board analog validation remain
outside this functional GPU gate.
The implementation includes the multicycle CPU core, the currently tracked
instruction set, bit-field memory operations, graphics operations through
LINE/DRAV/PIXT/PIXBLT/FILL with window checking, I/O registers, reset-vector
fetch, maskable/NMI entry with architectural service-context ST
initialization, and the illegal-opcode trap. Video timing is integrated in
its dedicated VCLK domain through coherent CDC, internal/external
noninterlaced/interlaced timing, the screen-refresh client, and its physical
memory-to-register cycle. Program-controlled VRAM MTR/RTM service is also
integrated; external VRAM serial-display behavior is a surrounding-system
responsibility rather than missing processor RTL.
Host and local/video pad direction, pin assignments, I/O timing, and required
CDC chains are signed off by the checked-in FPGA project and validator. Read
`tasks.md`, `docs/completion_audit.md`, and the current-status sections in
`docs/architecture.md` before selecting new work.

## Specification source of truth

`third_party/TMS34010_Info/` is a pinned git submodule. Authoritative documents:

- `docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf` — ISA and architecture.
- `docs/datasheets/SPVS002C_TMS34010_Graphics_System_Processor_199106_altscan.pdf`
  — electrical and pin-level timing.
- `docs/ti-official/TMS34061_Users_Guide.pdf` — VRAM/CRTC companion.
- `emulation/mame/UPSTREAM.md` — behavioral cross-check only; do not copy
  emulator structure into RTL.

Do not use the older `TMS34010_docs` repository.

Every architectural implementation decision must cite a section, page, or
file from the submodule. If the specification does not settle a decision,
record it in `docs/assumptions.md` with `TODO/spec-uncertain`, keep the choice
isolated, and do not present it as verified compatibility.

The `third_party` submodule is reference material. Do not edit it as part of
normal core work.

## Start-of-task checklist

1. Run `git status --short --branch` and preserve unrelated user changes.
2. Read the latest completed task and roadmap in `tasks.md`.
3. Read the relevant rows in `docs/instruction_coverage.md` and entries in
   `docs/assumptions.md`.
4. Read the applicable specification sections in the pinned submodule.
5. For RTL changes, load the relevant documents from
   `docs/hdl-coding-guidelines/` as described below.
6. State a small objective and acceptance criteria before implementing.

Do not select work solely from stale `TODO` comments. Cross-check the current
RTL, tests, task log, changelog, and specification first.

## Project navigation

- `tasks.md` — task history, acceptance criteria, commit hashes, and roadmap.
- `changelog.md` — dated implementation history.
- `docs/architecture.md` — module map, datapath/control strategy, and gaps.
- `docs/assumptions.md` — non-spec-derived or ambiguous decisions.
- `docs/instruction_coverage.md` — per-instruction implementation/test status.
- `docs/status_audit.md` — primary-page N/C/Z/V matrix and undefined-bit
  policy.
- `docs/completion_audit.md` — complete ISA reconciliation and ordered
  project-level exit gates.
- `docs/timing_notes.md` — long paths, multicycle operations, and FPGA timing.
- `docs/memory_map.md` — bit-addressed memory model and I/O register map.
- `docs/hdl-coding-guidelines/` — authoritative Cyclone V RTL style bundle.
- `fpga/tms34010_cyclone_v.qsf` — sole Quartus project assignment source for
  the `5CSEBA6U23I7` top, RTL file set, and 63 physical pins.
- `fpga/tms34010_cyclone_v.sdc` — complete clock, CDC, reset, MCP, and I/O
  timing contract.
- `fpga/PINOUT.md` and `fpga/IMPLEMENTATION_EVIDENCE.md` — board mapping,
  reproducible report results, accepted warnings, and environmental bounds.
- `rtl/tms34010_pkg.sv` — sole home for shared architectural constants and
  typedefs; do not scatter magic architectural values through the RTL.
- `rtl/memory/tms34010_field_sequencer.sv` — synthesizable translation from
  core bit fields to aligned 16-bit physical-word requests.
- `rtl/memory/tms34010_bus_arbiter.sv` — fixed-priority local-cycle owner,
  refresh-event retention, CPU RMW reservation, and HOLD restart signaling.
- `rtl/memory/tms34010_memory_fabric.sv` — field sequencer plus all-client
  arbiter composition behind one abstract controller boundary.
- `rtl/memory/tms34010_local_bus.sv` — standalone 8× original-pin phase
  engine, LRDY waits, address/status multiplexing, explicit screen/SRT VRAM
  transfers, and reset initialization.
- `rtl/cdc/tms34010_local_bus_bridge.sv` — two-phase MCP command/response
  bridge between core and 8× domains; payload buses are held stable while
  attributed request/ack toggles cross through 2FF synchronizers.
- `rtl/cdc/tms34010_cdc_mailbox.sv` — one-entry coherent MCP word crossing
  used for video configuration, live commands/status, and DIP delivery.
- `rtl/cdc/tms34010_screen_cdc.sv` — held VCLK-to-core screen transaction;
  bundled SRFADR/DPYTAP/ORG stays stable until physical completion returns.
- `rtl/video/tms34010_video_subsystem.sv` — dedicated VCLK owner composing
  internal/external noninterlaced/interlaced timing, active-low sync
  recognition and direction, field-aware display-address scheduling, every
  core/VCLK mailbox, and the screen transaction bridge.
- `rtl/tms34010_system.sv` — synthesizable functional wrapper connecting the
  core's CPU, host, display, and refresh clients to the memory fabric.
- `rtl/tms34010_pin_system.sv` — integrated functional system, CDC bridges,
  original local-bus/HOLD/RUN-EMU/host pins, shared HLDA/EMUA output, HRDY,
  split HD data/output-enable boundary, and active-low video-sync
  inputs/split output enables.
- `rtl/fpga/tms34010_cyclone_v_top.sv` — DE10-Nano realization boundary
  composing the PLL, per-domain reset release, pin system, and physical pads.
- `rtl/fpga/tms34010_fpga_io.sv` — sole home for top-level HD/LAD/control/
  sync tri-states and active-low video-sync conversion.
- `rtl/fpga/tms34010_cyclone_v_pll.sv` — vendor-isolated 50/200 MHz clock
  wrapper; portable simulation uses its explicit elaboration bypass.
- `rtl/fpga/tms34010_cyclone_v_video_pll.sv` — independent 50 MHz video PLL
  with phase-zero internal VCLK and 180-degree physical VIDEO_VCLK.
- `rtl/fpga/tms34010_reset_sync.sv` — active-high per-domain reset-release
  conditioner driven by board reset and both PLL lock indications.
- `rtl/host/tms34010_host_bus.sv` — asynchronous original-pin host access
  qualification, HCS/HSTCTL and busy wait generation, bundled request
  capture, response retention, and byte-lane HD direction.
- `rtl/cdc/tms34010_emu_bridge.sv` — held EMU-event handshake, synchronized
  halt level, exact Q1/Q2 phasing, and Q3/Q4 HLDA mux.
- `rtl/cdc/tms34010_sync_bit.sv` — dedicated, Quartus-recognizable two-flop
  synchronizer used for external interrupt, HOLD, RUN/EMU, and EMUA bridge
  levels plus raw HSYNC/VSYNC inputs.
- `sim/models/sim_memory_model.sv` — behavioral, nonsynthesizable bit-addressed
  memory target used by integration tests; its public requests route through
  the field sequencer.

## Build, simulation, and lint

The scripts support Questa/ModelSim when `vlog`, `vsim`, and `vlib` are
available, and otherwise fall back to Verilator when installed:

```sh
scripts/sim.sh <tb_name>
scripts/regress.sh
scripts/lint.sh
scripts/synth_quartus.sh
```

Tool overrides are `VLOG`, `VSIM`, `VLIB`, `VERILATOR`, and `QUARTUS_SH`.
Testbenches are self-checking and must print `TEST_RESULT: PASS`. A simulator
exit code alone is not a passing result. `scripts/regress.sh` discovers every
`sim/tb/tb_*.sv` bench, retains per-test logs under `work/regression/`, and
accepts `REGRESS_JOBS=<N>` for parallel Verilator builds.

`scripts/synth_quartus.sh` requires Quartus Prime Lite 17.0.2. It deletes
only this project's generated implementation directories, then runs a clean
map, fit, assembly, multicorner TimeQuest analysis, and strict report
validation. Its pass requires exact tool/device/top identity, all four
phases, the reviewed warning allowlist, 63 fitted pins, complete constraints,
nonnegative setup/hold/minimum-pulse timing with zero TNS, every required
synchronizer, and the fixed resource envelopes. Do not call a manual Quartus
phase or a stale report a project pass.

RTL lint is a zero-diagnostic gate. Do not silently suppress new warnings or
call a warning-bearing run "clean."

## Change workflow

Keep each implementation increment small enough to review and validate:

1. Choose or add one numbered task in `tasks.md`.
2. Record the specification source and observable acceptance criteria.
3. Implement the smallest useful synthesizable change.
4. Add or update self-checking tests under `sim/tb/`.
5. Run `scripts/lint.sh`, the focused test, and proportionate regressions.
6. Update affected architecture, assumptions, coverage, timing, or memory-map
   documentation.
7. Update `tasks.md` and `changelog.md`.
8. Recheck `git diff` and `git status`.

Do not commit or push unless the user asks. When the user requests a commit,
keep one task per commit, stage files explicitly, and record the resulting
commit hash in `tasks.md`. When the user requests publication, push only after
the local commit and validation are confirmed. Report any authentication or
network failure; never claim a push succeeded when it did not.

The historical completion roadmap ends at Task 0160. The active
production-revision GPU roadmap is Task 0161–0174. New work after it still
requires a new numbered task with explicit scope and acceptance criteria; do
not silently extend either baseline.

Historical task entries and changelog entries describe what was true at the
time. Correct current summaries when they drift, but do not rewrite historical
acceptance criteria merely to make them read as current documentation.

## HDL coding guidelines

`docs/hdl-coding-guidelines/` is the authoritative Cyclone V bundle (target
part `5CSEBA6U23I7`, DE10-Nano). Begin at `00-INDEX.md`.

For new RTL, read at least:

- `12-synthesizable-sv-subset.md`
- `13-registers-and-combinational-blocks.md`
- `14-finite-state-machines.md` when an FSM is involved
- `16-resource-and-state-economy.md`
- `17-era-faithful-microarchitecture.md`

For review, also read `90-anti-patterns.md` and
`91-core-bringup-checklist.md`. Load the memory, DSP, CDC, handshake, timing,
and Quartus-report chapters when those topics are in scope.

Two intentional project choices override the bundle's conventions without
violating its contracts:

- Reset is synchronous active-high `rst` (assumption A0003). Do not convert it
  to active-low.
- Every `rtl/` file starts with `` `default_nettype none `` and restores
  `` `default_nettype wire `` at the end.

## SystemVerilog rules

Use:

- `logic`, explicit widths, and named constants.
- `always_ff` with nonblocking assignments for sequential state.
- `always_comb` with blocking assignments and safe defaults.
- typed enums for FSMs and packed structs for related control/data.
- explicit reset behavior, default transitions, and a `default:` arm in every
  `case`; `unique` or `priority` does not replace `default:`.
- small composable modules with clear, bounded combinational paths.

Forbid in synthesizable RTL:

- `#` delays, `force`/`release`, `fork`/`join`, classes, dynamic arrays,
  queues, DPI, file I/O, randomization, simulation system tasks, unbounded
  `while`, runtime-variable loops, and simulation-only `initial` blocks.
- `/` or `%`, except a compile-time power-of-two operation expressed as a
  shift/mask or a dedicated, documented, tested multicycle divider.
- accidental latches, combinational loops, hidden clock-domain crossings,
  fabric-derived clocks, and magic architectural numbers.

Large FPGA memories belong behind wrappers under `rtl/fpga/`; document read
latency at each wrapper and do not assume combinational BRAM reads. Any CDC
belongs in a clearly named CDC module and must be documented in
`docs/timing_notes.md`.

Graphics operations are hardware datapaths plus FSMs with counters, explicit
memory transactions, and completion conditions. Never implement them as a
software-style loop in a combinational block.

## Before adding a module

Write down:

- purpose and specification citation;
- ports and clock domains;
- stored state and reset values;
- combinational paths and FSM states;
- expected latency and throughput;
- expected ALM, register, RAM, and DSP use;
- RAM/ROM inference and read latency, if any;
- tests that cover normal, boundary, stall, and reset behavior.

After implementation, review for latches, combinational loops, long paths,
division/modulo, runtime loops, reset omissions, assignment misuse, poor
memory inference, magic values, missing citations, and missing tests.

## Handoff format

Report the outcome, changed files, exact tests and results, documentation
updates, known limitations, git state, and the next smallest useful task.
Distinguish verified behavior from assumptions and from untested claims.
