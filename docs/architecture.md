# Architecture

> Status: **implemented and ISA/status-audited through Task 0158, with
> integration gaps**. The core executes the instruction and graphics
> operations tracked in `instruction_coverage.md`; reset-vector fetch, I/O
> registers, interrupt entry, and the abstract RUN/EMU handshake are
> integrated. Direct HSTCTL access, HINT, HCS-selected reset halt, and HLT
> are also integrated. The synchronous four-register host engine shares
> HSTADR/HSTDATA with processor I/O accesses and exports its held local-word
> client. Architectural fields are sequenced onto aligned 16-bit words, and
> the fixed-priority local-cycle arbiter has landed with CPU RMW/HOLD restart
> semantics. The functional-system wrapper connects every core client through
> that fabric to one abstract controller boundary.
> An 8×-clock local-bus engine now generates the original
> LCLK/LAD/control phases, address/status formats, LRDY waits, and reset
> initialization. A two-phase MCP bridge coherently connects it to the
> core-clock fabric, including returned read data, IAQ, and screen ORG.
> Processor and host-indirect on-chip I/O requests now use the integrated
> physical I/O read/write cycles with completion-qualified side effects.
> Active-low HOLD is sampled in the physical phase engine and exchanged with
> the core arbiter through synchronized levels; HOLDA and every affected bus
> output enable follow the documented Q2/Q3 release and resume boundaries.
> Physical RUN/EMU is synchronized into the core, and exact Q1/Q2 EMUA is
> combined with Q3/Q4 HLDA on the original shared output.
> The asynchronous original-pin host bus qualifies active-low access
> strobes, inserts HRDY waits, captures one coherent four-register request,
> and returns latched read data through selected HD byte lanes.
> Ordinary I/O storage now enforces every documented reserved field and
> reserved register location consistently for processor and host access.
> Internal/external noninterlaced/interlaced video timing and the held
> screen-refresh client now live in a dedicated VCLK domain. Atomic
> configuration/command/status mailboxes, lossless DIP delivery, a completed
> bundled screen-transaction bridge, and individually synchronized active-low
> HSYNC/VSYNC inputs isolate it from the core clock and asynchronous pins.
> DPYCTL.SRT now converts only graphics pixel reads/writes into explicit VRAM
> MTR/RTM cycles with the documented physical phases. Pixel data comes from
> the attached VRAM serial port rather than a processor pin. The remaining
> system-level exit gates are recorded in `completion_audit.md`.

## Specification source

Primary reference: `third_party/TMS34010_Info` (submodule, pinned commit).

Authoritative documents inside the submodule:

- `docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf` — architecture and ISA
  reference. **Treat this as the spec** when documentation conflicts.
- `docs/datasheets/SPVS002C_TMS34010_Graphics_System_Processor_199106_altscan.pdf`
  — electrical and pin-level spec; useful for memory cycle timing and host
  interface signaling.
- `docs/ti-official/1986_SPVU001_TMS34010_Users_Guide_first_edition.pdf` —
  earlier edition; useful for cross-checking ambiguities.
- `docs/ti-official/TMS34061_Users_Guide.pdf` — VRAM/CRTC companion; informs
  the video/display subsystem boundary.
- `emulation/mame/UPSTREAM.md` — pointer to MAME's `tms34010` core for
  behavioral cross-checks **only**. Software emulator structure is not copied
  into RTL.

Every implementation decision must cite a section/page/file from the
submodule. If it cannot, the assumption goes into `docs/assumptions.md` with
a `TODO/spec-uncertain` marker.

## Top-level block diagram

```
┌──────────────────────────── tms34010_system ─────────────────────────────┐
│                                                                         │
│  ┌────────────── tms34010_core ──────────────┐                           │
│  │ PC / decode / datapath / graphics / I/O   │                           │
│  │       ⇅ coherent video MCP mailboxes      │◄──── independent VCLK     │
│  │ CPU fields   host   screen   DRAM refresh │                           │
│  └──────┬────────┬────────┬────────────┬──────┘                           │
│         │        │        │            │                                  │
│  ┌──────▼────────▼────────▼────────────▼────── tms34010_memory_fabric ─┐ │
│  │ field sequencer (CPU 1–32 → 16-bit) → fixed-priority local arbiter │ │
│  └───────────────────────────┬─────────────────────────────────────────┘ │
│                              │ abstract held local cycle                  │
└──────────────────────────────│────────────────────────────────────────────┘
                               ▼
            ┌──── tms34010_local_bus_bridge (toggle MCP) ────┐
            │ held command → 8×; held read data/ack → core   │
            └─────────────────────────┬───────────────────────┘
                                      ▼
             ┌──────── tms34010_local_bus (8× clock) ────────┐
             │ LCLK1/2, LAD, RAS/CAS/LAL/W/TR/DEN/DDOUT      │
             └────────────────────────────────────────────────┘
```

The CPU, graphics execution engines, I/O register storage, interrupt entry,
and REFCNT refresh requester live in or directly under `tms34010_core`.
`tms34010_video_subsystem` keeps timing/display-address state in VCLK and
crosses only coherent configuration, live commands/status, DIP, and bundled
screen transactions; raw active-low sync pins enter through individual
one-bit synchronizers. The field-to-word sequencer and local-cycle arbiter are
composed by
`tms34010_memory_fabric`; `tms34010_system` connects every core client to that
fabric. `tms34010_local_bus_bridge` crosses that held command and its response
coherently into/out of the 8× domain, while `tms34010_pin_system` composes the
system, bridge, and `tms34010_local_bus`; `tms34010_emu_bridge` closes the
RUN/EMU event/level CDC and shared output mux, and
`tms34010_host_bus` closes the asynchronous host-control/data boundary. The
pin system also exposes split HSYNC/VSYNC direction. The FPGA
clock/constraint project remains planned.

