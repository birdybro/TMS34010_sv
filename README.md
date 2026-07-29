# TMS34010_sv

A synthesizable SystemVerilog reimplementation of the Texas Instruments
TMS34010 Graphics System Processor, initially targeting Intel/Altera Cyclone V.
This is FPGA RTL, not a software emulator.

## Current status

Functional implementation work is complete through Task 0159. Task 0124
reconciled the official instruction summary and all remaining system
integration work into `docs/completion_audit.md`; Task 0125 closed the
logical-status and ANDI/ANDNI semantic findings, and Tasks 0126–0127 landed
the two missing memory-to-memory MOVE forms. Task 0128 implemented the EMU
handshake and completed every row in the official instruction summary. Task
0129 corrected the MOVK/ADDK/SUBK encoded-zero constant to the specified
value 32. Task 0130 corrected all shift encodings, SLA overflow, and
per-instruction status masks. Task 0131 corrected MOVI C preservation for
both immediate widths. Task 0132 resolved the REV value and EXGPC alignment
rules directly against their individual instruction pages. Task 0133 resolved
FILL XY's final linear DADDR writeback and W=0 status preservation. Task
0134 corrected SUBXY's coordinate comparisons to signed 16-bit
semantics. Task 0135 completed the primary-page instruction status audit,
resolved A0009, corrected divide/modulo and odd-result multiply edge cases,
and completed W=3/PIXT graphics-window status behavior. Task 0136 resolved
the remaining field-alignment assumption and added exact
specification-derived sequencing from 1–32-bit architectural fields onto
aligned 16-bit physical words. Task 0137 implemented the source-specific
INTPEND/INTENB contract, synchronized both active-low external interrupt
pins, and exposed synchronous host/display request sidebands. Task 0138
corrected REFCNT to the guide's continuous 14-bit decrementing counter,
integrated it with CONTROL.RR/RM and the I/O register file, and exposed its
refresh request, row, and mode at the core boundary. Task 0139 integrated the
internal noninterlaced video counters/timing registers, corrected DIP to the
start of horizontal blanking, and exported timing outputs. Task 0140
corrected the inherited sync/blank interval endpoints for the guide's
one-VCLK equality-to-output delay. Task 0141 made DPYADR live and added a
held screen-refresh request/acknowledge client with frame reload, line
cadence, and completion-time address updates. Task 0142 completed direct
host-side HSTCTL ownership, HINT, HCS-selected reset halt, and
instruction-boundary HLT/NMI behavior. Task 0143 added the synchronous
HSTADR/HSTDATA indirect-memory engine, including LBL byte ordering,
INCR/INCW address sequencing, prefetch buffering, and held local-word
requests. Task 0144 integrated that engine with the processor-visible I/O
registers and replaced the temporary HSTCTL-only core boundary with one
synchronous four-register host port plus an exposed held local-word client.
Task 0145 added the specification-priority local-bus arbiter, including
held-owner completion, pulsed DRAM-refresh retention, CPU partial-word RMW
reservation, inter-word preemption, and the external-HOLD restart exception.
Task 0146 connected every core memory client through the field sequencer and
arbiter behind one synthesizable functional-system/controller boundary.
Task 0147 added the standalone original-pin local-bus phase engine with
LCLK1/LCLK2, exact address/status multiplexing, LRDY extension, all landed
word/screen/DRAM/I/O cycle families, and eight post-reset RAS-only cycles.
Task 0148 connected that engine to the core-clock memory fabric through a
two-phase coherent command/response bridge, propagated opcode IAQ and
screen-refresh ORG, and added an integrated pin-system wrapper.
Task 0149 routes processor accesses to on-chip registers around field
sequencing into the specified two-clock physical I/O read/write cycles and
commits writes exactly once on returned completion.
Task 0150 routes host-indirect accesses through those same physical cycles,
adds an independent shared-register read view, and commits host-side writes
only after their returned completion.
Task 0151 connects the active-low physical HOLD input to the existing
fixed-priority arbiter through synchronized level handshakes, emits the
Q3/Q4-only active-low HOLDA component, and phases LAD/control output-enable
release and reacquisition at the specified Q2/Q3 boundaries.
Task 0152 synchronizes RUN/EMU, transfers each architectural EMU event into
the 8× domain with a held handshake, and combines exact Q1/Q2 EMUA with
Q3/Q4 HLDA on the original shared output pin.
Task 0153 replaces the integrated wrapper's synchronous host boundary with
the original active-low HCS/HREAD/HWRITE/HLDS/HUDS controls, HFS selection,
byte-lane HD direction, immediate HRDY waits, coherent bundled capture, and
prior-indirect busy backpressure.
Task 0154 closes the remaining ordinary I/O-register reserved behavior:
CONTROL/DPYCTL/DPYTAP masks apply identically to processor and host-indirect
writes, and the four reserved register locations ignore writes and read zero.
Task 0155 introduces the independent VCLK domain: HCOUNT/VCOUNT, timing
compares, DPYADR, and automatic screen scheduling now live there, while
atomic configuration/command/status mailboxes, lossless DIP delivery, and a
bundled held screen-request bridge isolate every core/VCLK crossing.
Task 0156 implements internally generated interlaced video: the odd field
starts at HTOTAL/2, performs the specified VESYNC midline VCOUNT advance,
returns to the even field at the full-line boundary, and applies signed
DUDATE/2 to the DPYSTRT reload preceding that even field.
Task 0157 implements external video synchronization: independently
synchronized active-low HSYNC/VSYNC inputs receive the specified 2.5-VCLK
recognition delay, HTOTAL/VTOTAL provide missing-sync fallbacks, HSD selects
horizontal input or output operation, external interlace uses the documented
horizontal recognition window, and explicit sync output enables propagate to
the pin-system boundary.
Task 0158 consumes DPYCTL.SRT and converts only graphics pixel reads/writes
into the specified explicit VRAM memory-to-register/register-to-memory local
cycles. It adds the exact TR/QE/W/address-status phases, retains ordinary
instruction/data/I/O/host traffic, and avoids unnecessary destination reads
for direct replace operations. This also corrects the completion boundary:
the TMS34010 has no pixel-data output pins; attached VRAM supplies pixels
through its serial port.
Task 0159 adds the Cyclone V realization boundary: wrapped core/bus and
phase-separated video PLLs, independent continuous VCLK, per-domain
active-high reset release, actual HD/LAD/control/sync tri-states, active-low
sync inversion, and a DE10-Nano top-level port surface. The reusable
hierarchy now carries separate core, bus, and video resets so every clock
domain releases synchronously.
The repository currently contains:

- a multicycle 32-bit core with bit-addressed instruction and data access;
- A/B register files, shared stack pointer, status register, ALU, shifter,
  multiplier, and multicycle divider;
- the instruction families tracked in `docs/instruction_coverage.md`, including
  field-aware MOVE, stack/trap/interrupt operations, and conditional control;
- PIXT, FILL, PIXBLT, DRAV, and LINE graphics datapaths with pixel processing,
  plane masking, transparency, and all window modes;
- on-chip I/O-register storage plus every maskable pending-source boundary
  and maskable/nonmaskable entry path, including defined reserved-field and
  reserved-location behavior;
- architectural reset and illegal-opcode vector entry, including
  HCS-selected host-present reset halt;
- a synchronous direct-host HSTCTL boundary with complementary host/processor
  field ownership, active-low HINT, and instruction-boundary HLT;
- an integrated synchronous four-register host engine with shared
  processor/host HSTADR/HSTDATA state, byte-order triggers, pre-read/post-write
  incrementing, stalled-request stability, and an exposed local-word client;
- synchronized physical RUN/EMU sampling, exact Q1/Q2 EMUA pulse/halt
  indication, and resume;
- a synthesizable field-to-word sequencer covering §4.1 alignment cases A–G,
  partial-word RMW locking/restart, and arbitrary word-side stalls;
- a synthesizable fixed-priority HOLD/screen/DRAM/host/CPU local-cycle
  arbiter with held grants and a captured DRAM-refresh event;
- an integrated functional-system wrapper that converges CPU/graphics,
  screen, DRAM-refresh, and host-indirect traffic on one abstract controller;
