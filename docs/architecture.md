# Architecture

> Status: **implemented through Task 0126; audited through Task 0124, with
> integration gaps**. The core executes the instruction and graphics
> operations tracked in `instruction_coverage.md`; reset-vector fetch, I/O
> registers, and interrupt entry are integrated. Video timing and refresh
> exist as standalone modules. The remaining ISA discrepancies and all
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
                              tms34010_core
        ┌──────────────────────────────────────────────────────┐
        │                                                      │
clk ───▶│  ┌─────────┐    ┌──────────┐    ┌─────────┐          │
rst ───▶│  │  PC     │───▶│  Fetch   │───▶│ Decode  │          │
        │  └─────────┘    └──────────┘    └────┬────┘          │
        │       ▲                              │               │
        │       │                              ▼               │
        │  ┌────┴────┐    ┌──────────┐    ┌─────────┐          │
        │  │  Flags  │◀───│  ALU /   │◀───│ Control │          │
        │  │   (ST)  │    │ Shifter  │    │  FSM    │          │
        │  └─────────┘    └──────────┘    └────┬────┘          │
        │                       ▲              │               │
        │                       │              ▼               │
        │                  ┌────┴────┐    ┌─────────┐          │
        │                  │ Regfile │◀──▶│ Mem IF  │──┐       │
        │                  │ (A,B,SP)│    └─────────┘  │       │
        │                  └─────────┘                 │       │
        └─────────────────────────────────────────────│───────┘
                                                       │
                            ┌──────────────────────────┴────┐
                            │   bus_arbiter / cache /        │
                            │   pixel_addr / pixblt / line   │
                            │   host_if / video_timing       │
                            └────────────────────────────────┘
```

The CPU, graphics execution engines, I/O register storage, and interrupt entry
currently live in or directly under `tms34010_core`. The lower memory/host
fabric remains planned; video timing and refresh are standalone blocks awaiting
integration.

## Test substrate

For tests beyond pure FSM-state checks, a behavioral memory model under
`sim/models/sim_memory_model.sv` provides a request/ack-handshake-compliant
16-bit-word store with one-cycle ack latency. It supports arbitrary 1–32-bit
fields at any bit address, including three-word straddles and
read-modify-write preservation. The model is **not RTL**; it exists only to
drive the core interface in simulation. A synthesizable external-memory
fabric/controller has not landed.

## Module map

| Path                                    | Phase | Status      | Notes |
|-----------------------------------------|-------|-------------|-------|
| `rtl/tms34010_pkg.sv`                   | 0+    | **landed** | architectural constants, I/O/interrupt/graphics constants, FSM and decode types |
| `rtl/core/tms34010_core.sv`             | 0+    | **landed through Task 0126** | multicycle CPU, reset/illegal-vector fetch, memory sequencing, I/O routing, interrupts, and graphics engines |
| `rtl/core/tms34010_pc.sv`               | 1     | **landed**  | bit-addressed PC: reset/load/advance, advance amount in bits |
| `rtl/core/tms34010_regfile.sv`          | 2+    | **landed**  | A0–A14, B0–B14, shared SP (A15/B15 alias); 3R/1W; async read |
| `rtl/core/tms34010_alu.sv`              | 2     | **landed**  | combinational ADD/ADDC/SUB/SUBB/CMP/AND/ANDN/OR/XOR/NOT/NEG/PASS_A/PASS_B + N/C/Z/V flags |
| `rtl/core/tms34010_shifter.sv`          | 2     | **landed**  | 32-bit barrel shifter: SLL/SLA/SRL/SRA/RL/RR + N/C/Z flags |
| `rtl/core/tms34010_status_reg.sv`       | 2     | **landed**  | 32-bit ST: selective N/C/Z/V update vs full POPST-style write; named flag outputs |
| `rtl/core/tms34010_decode.sv`           | 3+    | **landed through Task 0126** | combinational decoder; per-instruction flag masks; unsupported encodings route to ILLEGAL |
| `rtl/core/tms34010_control.sv`          | 3     | merged into core.sv | top-level control and graphics FSMs; extraction remains an optimization option |
| `rtl/memory/tms34010_mem_if.sv`         | 1, 6  | not started | request/valid memory interface |
| `rtl/memory/tms34010_cache.sv`          | 6     | not started | optional instruction cache |
| `rtl/memory/tms34010_bus_arbiter.sv`    | 6     | not started | core vs. graphics vs. host arbitration |
| `rtl/graphics/tms34010_pixel_addr.sv`   | 5, 7  | not separate | XY/linear conversion currently resides in the core |
| `rtl/graphics/tms34010_pixblt.sv`       | 7     | not separate | PIXBLT/FILL datapaths and FSM states currently reside in the core |
| `rtl/graphics/tms34010_window.sv`       | 7     | not separate | all four window modes are implemented in the core |
| `rtl/graphics/tms34010_plane_mask.sv`   | 7     | not separate | PPOP, plane mask, and transparency logic currently reside in the core |
| `rtl/graphics/tms34010_line_draw.sv`    | 7     | not separate | LINE and DRAV FSMs currently reside in the core |
| `rtl/host/tms34010_host_if.sv`          | 6     | not started | HSTCTL / HSTDATA / HSTADRH/L |
| `rtl/io/tms34010_io_regs.sv`            | 6     | **landed + wired** | 32×16-bit memory-mapped I/O register file (1988 UG Fig 6-1); plain R/W storage, I/O-space decode + index. Instantiated inside the core (Task 0082): I/O-space accesses are serviced on-chip — external write gated off, read data muxed/latched in. Side-effect/read-only register behaviors deferred (A0028). |
| `rtl/video/tms34010_video.sv`           | 9     | **landed (standalone)** | HSYNC/VSYNC/blanking generator: free-running HCOUNT/VCOUNT off VCLK, wraps at HTOTAL/VTOTAL, sync/blank window compares, DPYINT scan-line strobe. Not yet wired to the I/O register timing values or a pixel clock (Task 0097). |
| `rtl/video/tms34010_refresh.sv`         | 9     | **landed (standalone)** | DRAM-refresh address generator: prescaler off CONTROL.RR (every 32/64 clocks, or disabled), 8-bit REFCNT row counter, one-clock refresh strobe (Task 0099). Not yet wired to the memory arbiter. |
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
tests. Task 0126 closed the signed-offset-source, postincrement-destination
MOVE row; the absolute-source variant and EMU remain. The audit also
consolidated the I/O, interrupt-source,
physical-memory, host, refresh, video, CDC, and Quartus work into seven
ordered exit gates. The authoritative remaining-work ledger is
`completion_audit.md`; this architecture document describes the current
structure rather than claiming project completion.

## Datapath strategy

- **Width**: TMS34010 is a 32-bit architecture with a 16-bit external
  multiplexed bus. Internally, ALU is 32 bits; external bus is 16 bits and
  cycles are multiphase. Exact physical phasing is not implemented; it must be
  taken from the User's Guide bus-cycle chapter and captured in
  `docs/timing_notes.md` when the memory fabric is designed.
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
CORE_FETCH  ──▶ CORE_DECODE         (when mem returns instruction word)
CORE_DECODE ──▶ CORE_EXECUTE
            └─▶ CORE_INT_PUSH_PC    (illegal opcode; vector 30)
CORE_EXECUTE──▶ CORE_MEMORY         (if instruction touches memory)
            └─▶ CORE_WRITEBACK      (otherwise)
CORE_MEMORY ──▶ CORE_WRITEBACK
CORE_WRITEBACK ─▶ CORE_FETCH
```