## Test substrate

For tests beyond pure FSM-state checks, a behavioral memory model under
`sim/models/sim_memory_model.sv` retains the core request/ack boundary and a
one-cycle 16-bit backing store. Every arbitrary 1–32-bit request passes
through the synthesizable `tms34010_field_sequencer`, including three-word
straddles and partial-word read/modify/write preservation. Only the backing
target is simulation-specific. The original-pin controller has a standalone
phase-level regression. `tb_pin_system` additionally boots the real core from
a pin-level LAD target through the integrated CDC, verifies the mandatory
reset initialization ordering, executes external asynchronous host accesses,
and observes the resulting processor/host-indirect physical I/O cycles.

## Module map

| Path                                    | Phase | Status      | Notes |
|-----------------------------------------|-------|-------------|-------|
| `rtl/tms34010_pkg.sv`                   | 0+    | **landed** | architectural constants, I/O/interrupt/graphics constants, FSM and decode types |
| `rtl/tms34010_system.sv`                | 6     | **landed through Task 0158** | functional-system wrapper connecting all core memory clients, explicit VCLK, raw video-sync pins, and the graphics SRT tag to the core/fabric boundary |
| `rtl/tms34010_pin_system.sv`            | 6     | **landed through Task 0158** | integrated core/VCLK/8× system, MCP bridges, original-pin local bus including SRT transfers, physical HOLD/RUN-EMU/host controls, HRDY, split HD direction, shared HLDA/EMUA, and split video-sync direction |
| `rtl/core/tms34010_core.sv`             | 0+    | **landed through Task 0158** | multicycle CPU, memory/host/interrupt/graphics engines, explicit VCLK, coherent DRAM/screen/video boundaries, and graphics-only DPYCTL.SRT tagging |
| `rtl/core/tms34010_pc.sv`               | 1     | **landed**  | bit-addressed PC: reset/load/advance, advance amount in bits |
| `rtl/core/tms34010_regfile.sv`          | 2+    | **landed**  | A0–A14, B0–B14, shared SP (A15/B15 alias); 3R/1W; async read |
| `rtl/core/tms34010_alu.sv`              | 2     | **landed**  | combinational ADD/ADDC/SUB/SUBB/CMP/AND/ANDN/OR/XOR/NOT/NEG/PASS_A/PASS_B + N/C/Z/V flags |
| `rtl/core/tms34010_shifter.sv`          | 2     | **landed through Task 0130** | 32-bit barrel shifter: SLL/SLA/SRL/SRA/RL/RR, carry, zero/sign, and SLA overflow |
| `rtl/core/tms34010_status_reg.sv`       | 2     | **landed**  | 32-bit ST: selective N/C/Z/V update vs full POPST-style write; named flag outputs |
| `rtl/core/tms34010_decode.sv`           | 3+    | **landed through Task 0135** | combinational decoder; per-instruction flag masks; unsupported encodings route to ILLEGAL |
| `rtl/core/tms34010_control.sv`          | 3     | merged into core.sv | top-level control and graphics FSMs; extraction remains an optimization option |
| `rtl/memory/tms34010_field_sequencer.sv` | 5, 6 | **landed (Task 0136)** | translates one bit-addressed 1–32-bit request into ascending aligned 16-bit word cycles; direct full-word writes, partial-word RMW lock, arbitrary word-side stalls |
| `rtl/memory/tms34010_local_bus.sv`      | 6     | **integrated through Task 0158** | 8× original-pin LCLK/row/column/data phases, address/status encoding, screen and explicit MTR/RTM transfers, LRDY waits, I/O/reset cycles, and phased HOLD/HOLDA output-enable release |
| `rtl/memory/tms34010_cache.sv`          | 6     | not started | optional instruction cache |
| `rtl/memory/tms34010_bus_arbiter.sv`    | 6     | **landed through Task 0158** | registered HOLD/screen/DRAM/host/CPU priority; held active owner; refresh capture; CPU RMW/HOLD restart; I/O and graphics MTR/RTM cycle selection |
| `rtl/memory/tms34010_memory_fabric.sv`  | 6     | **landed through Task 0158** | registered CPU request/SRT classification; external field sequencing; processor-I/O bypass; host-I/O classification; screen/DRAM/host/CPU arbitration |
| `rtl/graphics/tms34010_pixel_addr.sv`   | 5, 7  | not separate | XY/linear conversion currently resides in the core |
| `rtl/graphics/tms34010_pixblt.sv`       | 7     | not separate | PIXBLT/FILL datapaths and FSM states currently reside in the core |
| `rtl/graphics/tms34010_window.sv`       | 7     | not separate | all four window modes are implemented in the core |
| `rtl/graphics/tms34010_plane_mask.sv`   | 7     | not separate | PPOP, plane mask, and transparency logic currently reside in the core |
| `rtl/graphics/tms34010_line_draw.sv`    | 7     | not separate | LINE and DRAV FSMs currently reside in the core |
| `rtl/host/tms34010_host_if.sv`          | 6     | **integrated through Task 0150** | shared processor/host HSTADR/HSTDATA storage, independent indirect-I/O port, LBL byte completion, prefetch, INCR/INCW, held local-word client, and HSTCTL pass-through |
| `rtl/host/tms34010_host_bus.sv`         | 6     | **landed (Task 0153)** | asynchronous HCS/direction/byte qualification, HCS/HSTCTL and indirect-busy HRDY waits, bundled request capture, latched response, and per-byte HD output enables |
| `rtl/cdc/tms34010_sync_bit.sv`          | 6     | **integrated through Task 0157** | dedicated attributed two-flop synchronizer used for external levels, active-low HSYNC/VSYNC, and every MCP request/acknowledge toggle |
| `rtl/cdc/tms34010_local_bus_bridge.sv`  | 6     | **landed (Task 0148)** | two-phase MCP command/response CDC; source-held payloads and returned read data, one outstanding transaction |
| `rtl/cdc/tms34010_emu_bridge.sv`        | 6     | **landed (Task 0152)** | source-held EMU-event handshake, synchronized halt level, exact Q1/Q2 EMUA windows, and Q3/Q4 HLDA shared-pin mux |
| `rtl/cdc/tms34010_cdc_mailbox.sv`       | 9     | **landed (Task 0155)** | one-entry packed MCP word crossing with source-ready/accept and destination-valid pulse |
| `rtl/cdc/tms34010_screen_cdc.sv`        | 9     | **landed (Task 0155)** | VCLK-to-core held screen transaction; bundled payload stable until returned physical completion |
| `rtl/io/tms34010_io_regs.sv`            | 6     | **integrated through Task 0158** | memory-mapped I/O/host/interrupt/refresh storage plus explicit VCLK/external-sync boundaries, the DPYCTL.SRT tap, and coherent live-register read views |
| `rtl/video/tms34010_video_subsystem.sv` | 9     | **integrated through Task 0157** | VCLK-domain internal/external noninterlaced/interlaced timing and display composition with atomic config, coalesced live commands, coherent status, DIP event, and screen transaction CDC |
| `rtl/video/tms34010_video.sv`           | 9     | **integrated through Task 0157** | internal/external timing: writable counters, synchronized active-low sync inputs, exact recognition/fallback/interval endpoints, field sequencing, ENV gating, DPYINT, and split output enables |
| `rtl/video/tms34010_display_addr.sv`    | 9     | **integrated through Task 0156** | VCLK-owned live DPYADR, frame/line reloads, signed interlaced DUDATE/2 start, LCSTRT+1 scheduling, and acknowledged SRFADR/DPYTAP/ORG transfer |
| `rtl/video/tms34010_refresh.sv`         | 9     | **integrated (Task 0138)** | exact writable REFCNT bits 2-15 continuous down-counter; CONTROL.RR subtracts 2/1 for 32/64-clock requests, borrow decrements ROWADR, and request/row feed the core refresh-client boundary |
| `rtl/fpga/bram_1r1w.sv`                 | 1     | not started | Cyclone V BRAM wrapper, 1R1W, sync read |
| `rtl/fpga/bram_rom.sv`                  | 1     | not started | sync-read ROM wrapper |

