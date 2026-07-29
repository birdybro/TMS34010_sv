# Timing notes

> Status: **functional latency notes only**. RTL is implemented through Task
> 0142, but no real Quartus project, SDC, fit, or TimeQuest report exists yet.
> Every path/resource assessment below is therefore a watch item, not measured
> Cyclone V evidence.

## Known long paths (planned watchlist)

| Path                                | Phase introduced | Status   | Mitigation if needed |
|-------------------------------------|------------------|----------|----------------------|
| Decode → ALU operand mux            | 3                | landed, unmeasured | pipeline decode/execute boundary if Fmax suffers |
| Bit-addressed field/XY address logic| 5 / 7            | landed in core, unmeasured | register conversion/extract paths if combinational logic is too wide |
| PIXBLT/FILL/LINE pixel pipeline     | 7                | landed, multicycle, unmeasured | keep memory hand-offs registered; split core control if fanout dominates |
| Wide barrel shifter / field masks   | 2 / 5            | landed, unmeasured | stage only with synthesis evidence and full latency regression |
| Field-window shift/mask and word merge | Task 0136      | landed, sequenced, unmeasured | preserve the registered word boundary; pipeline only if TimeQuest identifies this path |
| SLA sign-difference reduction       | Task 0130         | landed, unmeasured | reduction follows the barrel shift amount; register only if TimeQuest identifies it |
| MPYS/MPYU 32×32 multiply (`mpy_product`) | 3 (Task 0071) | watch | Operands are regfile-registered and the product is registered into `mpy_product_q` (1 EXECUTE cycle), so it should map to Cyclone V variable-precision DSP (≈3–4 DSP blocks for 32×32→64). If the combinational 32×32 multiply fails Fmax, pipeline it into 2+ stages and stretch the multiply latency (cycle count is internal to EXECUTE/WRITEBACK — not externally observable for a register op). |

## Multi-cycle operations

- **Architectural reset** — after `rst` releases, `CORE_RESET` holds one
  32-bit read request at `0xFFFF_FFE0` until `mem_ack`. PC loads on that
  acknowledge and the next state is `CORE_FETCH`; there is no stack or data
  write. The field sequencer expands that abstract request into two ascending
  16-bit word reads and holds each request through `word_ack_i`. The eight
  original-silicon RAS-only initialization cycles still precede this
  transaction in the future pin-level memory controller.
- **Host-present reset halt** — if HCS is high during reset,
  HSTCTLH.HLT resets to one and `CORE_RESET_HALT` issues no vector or
  instruction request. A synchronous direct-host high-byte write clearing
  HLT returns through `CORE_RESET` and begins the level-0 vector transaction.
- **Run-time HLT** — HSTCTLH.HLT is observed at `CORE_FETCH`, after the
  current instruction finishes. `CORE_HOST_HALT` issues no processor memory
  transaction and accepts no interrupt until HLT clears. Refresh, video, and
  screen scheduling remain independently clocked. A newly simultaneous NMI
  takes priority long enough to complete entry; HLT then stops the first ISR
  fetch. A host write completing on the same edge as an already-acknowledged
  instruction fetch can take effect at the following boundary, matching the
  direct synchronous transaction abstraction rather than claiming pin phase.
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
- **DRAM-refresh request** — REFCNT resets to zero while CONTROL.RR resets to
  `00`. The first active core/local clock subtracts two from RINTVL, borrows
  into ROWADR (`0 → 255`), and registers `refresh_req_o` for one clock with
  `refresh_row_o=255`. Further RR=00 requests are 32 clocks apart; RR=01
  requests are 64 clocks apart. During each request pulse, the row is the
  newly decremented value and `refresh_cbr_o` reflects CONTROL.RM. The future
  arbiter must capture or retain this event until it performs the physical
  cycle; no service/acknowledge path exists yet.
- **Integrated video timing** — Task 0139 runs the internal/noninterlaced
  generator on the project `clk` under A0034. HCOUNT advances each positive
  edge and wraps after HTOTAL; that wrap advances VCOUNT and wraps it after
  VTOTAL. Processor counter loads take same-edge priority. The display event
  is combinational for the `HCOUNT=HSBLNK && VCOUNT=DPYINT && ENV` interval
  and is sampled into the DIP latch on the following clock edge. Sync/end
  blank equality remains active for that count; start blank equality remains
  inactive until the following count. These are functional clock
  relationships, not the original falling-VCLK pin phase.
