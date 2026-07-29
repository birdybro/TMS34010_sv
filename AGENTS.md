# AGENTS.md

Repository-wide instructions for coding agents working on this project.

## Project

This repository is a synthesizable FPGA reimplementation of the Texas
Instruments TMS34010 Graphics System Processor in SystemVerilog. The initial
target is Intel/Altera Cyclone V.

This is RTL, not a software emulator. Model explicit hardware structure:
datapaths, muxes, registers, FSMs, counters, and memory transactions. Do not
translate a software implementation into one large procedural HDL block.

The functional implementation is complete through Task 0151. Task 0124
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
The implementation includes the multicycle CPU core, the currently tracked
instruction set, bit-field memory operations, graphics operations through
LINE/DRAV/PIXT/PIXBLT/FILL with window checking, I/O registers, reset-vector
fetch, maskable/NMI entry with architectural service-context ST
initialization, and the illegal-opcode trap. Video timing is functionally
integrated through its screen-refresh client and physical memory-to-register
cycle; a dedicated VCLK/CDC boundary, external sync, interlace, and VRAM
serial-display service remain future work. The shared HLDA/EMUA pin mux,
HRDY, and the asynchronous host pin wrapper remain future physical-wrapper
work. Read
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
- `rtl/tms34010_pkg.sv` — sole home for shared architectural constants and
  typedefs; do not scatter magic architectural values through the RTL.
- `rtl/memory/tms34010_field_sequencer.sv` — synthesizable translation from
  core bit fields to aligned 16-bit physical-word requests.
- `rtl/memory/tms34010_bus_arbiter.sv` — fixed-priority local-cycle owner,
  refresh-event retention, CPU RMW reservation, and HOLD restart signaling.
- `rtl/memory/tms34010_memory_fabric.sv` — field sequencer plus all-client
  arbiter composition behind one abstract controller boundary.
- `rtl/memory/tms34010_local_bus.sv` — standalone 8× original-pin phase
  engine, LRDY waits, address/status multiplexing, and reset initialization.
- `rtl/cdc/tms34010_local_bus_bridge.sv` — two-phase MCP command/response
  bridge between core and 8× domains; payload buses are held stable while
  attributed request/ack toggles cross through 2FF synchronizers.
- `rtl/tms34010_system.sv` — synthesizable functional wrapper connecting the
  core's CPU, host, display, and refresh clients to the memory fabric.
- `rtl/tms34010_pin_system.sv` — integrated functional system, CDC bridge,
  and original local-bus pins; synchronous host and abstract HOLD boundaries
  remain exposed.
- `rtl/cdc/tms34010_sync_bit.sv` — dedicated, Quartus-recognizable two-flop
  synchronizer used for each asynchronous external interrupt level.
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

`scripts/synth_quartus.sh` is currently only a placeholder/tool-discovery
check. Its zero exit status is not evidence of synthesis, fit, timing closure,
or Cyclone V compatibility. A real Quartus project, constraints, and reports
remain future work.

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