Rows without files describe planned integration boundaries or possible
refactoring, not stub modules. Unsupported instruction encodings route to the
illegal-opcode path rather than silently doing nothing.

## Completion ledger

Task 0124 compared every row in the 1988 User's Guide §12.3 instruction
summary against the decoder, execution paths, tests, and
`instruction_coverage.md`. That reconciliation found two missing MOVE forms,
the missing EMU interface, incorrect shared ANDI/ANDNI semantics, and
provisional logical flag behavior. Task 0125 closed the logical findings with
Z-only masks, both immediate extension conventions, and exact CLR/DEC alias
tests. Tasks 0126–0127 closed both postincrement-destination MOVE rows, and
Task 0128 implemented EMU. Every §12.3 instruction-summary row now has an
implemented coverage entry and named test. Task 0129 corrected the zero-field
constant used by MOVK/ADDK/SUBK to the specified value 32, resolving A0013
and A0018. Task 0130 resolved the shift-family encoding and status
assumptions, including right-count two's-complement fields and SLA overflow.
Task 0131 resolved MOVI's C-preservation mask for both immediate widths.
Task 0132 resolved A0025 from pages 12-79 and 12-233 and regression-locked
REV's `0x00000008` result, EXGPC's low-nibble PC mask, its next-PC exchange,
and both instructions' status preservation. Task 0133 resolved A0029 from
the FILL XY description on page 12-85: the XY start is converted to linear
space and final DADDR is the linear address just beyond the last pixel on the
last row. Task 0134 resolved A0027 by combining SUBXY's status table with the
architectural definition of signed 16-bit XY components; C/V now compare the
source and destination coordinates as signed values. Task 0135 completed the
individual-instruction status audit and resolved A0009. The static policy is
exhaustively checked across all 65,536 opcodes, while focused tests cover
runtime divide/modulo, multiply-result-width, W=3 preclipping, and PIXT
XY-destination distinctions. `status_audit.md` records the complete matrix
and the deterministic handling of Undefined flags. Task 0136 then resolved
A0005 and landed exact §4.1 field-to-word sequencing, including all seven
alignment cases, stalls, reset recovery, and per-word RMW indivisibility.
Task 0137 completed the pending-source half of the I/O/interrupt gate:
dedicated LINT synchronizers, read-only X1P/X2P/HIP, latched DIP/WVP,
host/display set sidebands, and core-level external vector/priority tests.
Task 0138 corrected the refresh model against the individual REFCNT pages and
made it the live I/O register. CONTROL.RR/RM now drive a continuous
interval/row down-counter, while refresh request, decremented row, and mode
leave the core for the local-cycle arbiter. Physical refresh bus service remains
part of the local-memory fabric gate. Task 0139 corrected the old standalone
display-interrupt event from line start to start-of-HBLANK and integrated the
timing registers, live HCOUNT/VCOUNT, DPYCTL.ENV, DIP latch, and timing
outputs. At that checkpoint A0034 recorded a deliberate
same-clock/noninterlaced boundary; Task 0155 later resolves the VCLK half,
Task 0156 closes internal interlace, and Task 0157 closes external
synchronization. Task 0158 closes the graphics SRT transfer consumer.
Task 0140 then
corrected the inherited interval endpoints: end compares remain active at
equality and blank-start compares take effect on the following count, matching
the one-VCLK delay in §§9.5/9.6.