Multicycle graphics operations are FSM branches invoked from `CORE_EXECUTE`
and return to writeback only when their memory loops and architectural
writebacks complete.

**Architectural reset** (Task 0121): while `rst` is active, `CORE_RESET` keeps
the memory request inactive. After release it holds a 32-bit read at
`RESET_VECTOR_ADDR = 0xFFFF_FFE0` until `mem_ack`, loads PC from the returned
level-0 vector, and enters `CORE_FETCH`. This is the same vector word used by
TRAP 0; reset performs no PC/ST push and does not touch SP. The eight
post-reset RAS-only cycles and HCS-selected host halt are responsibilities of
the future physical memory controller and host interface.

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

## Memory interface

The core exposes one request/ack interface for instruction fetches, data
accesses, and graphics transactions. I/O addresses are decoded on-chip, but
the core still emits an external cycle and uses its ack (A0028). A future bus
arbiter must add host, video, and refresh clients and reproduce the required
priority.

| Signal     | Dir   | Width | Purpose                                |
|------------|-------|-------|----------------------------------------|
| `mem_req`  | out   | 1     | core asserts on a new request          |
| `mem_we`   | out   | 1     | write enable                           |
| `mem_addr` | out   | 32    | bit address (low bits = bit-offset)    |
| `mem_size` | out   | 6     | field size in bits (1–32)              |
| `mem_wdata`| out   | 32    | write data                             |
| `mem_rdata`| in    | 32    | read data, aligned to field            |
| `mem_ack`  | in    | 1     | one-cycle pulse: data valid / write done |

This is the current core interface. Its physical 16-bit bus sequencing,
wait-state behavior, and arbitration remain outside the core.

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

## Host interface (not implemented)

The TMS34010 exposes HSTCTL, HSTDATA, and HSTADRH/L to a host CPU for control
and shared-memory access. The intended first implementation is a synchronous
slave port; signal-level pin compatibility with original silicon is not a
goal.

## Video / display (standalone blocks only)

`tms34010_video` produces counters, sync, blanking, and a display-interrupt
pulse from explicit timing-register inputs. `tms34010_refresh` produces the
refresh row and request cadence. Neither block is connected to the core's I/O
registers, interrupt-pending bits, pixel-memory path, or a memory arbiter.
VRAM shift-register behavior and pixel output are not implemented.

## Clock / reset strategy

- Single core clock (`clk`). All sequential logic is positive-edge.
- Active-high synchronous reset (`rst`). Reset state is documented per
  module.
- Any clock-domain crossings (host interface, video output) are wrapped
  in a clearly-named CDC module and flagged in `docs/timing_notes.md`.

## FPGA resource strategy

- Future architecturally-sized memories should use `rtl/fpga/bram_*.sv`
  wrappers so inference stays localized. Those wrappers do not exist yet.
- Avoid wide muxes where a small FSM can sequence the choice across
  cycles instead.
- No vendor-locked primitives in core RTL. Cyclone V-specific primitives
  live only under `rtl/fpga/` and are wrapped.

## Current implementation gaps

- A synthesizable memory fabric, physical external-bus sequencing, wait-state
  validation, cache, and arbitration among CPU/graphics/host/video/refresh.
- Host interface behavior.
- Full I/O side effects/read-only semantics and internally completed I/O
  accesses.
- Integration of video timing and refresh with I/O registers, interrupts, and
  memory; display fetch and pixel output.
- Real Quartus project files, SDC, synthesis/fit/timing reports, and measured
  Cyclone V resource/Fmax results.
- A cycle-accuracy contract against original silicon.

The instruction table and assumption log contain narrower semantic
uncertainties. Treat them as part of the backlog even when the corresponding
instruction is functionally implemented.
