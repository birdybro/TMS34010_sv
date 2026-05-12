# Architecture

> Status: **scaffold**. Nothing in the RTL/ directory is implemented yet beyond
> a top-level skeleton. This file is the design intent. Each section is marked
> with implementation status. As modules land, the corresponding section is
> expanded with concrete signal lists, FSM tables, and timing diagrams.

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

## Top-level block diagram (planned)

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

Solid blocks belong to Phase 1–2. Dashed (lower) blocks are Phase 3–9.

## Module map (planned)

| Path                                    | Phase | Status      | Notes |
|-----------------------------------------|-------|-------------|-------|
| `rtl/tms34010_pkg.sv`                   | 0     | skeleton    | widths, basic typedefs; expanded each phase |
| `rtl/core/tms34010_core.sv`             | 0–1   | skeleton    | top-level wrapper; FSM scaffold; mem-IF stub |
| `rtl/core/tms34010_pc.sv`               | 1     | not started | byte/bit-addressed PC register |
| `rtl/core/tms34010_regfile.sv`          | 2     | not started | A0–A14, B0–B14, SP, ST, PC |
| `rtl/core/tms34010_alu.sv`              | 2     | not started | add/sub/log/cmp; flag generation |
| `rtl/core/tms34010_shifter.sv`          | 2     | not started | barrel shifter; field-extract helpers |
| `rtl/core/tms34010_flags.sv`            | 2     | not started | status-register flag update logic |
| `rtl/core/tms34010_decode.sv`           | 3     | not started | opcode + operand decode |
| `rtl/core/tms34010_control.sv`          | 3     | not started | top-level control FSM |
| `rtl/memory/tms34010_mem_if.sv`         | 1, 6  | not started | request/valid memory interface |
| `rtl/memory/tms34010_cache.sv`          | 6     | not started | optional instruction cache |
| `rtl/memory/tms34010_bus_arbiter.sv`    | 6     | not started | core vs. graphics vs. host arbitration |
| `rtl/graphics/tms34010_pixel_addr.sv`   | 5, 7  | not started | bit-addressed pixel address generator |
| `rtl/graphics/tms34010_pixblt.sv`       | 7     | not started | block transfer FSM |
| `rtl/graphics/tms34010_window.sv`       | 7     | not started | window clip / hit-test |
| `rtl/graphics/tms34010_plane_mask.sv`   | 7     | not started | plane mask + transparency |
| `rtl/graphics/tms34010_line_draw.sv`    | 7     | not started | Bresenham line FSM |
| `rtl/host/tms34010_host_if.sv`          | 6     | not started | HSTCTL / HSTDATA / HSTADRH/L |
| `rtl/io/tms34010_io_regs.sv`            | 6     | not started | memory-mapped I/O registers |
| `rtl/video/tms34010_video_timing.sv`    | 9     | not started | HSYNC/VSYNC/blanking generator |
| `rtl/video/tms34010_refresh.sv`         | 9     | not started | screen refresh / VRAM shift control |
| `rtl/fpga/bram_1r1w.sv`                 | 1     | not started | Cyclone V BRAM wrapper, 1R1W, sync read |
| `rtl/fpga/bram_rom.sv`                  | 1     | not started | sync-read ROM wrapper |

Every module listed will be added as part of its phase's task series. None
are stubbed silently — if decoded but unimplemented, decode raises an
illegal-opcode trap (Phase 3 onward).

## Datapath strategy (planned, Phase 1–2)

- **Width**: TMS34010 is a 32-bit architecture with a 16-bit external
  multiplexed bus. Internally, ALU is 32 bits; external bus is 16 bits and
  cycles are multi-phase. The exact phasing comes from the 1988 User's
  Guide chapter on bus cycles — captured in `docs/timing_notes.md` once
  Phase 6 starts.
- **Pipelining**: initial implementation is multi-cycle FSM, not pipelined.
  This keeps the first ISA implementation reviewable. Pipelining is a
  Phase 10 candidate.