Task 0141 made DPYADR a live register and landed the next display-memory
client boundary. Frame/line events reload its fields from DPYSTRT, SRE
schedules the first and LCSTRT-spaced active-line requests, and a held
SRFADR/DPYTAP payload advances by DUDATE/ORG only after the future controller
acknowledges completion.

Task 0142 completed the synchronous direct-host HSTCTL boundary. Host and
processor writes now obey their complementary low-byte ownership, HINT
reflects INTOUT, and defined high-byte fields are shared. HCS selects a
pre-vector reset halt; run-time HLT stops only at an instruction boundary.
Physical host-pin timing/CDC and integration of the HSTADR/HSTDATA engine
remain with the future host/memory fabric.

Task 0143 landed the synchronous host-indirect engine as a separate module.
It owns aligned HSTADR and buffered HSTDATA state, implements both LBL
byte-last conventions, launches the specified address prefetch/read/write
cycles, orders INCR before reads and INCW after acknowledged writes, and
holds its local-word client stable through stalls. Core I/O-register and
memory-arbiter integration were deliberately deferred.

Task 0144 instantiated that engine in the I/O block. Processor and host
accesses now share HSTADR/HSTDATA state through one generalized four-register
core boundary, while HSTCTL continues through its existing ownership logic.
The resulting held aligned-word host client is exposed from the core for the
next specification-priority arbiter task.

Task 0145 landed that arbiter as a controller-facing module. It registers one
active owner until physical completion, captures a one-clock DRAM-refresh
event, reserves the CPU between a partial-word read and write, permits
preemption between different field words, and restarts the complete RMW pair
when HOLD intervenes. Wiring all core clients through it remains separate
from defining its verified arbitration contract.

Task 0146 composed the field sequencer and arbiter in
`tms34010_memory_fabric`, then connected the core's architectural memory,
host-indirect, screen-refresh, and DRAM-refresh boundaries through it in
`tms34010_system`. The resulting wrapper is synthesizable and exposes only the
synchronous host/interrupt/control inputs, functional video outputs, HOLD,
and one abstract local-cycle controller interface. It is not the final FPGA
top or a claim of original-pin timing.

Task 0147 landed the opposite side of that boundary as a standalone physical
phase engine. `tms34010_local_bus` divides one dedicated 8× timing clock into
the documented LCLK1/LCLK2 Q phases, multiplexes exact word, screen, refresh,
and I/O row/column/status values onto LAD, samples ordinary reads in mid-Q4,
repeats the access period for each low LRDY sample, and performs the eight
zero-row RAS-only cycles after reset. Keeping its command port synchronous to
the 8× domain makes the remaining CDC explicit rather than embedding an
unsafe multi-bit crossing.

Task 0148 closed that functional CDC boundary. The core marks only
`CORE_FETCH` word requests as IAQ in the current cacheless design, and the
display scheduler captures ORG with SRFADR/DPYTAP. Both sidebands join every
existing cycle payload in `local_cycle_cmd_t`. The bridge holds that complete
source register while a request toggle crosses through a 2FF synchronizer,
captures it once in the 8× domain, and uses the reverse acknowledge toggle to
hold and return read data. `tms34010_pin_system` connects the resulting
destination request to the local-bus engine. Physical HOLD/host pins and
Quartus CDC constraints remain distinct exit-gate work.

Task 0149 completes the processor half of the on-chip I/O cycle path. The
core exports its full-address decode, original direction, and internal read
word while continuing to suppress ordinary RAM writes. A registered
classification stage in `tms34010_memory_fabric` holds every architectural
CPU request, sends external fields through the sequencer, and sends processor
I/O directly to the arbiter as `LOCAL_CYCLE_IO_READ/WRITE`. The internal read
word is part of the coherent command; IAQ is forced inactive. The I/O owner
observes only the returned completion pulse, preventing held physical cycles
from repeating writes or live-register loads.

Task 0150 completes the host-indirect half of that path. The held host address
is decoded against the same I/O page and has an independent asynchronous read
view into the shared register owner. When the host wins arbitration, the
arbiter snapshots that live word and selects `LOCAL_CYCLE_IO_READ/WRITE`;
the existing MCP and phase engine return it through HSTDATA. Host-indirect
writes reach ordinary and live registers only on the returned acknowledge.
Indirect HSTCTLL writes retain host-side ownership, and an independent
HSTADR/HSTDATA port prevents either client from stealing the other's read
selector.

