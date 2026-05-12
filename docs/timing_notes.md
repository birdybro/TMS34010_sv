# Timing notes

> Status: **scaffold**. Concrete numbers go here as modules land and as
> Quartus timing reports become available.

## Known long paths (planned watchlist)

| Path                                | Phase introduced | Status   | Mitigation if needed |
|-------------------------------------|------------------|----------|----------------------|
| Decode → ALU operand mux            | 3                | planned  | pipeline decode/execute boundary if Fmax suffers |
| Bit-addressed memory IF alignment   | 1 / 6            | planned  | register alignment shifter output if combinational shift is too wide |
| PIXBLT memory pipeline              | 7                | planned  | natively multi-cycle; register every memory hand-off |
| Wide barrel shifter (field extract) | 2                | planned  | DSP block or staged shifter on Cyclone V |

## Multi-cycle operations

To be filled in as instructions/operations land. For each, document:

- Start condition (which FSM state issues the start).
- Internal state count.
- External memory transactions per operation.
- Done signal semantics.
- Whether the operation is interruptible.

## Pipeline boundaries

Initial implementation is **multi-cycle, non-pipelined**. There is one
pipeline boundary: `CORE_FETCH → CORE_DECODE` is a register stage so the
fetched instruction word is stable before decode.

Pipelining is a Phase 10 candidate. Any pipeline introduction must:

- Update this file with the new register/bypass map.
- Re-verify all existing instruction tests.
- Document the hazard policy (stall vs. forward vs. flush).

## RAM latency assumptions

- Cyclone V M10K block RAMs: assume **1-cycle synchronous read** (read
  address registered, read data appears one cycle later).
- All RAM wrappers under `rtl/fpga/bram_*.sv` declare their latency in a
  comment at the top of the file. The rest of the RTL must not assume
  combinational read.

## FPGA timing concerns

- Single core clock; target Fmax is **not** set yet — measured after
  Phase 1 skeleton synthesizes. Initial sanity target: clear 50 MHz on
  Cyclone V 5CGXFC6, then ratchet up.
- Avoid combinational paths longer than ~10 LUT levels. If a path goes
  longer, register it or note the exception here.
- All clock-domain crossings (host interface, video) must be wrapped in
  a CDC primitive (Phase 6 / Phase 9). Listed here when they land.

## Cyclone V-specific notes

To be filled in once `scripts/synth_quartus.sh` produces real reports.
Anticipated items: M10K inference style, DSP usage for the shifter,
clock network choice (regional vs. global) for the core clock.