- a standalone 8×-clock original-pin local-bus engine covering ordinary word,
  screen-transfer, program-controlled MTR/RTM, RAS-only, CAS-before-RAS, and
  I/O cycles, including LRDY waits and reset initialization;
- an integrated core-clock-to-8× pin-system wrapper using a lossless MCP
  command/response CDC, including returned read data, IAQ, and screen ORG;
- processor and host-indirect on-chip I/O access through dedicated
  RAS/LAL-only physical cycles, including internal read data and
  completion-qualified register writes;
- active-low physical HOLD sampling and synchronized grant return, with
  early Q3/Q4 HOLDA indication and explicit Q2/Q3 LAD/control output-enable
  release/resume sequencing;
- the original shared HLDA/EMUA output, with lossless EMU-event CDC and
  phase-exclusive EMUA/HLDA selection under simultaneous halt and HOLD;
- the asynchronous original-pin host bus, with legal-access qualification,
  HCS-triggered HSTCTL delay, coherent register request/response capture,
  indirect-busy waits, latched read data, and per-byte HD output enables;
- integrated dedicated-VCLK internal/external noninterlaced/interlaced video
  timing with live HCOUNT/VCOUNT, synchronized active-low sync inputs,
  DPYCTL.DXV/HSD direction control and output enables, DPYCTL.ENV blanking,
  field-aware DIP, live DPYADR, signed half-DUDATE field starts, and held
  screen-refresh scheduling; coherent MCP configuration/command/status,
  event, and completed-screen-transaction crossings; plus integrated
  REFCNT/refresh-request generation;
- DPYCTL.SRT classification for every graphics engine, with explicit
  program-controlled VRAM MTR/RTM pin cycles and unaffected nonpixel traffic;
- a Cyclone V top-level adapter with vendor-isolated PLLs, three reset
  conditioners, active-low video-clock/sync phase mapping, and IOE-ready
  bidirectional host/local/video pads;
- 146 self-checking SystemVerilog testbenches, including non-integer-clock
  video CDC, cycle-by-cycle internal interlace and external-sync coverage,
  end-to-end SRT graphics-cycle coverage, direct FPGA pad/reset checks, and
  an exhaustive 65,536-opcode static status-policy sweep.

This is not yet a fully signed-off FPGA system. ISA/status reconciliation and
the synthesizable Cyclone V adapter are complete; the audit records the
remaining real Quartus project/constraints plus timing/resource/CDC
validation. A board-level design still needs external VRAM or an equivalent
memory/video subsystem to consume the landed transfer cycles and emit pixels;
that device behavior is not part of this processor.

## Getting started

```sh
git submodule update --init --recursive
scripts/lint.sh
scripts/regress.sh
scripts/sim.sh tb_smoke
scripts/sim.sh tb_pixt_win
```

The scripts prefer Questa/ModelSim and fall back to Verilator. Testbenches must
print `TEST_RESULT: PASS`; the simulator exit code alone is not treated as a
pass. `scripts/regress.sh` discovers and runs all testbenches; set
`REGRESS_JOBS` to parallelize the Verilator flow. `scripts/synth_quartus.sh`
remains a placeholder until Task 0160 and does not yet perform a real
synthesis or timing run.

Before changing RTL, read [AGENTS.md](AGENTS.md), [tasks.md](tasks.md),
[architecture.md](docs/architecture.md), and the relevant specification in the
pinned `third_party/TMS34010_Info` submodule.

## Repository map

- `rtl/` — synthesizable package, core, memory sequencing, I/O, video, and
  refresh RTL.
- `sim/models/` — nonsynthesizable behavioral memory model.
- `sim/tb/` — focused self-checking testbenches.
- `docs/` — architecture, assumptions, coverage, memory/timing notes, and the
  authoritative Cyclone V HDL coding-guideline bundle.
- `docs/completion_audit.md` — primary-spec reconciliation and ordered exit
  gates for project completion.
- `docs/status_audit.md` — complete individual-instruction N/C/Z/V policy,
  undefined-bit handling, and regression evidence.
- `scripts/` — lint, simulation, and Quartus entry points.
- `tasks.md` / `changelog.md` — task-level design and implementation history.
- `third_party/TMS34010_Info/` — pinned primary/reference documentation.