Task 0151 closes physical HOLD release around the integrated path. The local
phase engine samples active-low HOLD at each end-Q1 boundary; a dedicated
2FF level synchronizer carries that request to the existing highest-priority
arbiter, and a second one returns its quiescent grant. The engine first emits
active-low HOLDA during Q3/Q4, releases LAD plus RAS/LAL/CAS/W/TR/QE at the
following Q2, and releases DEN/DDOUT at Q3. It retains those output enables
inactive until an end-Q1 release sample, then reacquires the same groups at
Q2 and Q3. Commands cannot start while held, and an active physical cycle
still completes before grant. That task deliberately left the actual shared
HLDA/EMUA pin mux as a separate wrapper boundary.

Task 0152 closes that final shared-pin boundary. Physical RUN/EMU first passes
through a reset-to-RUN 2FF synchronizer before the core samples it. Every EMU
execute pulse sets a held source request; `tms34010_emu_bridge` acknowledges
it only after an exact Q1/Q2 destination pulse has completed. The registered
halt level crosses separately and is latched only on Q4B-to-Q1A, preventing a
partial EMUA window. LCLK1 high selects that EMUA result, while LCLK1 low
selects Task 0151's HLDA component. Simultaneous halt and HOLD therefore drive
the shared pin low in both halves for their independent reasons.

Task 0153 closes the physical host-register boundary. A legal access is HCS
active with exactly one active direction and at least one active byte strobe.
The bridge lowers HRDY immediately, waits for a synchronized access level,
then captures HFS, direction, byte enables, and HD as one bundled request for
the existing core-clock engine. Read data is registered before HRDY rises and
only selected byte lanes receive output-enable intent. A completed current
access keeps ready even when it launches an indirect side effect; that busy
state waits the following access. HCS plus stable HFS also starts the
mandatory HSTCTL delay before the remaining strobes arrive.

Task 0154 closes the ordinary register-storage audit. CONTROL bits 1:0,
DPYCTL bit 1, and DPYTAP bits 15:14 now use shared package masks on either
completed requester path. Reserved indices 17h–1Ah are explicit non-storage:
writes do nothing and both read views return zero, including the PMASK
compatibility word called out by the guide. Defined fields are unchanged;
REFCNT's previously documented A0033 reserved-bit retention remains isolated.
At that checkpoint SRT remained for the video/display gate; Task 0158 now
consumes it. CD/CF have no cache consumer in the current cacheless
implementation.

Task 0155 closes the provisional core/VCLK boundary from A0034.
`tms34010_video_subsystem` now owns all counters, timing compares, DPYADR, and
screen scheduling in `vclk_i`. Two packed source-held mailboxes carry atomic
configuration and coalesced live-register commands into VCLK; a continuously
re-armed packed mailbox returns coherent, bounded-stale HCOUNT/VCOUNT/DPYADR
snapshots. A sticky DIP event mailbox and a separate bundled screen
transaction return interrupt and completed memory service without sampling
changing multi-bit buses. `tb_video_cdc` verifies the full crossing set under
unrelated clocks.

Task 0156 completes internally generated interlace. NIL selects the existing
noninterlaced sequence or a two-field sequence that resets VCOUNT halfway
through the last even-field line without resetting HCOUNT. The odd-field
VESYNC half-line compare performs the separately documented VCOUNT increment,
so VSYNC ends at the shifted phase and `DPYINT=VESYNC` does not duplicate the
even-field event when HSBLNK is the half-line point. The odd field returns to
the even field at the ordinary full-line VTOTAL boundary. That field phase
feeds the display-address owner directly in VCLK: the DPYSTRT reload preceding
an even field applies signed DUDATE/2, while the reload preceding an odd field
is unchanged and completed scan-line transfers still use full DUDATE.

Task 0157 completes external synchronization. DPYCTL.DXV selects the internal
generator or active-low external sync recognition, and HSD retains internally
generated horizontal timing/output while VSYNC remains external. Each raw
sync input passes through its own attributed two-flop synchronizer and an
edge-history stage; a falling active-low input is therefore acted upon on the
third project update edge, representing the guide's rising-edge sample plus
2.5-VCLK falling-edge clear. External HSYNC or the HTOTAL fallback begins a
line, while external VSYNC or the VTOTAL fallback begins a field. NIL=0
classifies an external field from the pre-clear HCOUNT window; NIL=1 forces
the noninterlaced even phase. Explicit HSYNC/VSYNC output enables now reach
the pin-system boundary.

Task 0158 completes DPYCTL.SRT and corrects the final video scope. The core
tags only graphics pixel requests from PIXT, DRAV, LINE, FILL, and PIXBLT.
The registered fabric preserves that tag through field-to-word sequencing;
the arbiter converts reads to `LOCAL_CYCLE_PIXEL_MTR` and writes to
`LOCAL_CYCLE_PIXEL_RTM`. The physical engine retains the ordinary address,
forces IAQ inactive and TR column status active, holds TR/QE at RAS fall, and
uses low W at RAS fall only for RTM. Neither cycle exchanges CPU data during
the access period; an MTR pixel-load result is deterministic zero under
A0048. Direct replace modes bypass an unnecessary destination read, while
PPOP, transparency, PMASK, and applicable windows keep the read path.
The processor has sync/blank and VRAM-control pins but no pixel-data output;
the external VRAM serial port is the pixel source.

The audit also consolidated the I/O, interrupt-source,
physical-memory, host, refresh, video, CDC, and Quartus work into seven
ordered exit gates. The authoritative remaining-work ledger is
`completion_audit.md`; this architecture document describes the current
structure rather than claiming project completion.

## Datapath strategy

- **Width**: TMS34010 is a 32-bit architecture with a 16-bit external
  multiplexed bus. Internally, ALU is 32 bits; external bus is 16 bits and
  cycles are multiphase. Field-to-word splitting, the original-pin phase
  engine, and the coherent clock-domain bridge between them are implemented.