- **Screen-refresh request** — at an eligible start-HBLANK event,
  `screen_refresh_req_o` registers high and captures SRFADR/DPYTAP. The level
  and payload remain stable for an unbounded number of core clocks until
  `screen_refresh_ack_i` reports completion of the future physical VRAM
  transfer. That acknowledge clears the request, reloads LNCNT, and updates
  SRFADR by the live DUDATE/ORG value. Processor DPYADR load wins a same-edge
  automatic update. The future arbiter must not acknowledge selection alone;
  acknowledge denotes completed memory-to-register service.
- **MOVE *Rs(offset),*Rd+** — opcode and signed-offset fetch are followed by
  two acknowledged FS-bit transactions in one `CORE_MEMORY` stay: source
  read, then destination write. `move_data_q` bridges the transactions; the
  destination pointer advances in `CORE_WRITEBACK`. Each abstract field
  transaction is expanded by `tms34010_field_sequencer` into the §4.1
  minimum aligned-word sequence and can stall independently on each
  `word_ack_i`.
- **MOVE @SAddress,*Rd+** — opcode and two source-address fetches are
  followed by the same two acknowledged FS-bit source-read/destination-write
  transactions and destination writeback. Absolute-address fetch order is
  low word then high word.
- **Physical field sequencing** — one accepted 1–32-bit request remains
  active internally until all required ascending 16-bit word operations have
  completed. Minimum physical-word counts are:

  | §4.1 case | Read words | Write words |
  |-----------|------------|-------------|
  | A         | 1          | 1 direct    |
  | B         | 1          | 2 (read/modify/write) |
  | C         | 2          | 2 (partial RMW + direct) |
  | D         | 2          | 3 (partial RMW + direct) |
  | E         | 2          | 3 (direct + partial RMW) |
  | F         | 2          | 4 (two partial RMW pairs) |
  | G         | 3          | 5 (partial RMW + direct + partial RMW) |

  Controller select/response states are implementation latency, not claimed
  original-pin phases. Each asserted word request and its payload remain
  stable until acknowledge. `word_rmw_lock_o` is asserted from a partial-word
  read through the matching write acknowledge; §11.3 permits arbitration
  between different words of a multiword field, so the lock does not span
  the complete field.
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

## Interrupt input CDC

LINT1 and LINT2 are raw asynchronous active-low level inputs. Each passes
through its own `tms34010_sync_bit` instance: two core-clock flops with no
combinational logic between them and Quartus `PRESERVE`,
`SYNCHRONIZER_IDENTIFICATION`, and `useioff=0` attributes. Reset initializes
both synchronized levels inactive-high. The core therefore observes a pin
transition after two core-clock sampling edges; this is the FPGA abstraction
of the guide's one-to-two-state synchronization delay.

The future SDC must mark the pin-to-first-stage paths asynchronous and the
Quartus metastability report must recognize both chains. Those checks cannot
be claimed until the real project exists. The direct `host_ctl_*` interface
and supplemental `dpyint_set_i` are currently synchronous core-clock
transactions/events. The future asynchronous host pin wrapper must transfer
each completed control write coherently and return stable read data/HINT
under its HRDY protocol. The integrated Task 0139 display compare is
same-clock and therefore needs no crossing yet. When it moves to VCLK, DIP
delivery must use a lossless event handshake or equivalent pending-level
protocol, timing configuration must use a coherent multi-bit transfer, and
free-running counter observation must not synchronize binary bits
independently.

## Provisional video clock boundary

Task 0139 intentionally closes functional register/timing integration before
introducing the physical video clock. The current active-high timing interval
outputs are core-clock signals. A future VCLK task must:

- place HCOUNT/VCOUNT and timing compares in the VCLK domain;
- transfer processor-written timing configurations coherently, with explicit
  update acknowledgement where required;
- provide reliable processor access to live counters without independently
  synchronizing binary bits;
- transfer DPYSTRT/DPYCTL/DPYTAP updates and live DPYADR ownership coherently
  with the screen-refresh scheduler;
- carry display-interrupt events into the core domain without losing a
  one-VCLK pulse;
- constrain both clocks and every crossing in SDC, then verify Quartus CDC
  recognition and metastability reports.

## Cyclone V-specific notes

To be filled in once `scripts/synth_quartus.sh` produces real reports.
Anticipated items: M10K inference style, DSP usage for the shifter,
clock network choice (regional vs. global) for the core clock.
