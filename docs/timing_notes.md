# Timing notes

> Status: **functional latency notes only**. RTL is implemented through Task
> 0128, but no real Quartus project, SDC, fit, or TimeQuest report exists yet.
> Every path/resource assessment below is therefore a watch item, not measured
> Cyclone V evidence.

## Known long paths (planned watchlist)

| Path                                | Phase introduced | Status   | Mitigation if needed |
|-------------------------------------|------------------|----------|----------------------|
| Decode → ALU operand mux            | 3                | landed, unmeasured | pipeline decode/execute boundary if Fmax suffers |
| Bit-addressed field/XY address logic| 5 / 7            | landed in core, unmeasured | register conversion/extract paths if combinational logic is too wide |
| PIXBLT/FILL/LINE pixel pipeline     | 7                | landed, multicycle, unmeasured | keep memory hand-offs registered; split core control if fanout dominates |
| Wide barrel shifter / field masks   | 2 / 5            | landed, unmeasured | stage only with synthesis evidence and full latency regression |
| MPYS/MPYU 32×32 multiply (`mpy_product`) | 3 (Task 0071) | watch | Operands are regfile-registered and the product is registered into `mpy_product_q` (1 EXECUTE cycle), so it should map to Cyclone V variable-precision DSP (≈3–4 DSP blocks for 32×32→64). If the combinational 32×32 multiply fails Fmax, pipeline it into 2+ stages and stretch the multiply latency (cycle count is internal to EXECUTE/WRITEBACK — not externally observable for a register op). |

## Multi-cycle operations

- **Architectural reset** — after `rst` releases, `CORE_RESET` holds one
  32-bit read request at `0xFFFF_FFE0` until `mem_ack`. PC loads on that
  acknowledge and the next state is `CORE_FETCH`; there is no stack or data
  write. The abstract core adds no fixed wait beyond the memory transaction.
  The eight original-silicon RAS-only initialization cycles precede this
  transaction in the future physical memory controller.
- **Illegal opcode entry** — detection in `CORE_DECODE` bypasses execute and
  issues three acknowledged 32-bit transactions through the shared interrupt
  states: push PC, push ST, then read vector 30. A final `CORE_INT_DONE` cycle
  updates SP/ST/PC before handler fetch. ST.IE and INTENB do not gate entry.
- **Interrupt completion** — `CORE_INT_DONE` initializes live ST and loads PC
  in one internal cycle. Context-saving entries also decrement SP there;
  NMIM=1 NMI omits the SP write but retains the ST/PC updates.
- **EMU** — `CORE_EXECUTE` drives active-low EMUA for one core cycle while
  sampling RUN/EMU. RUN proceeds through ordinary writeback as a NOP. EMU
  enters `CORE_EMU_HALT`, holds EMUA low, issues no memory request, and stays
  halted for an unbounded number of core cycles until RUN returns high.
  Original Q1/Q2 pulse phasing and HLDA/EMUA pin multiplexing are deferred to
  the physical wrapper (A0032).
- **MOVE *Rs(offset),*Rd+** — opcode and signed-offset fetch are followed by
  two acknowledged FS-bit transactions in one `CORE_MEMORY` stay: source
  read, then destination write. `move_data_q` bridges the transactions; the
  destination pointer advances in `CORE_WRITEBACK`. The abstract interface
  treats an unaligned/straddling field as one transaction, while the future
  physical 16-bit controller must expand it into the specification-derived
  bus phases.
- **MOVE @SAddress,*Rd+** — opcode and two source-address fetches are
  followed by the same two acknowledged FS-bit source-read/destination-write
  transactions and destination writeback. Absolute-address fetch order is
  low word then high word.
- **DIVU/DIVS/MODU/MODS** — `tms34010_divider` (restoring
  long division). Start: the `CORE_EXECUTE → CORE_DIVIDE` edge (one-cycle
  `div_start`). Internal states: 1 (latch) + 32 (iterate) + 1 (done); on
  overflow it short-circuits to done in 2 cycles. No memory transactions.
  Done: level-high `done` in the result cycle; the core leaves CORE_DIVIDE
  for WRITEBACK on it. Not interruptible; interrupt requests are sampled only
  at `CORE_FETCH` instruction boundaries. The
  restoring step (33-bit compare/subtract) is the per-iteration critical
  path — short, but pipeline the compare if a wider divisor path ever
  appears.

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

- Single core clock; target Fmax is **not** set yet. Initial sanity target:
  clear 50 MHz on the documented Cyclone V `5CSEBA6U23I7`, then set the real
  target from system requirements and measured reports.
- Avoid combinational paths longer than ~10 LUT levels. If a path goes
  longer, register it or note the exception here.
- All clock-domain crossings (host interface, video) must be wrapped in
  a CDC primitive (Phase 6 / Phase 9). Listed here when they land.

## Cyclone V-specific notes

To be filled in once `scripts/synth_quartus.sh` produces real reports.
Anticipated items: M10K inference style, DSP usage for the shifter,
clock network choice (regional vs. global) for the core clock.