- **Pipelining**: initial implementation is multi-cycle FSM, not pipelined.
  This keeps the first ISA implementation reviewable. Pipelining is a
  Phase 10 candidate.
- **Bit-addressed PC**: the TMS34010 PC addresses bits, not bytes or words.
  This is the central architectural quirk. Address handling is captured in
  `docs/memory_map.md`.

## Control structure

The top-level FSM began with the sequence below and now includes immediate
fetch, divide, memory, interrupt-entry, and graphics-engine substates. The
authoritative state enum is `core_state_t` in `rtl/tms34010_pkg.sv`.

```
CORE_RESET  ──▶ CORE_FETCH          (after level-0 vector read/PC load)
           └─▶ CORE_RESET_HALT      (HCS high; host clears HLT to continue)
CORE_FETCH  ──▶ CORE_DECODE         (when mem returns instruction word)
CORE_DECODE ──▶ CORE_EXECUTE
            └─▶ CORE_INT_PUSH_PC    (illegal opcode; vector 30)
CORE_EXECUTE──▶ CORE_MEMORY         (if instruction touches memory)
            └─▶ CORE_WRITEBACK      (otherwise)
            └─▶ CORE_EMU_HALT       (EMU samples RUN/EMU low)
CORE_EMU_HALT ─▶ CORE_FETCH         (RUN returns high)
CORE_HOST_HALT ─▶ CORE_FETCH        (host/processor clears HSTCTL.HLT)
CORE_MEMORY ──▶ CORE_WRITEBACK
CORE_WRITEBACK ─▶ CORE_FETCH
```

Multicycle graphics operations are FSM branches invoked from `CORE_EXECUTE`
and return to writeback only when their memory loops and architectural
writebacks complete.

**Architectural reset** (Tasks 0121 and 0142): while `rst` is active,
`CORE_RESET` keeps
the memory request inactive. After release it holds a 32-bit read at
`RESET_VECTOR_ADDR = 0xFFFF_FFE0` until `mem_ack`, loads PC from the returned
level-0 vector, and enters `CORE_FETCH`. This is the same vector word used by
TRAP 0; reset performs no PC/ST push and does not touch SP. When HCS is high
during reset, HSTCTL.HLT resets to one and `CORE_RESET_HALT` defers that
vector request until a direct host high-byte write clears HLT. The eight
post-reset RAS-only cycles are emitted by the integrated 8× physical
controller before that pending vector request can reach LAD.

**Maskable-interrupt entry** (Task 0100): `tms34010_int_ctrl` is instantiated
in the core; `int_req` (ST.IE=1 and an enabled INTPEND bit set, via the
INTENB/INTPEND taps on `tms34010_io_regs`) is sampled at `CORE_FETCH`. If
asserted, the core does not fetch — it runs a four-state entry sequence:

```
CORE_FETCH (int_req) ─▶ CORE_INT_PUSH_PC  (mem[SP-32] ← PC)
                     ─▶ CORE_INT_PUSH_ST  (mem[SP-64] ← ST)
                     ─▶ CORE_INT_VECTOR   (PC ← mem[vector])
                     ─▶ CORE_INT_DONE     (SP -= 64; ST ← 0x10) ─▶ CORE_FETCH
```

The push order (PC high, ST low) matches RETI's pop, so interrupt+RETI
round-trips. Task 0123 resolved A0030 against the page 8-6 ST diagram: live
ST is initialized to `ST_RESET_VALUE` for the service context, while the
exact pre-entry word remains stacked for RETI.

**EMU handshake** (Task 0128): fixed opcode `0x0100` drives `emua_n_o` low
during `CORE_EXECUTE` and samples `run_emu_n_i`. A high RUN sample retires as
a side-effect-free NOP. A low EMU sample enters `CORE_EMU_HALT`, holds EMUA
low, and issues no instruction or memory request; PC already names the
following instruction. Returning RUN high resumes at `CORE_FETCH`. This is an
abstract single-clock core boundary. Task 0152 preserves that core contract
while adding physical RUN/EMU synchronization, lossless event transfer, exact
Q1/Q2 EMUA phasing, and the shared Q3/Q4 HLDA mux (A0032/A0042).

**Illegal-opcode entry** (Task 0122): encodings in the reserved ranges from
User's Guide Table 8-6 never reach execute. From `CORE_DECODE`, they enter the
same push/vector states with an unmaskable request fixed at vector 30
(`0xFFFF_FC20`). Because opcode fetch already advanced PC, the stacked PC is
the following word, matching TRAP 30. The old ST is stacked, SP decreases by
64 bits, and live ST becomes `ST_RESET_VALUE`. The broader
`illegal_opcode_o` decoder-miss diagnostic remains sticky until reset while
valid-but-unimplemented encodings retain their existing placeholder path.

**NMI** (Task 0103): a nonmaskable interrupt (host sets HSTCTLH.NMI) is sampled
at the same `CORE_FETCH` boundary with priority over maskable requests and
*ignores* ST.IE. It vectors through trap 8 (0xFFFFFEE0). HSTCTLH.NMIM picks the
mode: NMIM=0 takes the full push path above; NMIM=1 jumps straight to
`CORE_INT_VECTOR` (no push and no SP update), but still initializes live ST
to `ST_RESET_VALUE` at `CORE_INT_DONE`. The device auto-clears HSTCTLH.NMI on
entry (a one-cycle `nmi_clear` into `tms34010_io_regs`) — mandatory, since a
non-maskable request would otherwise re-fire every cycle.