- **Bit-addressed PC**: the TMS34010 PC addresses bits, not bytes or words.
  This is the central architectural quirk. Address handling is captured in
  `docs/memory_map.md`.

## Control structure (planned)

Top-level FSM (Phase 1 skeleton, expanded in Phase 3):

```
CORE_RESET  ──▶ CORE_FETCH
CORE_FETCH  ──▶ CORE_DECODE         (when mem returns instruction word)
CORE_DECODE ──▶ CORE_EXECUTE
CORE_EXECUTE──▶ CORE_MEMORY         (if instruction touches memory)
            └─▶ CORE_WRITEBACK      (otherwise)
CORE_MEMORY ──▶ CORE_WRITEBACK
CORE_WRITEBACK ─▶ CORE_FETCH
```

Multi-cycle graphics operations are sub-FSMs invoked from `CORE_EXECUTE`
and return to `CORE_WRITEBACK` only when done.

## Memory interface (planned)

A single `request/valid/ready` interface from the core to the external
bus. The on-chip bus arbiter (Phase 6) multiplexes core fetch, core data,
graphics engine, host interface, and video refresh into the same external
bus, in priority order matching the User's Guide.

| Signal     | Dir   | Width | Purpose                                |
|------------|-------|-------|----------------------------------------|
| `mem_req`  | out   | 1     | core asserts on a new request          |
| `mem_we`   | out   | 1     | write enable                           |
| `mem_addr` | out   | 32    | bit address (low bits = bit-offset)    |
| `mem_size` | out   | 6     | field size in bits (1–32)              |
| `mem_wdata`| out   | 32    | write data                             |
| `mem_rdata`| in    | 32    | read data, aligned to field            |
| `mem_ack`  | in    | 1     | one-cycle pulse: data valid / write done |

Concrete signal list is provisional. Updated when `rtl/memory/tms34010_mem_if.sv`
lands in Phase 1.

## Graphics subsystem (planned, Phase 7)

Hardware datapath, not software loop. Each high-level operation (PIXBLT,
FILL, LINE) is its own FSM with explicit:

- pixel-address generator (bit-addressed)
- plane mask + transparency stage
- window-clip stage
- memory-request issuer

Throughput and latency targets are captured in `docs/timing_notes.md`
when the modules land.

## Host interface (planned, Phase 6)

The TMS34010 exposes HSTCTL, HSTDATA, HSTADRH/L registers to a host CPU
for control and shared-memory access. Initial implementation is a
synchronous slave port; signal-level pin-compat with the original device
is **not** a goal — the project is an FPGA core, not a drop-in replacement.

## Video / display (planned, Phase 9)

Video timing is a separate FSM driven by VTIM/HTIM-class registers.
Initial target is producing HSYNC/VSYNC/BLANK + pixel-clock at standard
arcade resolutions. VRAM shift-register cycles (the original device's
TMS34061-style serial output) are reproduced functionally; the exact
DRAM/VRAM electrical interface is not.

## Clock / reset strategy

- Single core clock (`clk`). All sequential logic is positive-edge.
- Active-high synchronous reset (`rst`). Reset state is documented per
  module.
- Any clock-domain crossings (host interface, video output) are wrapped
  in a clearly-named CDC module and flagged in `docs/timing_notes.md`.

## FPGA resource strategy

- All architecturally-sized memories use the `rtl/fpga/bram_*.sv` wrappers
  so the BRAM inference style is in one place and easy to retarget.
- Avoid wide muxes where a small FSM can sequence the choice across
  cycles instead.
- No vendor-locked primitives in core RTL. Cyclone V-specific primitives
  live only under `rtl/fpga/` and are wrapped.

## What is NOT implemented yet

Everything below the FSM scaffold. The current skeleton elaborates and
clears reset; it does not fetch real instructions, has no register file
content, and the memory interface is a stub. This is intentional and
tracked in `tasks.md`.