**Maskable pending sources** (Tasks 0137 and 0139): raw active-low
LINT1/LINT2 inputs
pass through independent two-flop synchronizers and appear as read-only,
level-sensitive INTPEND.X1P/X2P. HSTCTLL.INTIN appears as read-only HIP.
The direct host HSTCTL low-byte write sets INTIN; `dpyint_set_i` remains as a
supplemental integration/test sideband, while the integrated timing
compare now sets DIP directly at start-of-HBLANK. Both requests remain until
software clears INTIN or writes zero to DIP; the graphics window path
similarly latches WVP. INTENB retains only its five architected enable bits.
The existing priority encoder implements
HI > DI > WV > INT1 > INT2, and direct tests cover both external vectors.

## Memory interface

The core exposes one request/ack interface for instruction fetches, data
accesses, and graphics transactions. I/O addresses are decoded on-chip, but
the core still emits an external cycle and uses its ack (A0028).

| Signal     | Dir   | Width | Purpose                                |
|------------|-------|-------|----------------------------------------|
| `mem_req`  | out   | 1     | core asserts on a new request          |
| `mem_we`   | out   | 1     | write enable                           |
| `mem_addr` | out   | 32    | bit address (low bits = bit-offset)    |
| `mem_size` | out   | 6     | field size in bits (1–32)              |
| `mem_wdata`| out   | 32    | write data                             |
| `mem_iaq`  | out   | 1     | opcode acquisition; low for immediate/data words |
| `mem_is_io`| out   | 1     | full-address on-chip I/O decode        |
| `mem_io_we`| out   | 1     | original processor write intent        |
| `mem_io_rdata`| out| 16    | on-chip I/O read word for physical-cycle completion |
| `mem_rdata`| in    | 32    | read data, aligned to field            |
| `mem_ack`  | in    | 1     | one-cycle pulse: data valid / write done |

`tms34010_field_sequencer` accepts this core boundary and presents aligned
16-bit `word_req_o`, `word_we_o`, `word_addr_o`, `word_wdata_o`,
`word_rdata_i`, `word_ack_i`, and `word_restart_i` signals. It sequences one/two/three-word
reads, direct full-word writes, and partial-word RMW pairs while holding
payload stable through stalls. `word_rmw_lock_o` identifies the indivisible
interval required by §11.3.

`tms34010_bus_arbiter` implements the specified fixed order: external HOLD,
screen refresh, DRAM refresh, host indirect, then CPU/graphics. Its registered
owner keeps an issued cycle active through controller acknowledge. A CPU RMW
reservation forces the matching write ahead of other ordinary clients; only
HOLD can break the pair, in which case `word_restart_i` suppresses the
not-yet-issued write and repeats the read. The arbiter exposes an abstract
cycle kind and payload. `tms34010_local_bus_bridge` transfers that held shape
and its response coherently between clocks; `tms34010_local_bus` then converts
it into RAS/CAS/LAL/DEN/DDOUT/W phases and samples LRDY.

`tms34010_memory_fabric` composes those two modules and adds one registered
CPU request-classification stage without a second scheduling policy.
External CPU fields enter the sequencer; processor on-chip I/O
bypasses it and selects the dedicated cycle kinds. The already-word-aligned
host client enters arbitration directly; its full address selects the same
I/O cycle kinds and its internal read word is sampled on grant.
`tms34010_system` wires the core's four landed clients to that fabric, so a
functional integration can no longer bypass arbitration with separate CPU,
host, display, or refresh memories.

The host client additionally carries `host_mem_is_io_o` and
`host_mem_io_rdata_o` from the shared I/O owner. Its address, direction, and
write data remain held by `tms34010_host_if`; the arbiter registers the only
potentially live field—the internal I/O read word—when the host owner is
selected. The returned host acknowledge is therefore the single write-commit
event and the HSTDATA-prefetch completion.

## Graphics subsystem

PIXT, PIXBLT, FILL, DRAV, and LINE are implemented as hardware datapaths and
FSM branches with explicit:

- pixel-address generator (bit-addressed)
- plane mask + transparency stage
- window-clip stage
- memory-request issuer

These engines currently share implementation inside `tms34010_core`.
Extraction into dedicated modules is optional refactoring and must not precede
functional or synthesis evidence that justifies it.

## Host interface (physical wrapper integrated)

The TMS34010 exposes HSTCTL, HSTDATA, and HSTADRH/L to a host CPU for control
and shared-memory access. The core's synchronous completed-cycle boundary
selects any of those four 16-bit registers, carries two byte enables, and
returns acknowledge, read data, busy, and active-low HINT. The host owns
MSGIN, sets INTIN, and clears INTOUT; the processor owns MSGOUT, clears INTIN,
and sets INTOUT. Both can write the seven defined HSTCTLH fields. HCS
initializes HLT, and separate reset/run-time halt states preserve the correct
resume point.

`tms34010_host_if` is instantiated in `tms34010_io_regs` and supplies the
synchronous HSTADRL/HSTADRH/HSTDATA engine described in §10.3.3. It forces
word alignment, buffers prefetched data, implements both LBL byte completion
orders, applies INCR before reads and INCW after acknowledged writes, and
holds its local-word request during backpressure. Processor-side accesses
share the stored values but have no indirect side effects. HSTCTL transactions
pass through to the I/O block's Task 0142 owner.

The aligned 16-bit host client leaves standalone `tms34010_core` and is
connected to the shared fabric by `tms34010_system`.
`tms34010_host_bus` surrounds that synchronous boundary in
`tms34010_pin_system`: active-low HCS/HREAD/HWRITE/HLDS/HUDS and HFS form a
held asynchronous access, HRDY waits for coherent capture/response or an
older indirect side effect, and read data drives only the selected HD byte
lanes after completion. HSTCTL selection starts its wait from HCS alone.
The FPGA top must still instantiate physical bidirectional I/O buffers and
prove the bundled-data/strobe constraints recorded in A0043. CF is stored but
has no cache to flush.

## Video / display (timing integrated)

`tms34010_video` consumes the Chapter 6 timing registers and owns live,
processor-writable HCOUNT/VCOUNT plus the field phase. It produces
active-high HSYNC/VSYNC and horizontal/vertical/combined blank intervals. In
internal mode, sync and the leading blank interval remain active through
their programmed end values, while trailing blank begins after
HSBLNK/VSBLNK; this represents the specified one-VCLK equality-to-pin delay.
NIL=0 starts odd fields at HTOTAL/2, performs the odd VESYNC midline VCOUNT
step, and returns to even fields at the full-line VTOTAL event.

With DXV clear, raw active-low HSYNC/VSYNC inputs pass through separate
attributed two-flop VCLK synchronizers and edge history. The recognized
falling edge clears the corresponding counter on the third project update
edge, matching the guide's 2.5-VCLK recognition delay. External HSYNC starts
a line unless HSD selects internally generated horizontal timing; HTOTAL is
the missing-HSYNC fallback. External VSYNC clears VCOUNT independently, with
VTOTAL plus line start as the missing-VSYNC fallback. In external interlace,
the pre-clear HCOUNT window `HEBLNK < HCOUNT <= HSBLNK` selects an odd next
field; all other phases are even, and NIL=1 forces noninterlaced operation.
DXV/HSD also drive explicit HSYNC/VSYNC output enables; the functional sync
signals remain active-high intervals so a future FPGA top can implement the
physical active-low bidirectional pins.

DPYCTL.ENV=0 forces combined blank and inhibits new display interrupts; when
enabled, the DPYINT line compare sets INTPEND.DIP at `HCOUNT=HSBLNK`, except
for the specified odd-field VESYNC collision. The outputs and direction
controls are visible at the core and pin-system boundaries.

`tms34010_display_addr` consumes the start-HBLANK event and owns live DPYADR.
SRFADR reloads at the beginning of vertical blanking, LNCNT reloads before
the first active line, and SRE schedules a held screen-refresh request every
LCSTRT+1 active lines. In interlace, the reload preceding the even field adds
or subtracts DUDATE/2; the one preceding the odd field uses DPYSTRT unchanged.
The request captures SRFADR/DPYTAP (with DPYTAP reserved bits forced zero) and
remains stable until the memory controller acknowledges a completed VRAM
memory-to-register cycle. Only that acknowledge applies full DUDATE/ORG and
reloads LNCNT.

`tms34010_video_subsystem` clocks both blocks from independent `vclk_i`.
Configuration arrives atomically; counter/address writes are coalesced
commands; processor and host reads use a coherent bounded-stale triple rather
than independently synchronized binary bits. DIP crosses as a held event.
The screen request crosses with its captured payload and remains held in the
core until physical completion returns to VCLK. Raw external sync pins are
the exception to the core/VCLK mailboxes: each is independently synchronized
as a one-bit VCLK level before edge recognition. A0045 records the internal
active-edge representation, common synchronous-reset contract, and behavior
when VCLK is stopped; A0047 records the external-sync timing and direction
contract. A0048 records the separate core-clock SRT transfer and
attached-VRAM boundary.

Timing generation, synchronization, scheduled screen MTR, and
program-controlled graphics MTR/RTM are functionally and physically
implemented at the TMS34010 pin boundary. Attached VRAM owns its
shift-register storage and pixel output.
`tms34010_refresh` is integrated with REFCNT and its request is serviced
through the pin system; final FPGA integration must still prove its bounded
service under the PLL ratio, physical HOLD, and external waits.

## Clock / reset strategy

- One core clock, a dedicated 8× local-bus timing clock, and independent
  VCLK. All sequential logic is positive-edge; LCLK1/LCLK2 are decoded
  outputs, never fabric clocks. The VCLK active edge represents the original
  falling-edge update phase until the FPGA top maps its physical phase.
- Active-high synchronous reset (`rst`) is sampled in all three domains.
  Reset state and each bridge's common-toggle reset contract are documented
  per module and in `assumptions.md`.
- Every clock-domain crossing is wrapped in a clearly named CDC module and
  flagged in `docs/timing_notes.md`; raw HSYNC/VSYNC use individual
  attributed two-flop VCLK synchronizers.

## FPGA resource strategy

- Future architecturally-sized memories should use `rtl/fpga/bram_*.sv`
  wrappers so inference stays localized. Those wrappers do not exist yet.
- Avoid wide muxes where a small FSM can sequence the choice across
  cycles instead.
- No vendor-locked primitives in core RTL. Cyclone V-specific primitives
  live only under `rtl/fpga/` and are wrapped.

## Current implementation gaps

- Optional instruction cache.
- Real Quartus project files, SDC, synthesis/fit/timing reports, and measured
  Cyclone V resource/Fmax results.
- A cycle-accuracy contract against original silicon.

The instruction/status reconciliation and TMS34010 functional interface are
complete. Remaining completion work is FPGA realization and measured
memory/video/CDC timing evidence recorded in `completion_audit.md`.
