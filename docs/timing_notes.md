# Timing notes

> Status: **functional latency notes only**. RTL is implemented through Task
> 0155, but no real Quartus project, SDC, fit, or TimeQuest report exists yet.
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
| 8× local-bus phase/pin decode        | Task 0147        | landed/integrated, unmeasured | keep outputs in the 8× domain/IOE boundary; constrain the PLL clock and every pin delay before FPGA sign-off |
| Core↔8× MCP payload/response paths   | Task 0148        | landed, protocol-protected, unconstrained | declare asynchronous clocks, preserve/recognize toggle synchronizers, and cut/waive only the stable MCP payload paths |
| CPU request classification → field/I/O select | Task 0149 | one registered stage, unmeasured | retain the registered loop break; inspect fanout only if TimeQuest identifies it |
| Host I/O read mux → grant snapshot      | Task 0150        | grant-registered, unmeasured | retain the host-grant sample; do not let live counters cross the MCP as changing payload |
| HOLD request/grant CDC → phased output enables | Task 0151 | synchronized levels, unmeasured | preserve both 2FF chains; keep all OE/HOLDA decoding wholly in the 8× domain and constrain final I/O timing |
| EMU held-event/halt CDC → shared pin     | Task 0152        | source-held/phase-latched, unmeasured | preserve all three 2FF chains; constrain the final Q1/Q2 EMUA and Q3/Q4 HLDA mux at the I/O boundary |
| Host access/HCS levels → bundled payload | Task 0153        | 2FF-qualified MCP, unconstrained | preserve both synchronizers; constrain host input minima and bundled HFS/HD/control stability through capture; constrain HRDY and HD/OE outputs |
| Core↔VCLK video configuration/command/status/DIP | Task 0155 | four packed MCP mailboxes, unconstrained | declare core/VCLK asynchronous; recognize every request/ack 2FF; cut only source-held payload paths; retain bounded-stale status and sticky DIP contracts |
| VCLK→core screen request/completion | Task 0155 | held bundled MCP transaction, unconstrained | preserve request/complete toggles and source payload; keep the core request registered through memory completion |
| SLA sign-difference reduction       | Task 0130         | landed, unmeasured | reduction follows the barrel shift amount; register only if TimeQuest identifies it |
| MPYS/MPYU 32×32 multiply (`mpy_product`) | 3 (Task 0071) | watch | Operands are regfile-registered and the product is registered into `mpy_product_q` (1 EXECUTE cycle), so it should map to Cyclone V variable-precision DSP (≈3–4 DSP blocks for 32×32→64). If the combinational 32×32 multiply fails Fmax, pipeline it into 2+ stages and stretch the multiply latency (cycle count is internal to EXECUTE/WRITEBACK — not externally observable for a register op). |

## Multi-cycle operations

- **Architectural reset** — after `rst` releases, `CORE_RESET` holds one
  32-bit read request at `0xFFFF_FFE0` until `mem_ack`. PC loads on that
  acknowledge and the next state is `CORE_FETCH`; there is no stack or data
  write. The field sequencer expands that abstract request into two ascending
  16-bit word reads and holds each request through `word_ack_i`. The eight
  original-silicon RAS-only initialization cycles are implemented by the
  local-bus controller. In `tms34010_pin_system`, the core request may wait in
  the bridge while initialization runs and cannot reach physical LAD until
  all eight cycles retire.
- **Host-present reset halt** — if HCS is high during reset,
  HSTCTLH.HLT resets to one and `CORE_RESET_HALT` issues no vector or
  instruction request. In the pin system, a physical high-byte HSTCTL write
  crosses through Task 0153 before clearing HLT; the core then returns through
  `CORE_RESET` and begins the level-0 vector transaction.
- **Run-time HLT** — HSTCTLH.HLT is observed at `CORE_FETCH`, after the
  current instruction finishes. `CORE_HOST_HALT` issues no processor memory
  transaction and accepts no interrupt until HLT clears. Refresh, video, and
  screen scheduling remain independently clocked. A newly simultaneous NMI
  takes priority long enough to complete entry; HLT then stops the first ISR
  fetch. A host write completing on the same edge as an already-acknowledged
  instruction fetch can take effect at the following boundary, matching the
  direct synchronous transaction abstraction rather than claiming pin phase.
- **Synchronous host-indirect engine** — one idle host request is accepted
  and acknowledged on the next registered response cycle. A completed address
  load or last-byte HSTDATA access launches one aligned 16-bit local request;
  request, direction, address, and write data remain stable until local ack.
  Later host requests are backpressured until that side effect completes.
  INCR changes HSTADR on the HSTDATA-read acceptance edge before the local
  read; INCW changes it only on local-write acknowledge. These are internal
  core-clock relationships.
  Task 0144 routes this four-register handshake through the core/I/O boundary
  and exports the held local-word request unchanged. Task 0145 defines the
  arbiter completion contract; integration must acknowledge only completed
  local service, not selection.
  Task 0150 decodes that held address as ordinary memory or on-chip I/O.
  When it is I/O, arbitration snapshots the live internal read word on the
  grant edge; the request then waits for the same MCP/two-local-clock phase
  path as processor I/O. A write changes the internal register only when the
  returned acknowledge retires the host request.
- **Asynchronous physical host access** — Task 0153 lowers HRDY
  combinationally as soon as HCS, one legal direction, and a byte strobe form
  an access. A 2FF-synchronized combined level then captures stable
  HFS/direction/byte/HD payload into one held core-clock request. Returned
  data registers before HRDY rises and remains held until the synchronized
  access level clears. The current access remains ready if its acceptance
  starts a busy indirect side effect; busy waits the following access.
  HSTCTL also inserts two core-clock wait counts after synchronized HCS
  recognition. The host must hold the active access through HRDY and leave
  the combined access inactive for at least the synchronizer re-arm interval.
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
  Task 0152 synchronizes the physical input, stretches the execute event until
  one complete Q1/Q2 pulse is acknowledged, phase-latches the halt level, and
  selects Task 0151's HLDA result in Q3/Q4. CDC latency may delay the physical
  indication by complete local clocks but cannot shorten either half-cycle
  (A0032/A0042).
- **Physical HOLD/HOLDA release** — the 8× engine samples active-low HOLD at
  the end of Q1 and synchronizes the resulting level into the core domain.
  The arbiter grants only after its active owner completes; the synchronized
  grant returns to the phase engine, which emits early Q3/Q4 HOLDA, drops
  LAD/majority-control output enables at the following Q2, and drops
  DEN/DDOUT at Q3. After end-Q1 release sampling, the inverse Q2/Q3 sequence
  reacquires the bus. Synchronizer latency may add whole local clocks before
  either sequence begins but cannot alter its quarter-phase ordering. The
  shared pin selects this HLDA value only in Q3/Q4.
- **DRAM-refresh request** — REFCNT resets to zero while CONTROL.RR resets to
  `00`. The first active core/local clock subtracts two from RINTVL, borrows
  into ROWADR (`0 → 255`), and registers `refresh_req_o` for one clock with
  `refresh_row_o=255`. Further RR=00 requests are 32 clocks apart; RR=01
  requests are 64 clocks apart. During each request pulse, the row is the
  newly decremented value and `refresh_cbr_o` reflects CONTROL.RM. The
  Task 0145 arbiter captures this event until it performs the physical cycle;
  Task 0148 routes it through the MCP bridge to the RAS-only or CBR phase
  engine. The final wait/PLL configuration and permitted HOLD duration must
  still prove the one-entry pending latch cannot be overrun.
- **Integrated video timing** — Task 0155 runs the internal/noninterlaced
  generator on independent `vclk_i`. HCOUNT advances each active edge and
  wraps after HTOTAL; that wrap advances VCOUNT and wraps it after VTOTAL.
  Delivered counter loads take destination-edge priority. The display event
  is the `HCOUNT=HSBLNK && VCOUNT=DPYINT && ENV` interval and enters a sticky
  source event before its toggle crosses to the core DIP latch. Sync/end blank
  equality remains active for that count; start blank equality remains
  inactive until the following count. The internal positive edge represents
  the original falling-VCLK update edge; final PLL/pin phase mapping remains
  gate-6 work.
- **Screen-refresh request** — at an eligible start-HBLANK event,
  `screen_refresh_req_o` registers high and captures SRFADR/DPYTAP/ORG. The level
  and payload remain stable for an unbounded number of core clocks until
  `screen_refresh_ack_i` reports completion of the physical VRAM transfer.
  Task 0155 captures the VCLK payload behind a request toggle, holds a
  core-clock request through the arbiter/controller wait, and returns one
  completion toggle. That VCLK acknowledge clears the request, reloads LNCNT,
  and updates SRFADR by the live DUDATE/ORG value. A delivered DPYADR load wins
  a same-edge automatic update. Task 0145's arbiter contract does not acknowledge
  selection alone; acknowledge denotes completed memory-to-register service.
  Task 0148 carries that held request through the MCP bridge and returns the
  acknowledge only after the 8× screen-transfer cycle completes.
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
  the complete field. If HOLD wins between the read and write,
  `word_restart_i` suppresses the write and repeats the read after release.
- **Local-cycle arbitration** — selection uses registered owner states in
  the specified order HOLD, screen, DRAM refresh, host, then CPU. Selection
  costs an internal controller-facing bubble; once `cycle_req_o` asserts, its
  kind and payload remain stable until `cycle_ack_i`. CPU partial-word RMW
  reservation overrides ordinary priority only from the selected read through
  its write. A pulsed DRAM refresh occupies a one-entry pending latch until
  physical completion. These are internal arbitration clocks, not original
  LAD/RAS/CAS pin phases.
- **Original local-bus phases** — `tms34010_local_bus` runs from a dedicated
  clock at eight times the local-clock rate. Two 8× ticks form each Q phase,
  allowing the documented mid-quarter control transitions and the middle-Q4
  read sample. An ordinary ready cycle consumes two local clocks (16 8×
  ticks). LRDY is sampled at the end of Q1 in the access period; every low
  sample repeats that period for eight more 8× ticks. I/O cycles ignore LRDY.
  Screen-transfer TR/QE releases during the original access period and is not
  repeated with RAS/CAS/LAL. Reset release starts eight two-clock, zero-row
  RAS-only cycles, each independently extendable by LRDY. This is verified
  both standalone and through the integrated wrapper; no frequency/phase
  relationship to the core clock is assumed by the bridge.
- **Processor on-chip I/O** — every architectural CPU request first spends
  one core edge entering the fabric's registered classification stage.
  External fields then follow their existing sequencer latency; on-chip I/O
  bypasses it and waits for arbitration, the MCP round trip, and exactly two
  local clocks in the phase engine. LRDY is ignored. For writes, the internal
  register owner observes only the returned core-clock completion pulse, not
  every held request clock. For reads, the command carries the registered
  internal word and LAD remains released in the physical data phase.
- **Host-indirect on-chip I/O** — the host engine already registers address,
  direction, and write data before raising its held local request. The arbiter
  samples the independently selected internal read word when that request
  wins, then uses the same two-clock, LRDY-independent phase engine and MCP
  response. Address completion and each last-byte HSTDATA access retain their
  existing prefetch/INCR/INCW ordering; a write commits internal state only on
  the returned host acknowledge.
- **Integrated functional fabric** — `tms34010_system` routes the core's
  architectural field request through `tms34010_field_sequencer`, then joins
  its words with host, screen, and DRAM-refresh traffic in the arbiter. One
  registered request-classification stage precedes both field sequencing and
  direct processor I/O arbitration. The controller observes
  the selection bubbles and held-cycle latency described above.
  `tms34010_pin_system` adds the MCP
  round-trip and 8× phase latency but no new scheduling policy. The wrapper
  has no fixed clock-frequency ratio contract.
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

- The integrated pin system has a core clock, a dedicated 8× local-bus timing
  domain, and independent VCLK; a future PLL supplies/maps the FPGA clocks.
  Target Fmax is
  **not** set yet. Initial core-clock sanity target:
  clear 50 MHz on the documented Cyclone V `5CSEBA6U23I7`, then set the real
  target from system requirements and measured reports.
- Avoid combinational paths longer than ~10 LUT levels. If a path goes
  longer, register it or note the exception here.
- All clock-domain crossings (local bus, host interface, video) must be
  wrapped in a CDC primitive. Listed here when they land.

## Local-bus clock boundary

Task 0147 keeps the local-bus request, payload, response, and acknowledge
synchronous to `clk8x_i`. LCLK1/LCLK2 are output waveforms decoded from the
internal subphase counter and are never used as fabric clocks. A future PLL
supplies `clk8x_i`; the QSF/SDC must put that PLL output on a clock network
and constrain the physical LCLK/LAD/control pins.

Task 0148 connects the core-clock command boundary through
`tms34010_local_bus_bridge`. The source registers the complete command,
including internal I/O read data, before
toggling its request and holds the payload until the acknowledge toggle has
returned. The destination captures that stable MCP bus only after the request
passes through a dedicated 2FF synchronizer, holds its local request through
controller completion, then registers read data before toggling acknowledge.
The reverse 2FF latency guarantees that response data is stable before source
capture. One command is outstanding; a source re-arm waits for the arbiter
request to go low so the held completion cannot launch twice.

The bridge requires common reset assertion and initializes both toggle phases
to zero. Its RTL does not require a rational or fixed clock ratio, and
`tb_local_bus_bridge` tests a non-integer ratio with variable service delay.
The future SDC must declare the clock relationship, identify both
synchronizers, and cut or waive only the protocol-protected MCP payload paths.
Until Quartus recognizes those chains and TimeQuest/CDC reports are archived,
this is functional CDC evidence rather than FPGA timing sign-off.

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
be claimed until the real project exists. The supplemental `dpyint_set_i`
remains a synchronous core-clock event. Task 0155's display compare lives in
VCLK: a sticky event feeds a packed one-bit MCP mailbox and emits one core
pulse, while an already pending architectural DIP makes multiple intervening
events equivalent.

## Host pin CDC boundary

Task 0153 treats the combined legal physical access and HCS-active indication
as asynchronous levels. Each enters the core clock through its own attributed
2FF `tms34010_sync_bit`. HRDY falls directly from raw active pins before the
combined level can reach the second stage, requiring the external host to
hold HFS, direction, byte enables, and HD stable. The core captures that
bundled MCP payload only after synchronization, holds its request to the
register engine until acknowledge, registers returned data, and then releases
HRDY. No individual HFS or HD bit is independently synchronized.

The external access must remain active until HRDY is high, then remain
inactive long enough for the combined level to cross low through both stages
and clear the one-access latch. HFS must already be stable when HCS falls so
the HCS-only HSTCTL wait can be classified. These are functional protocol
requirements verified by `tb_host_bus`; the final SDC must constrain
pin-to-first-stage paths, recognize both 2FF chains, prove the host's minimum
active/inactive strobe widths, constrain the bundled payload relative to the
capture edge, and close HRDY plus HD/output-enable pin delays.

## Dedicated video clock boundary

Task 0155 closes the functional VCLK boundary:

- HCOUNT/VCOUNT, timing compares/outputs, DPYADR, and the screen scheduler are
  wholly in `vclk_i`;
- one source-held packed mailbox carries all twelve timing/display
  configuration words atomically, and a second carries coalesced live-owner
  commands;
- a continuously re-armed packed mailbox returns coherent
  `{HCOUNT,VCOUNT,DPYADR}` snapshots. The core view is handshake-latency stale
  but never bit-torn;
- a pending DIP condition crosses through a one-bit toggle mailbox;
- a dedicated request/completion bridge holds SRFADR/DPYTAP/ORG through
  arbitrary core-memory waits.

The core and VCLK clocks are asynchronous. The final SDC must define both
clocks, use asynchronous clock groups, preserve and report every toggle 2FF,
and cut/waive only payload buses proven stable by the MCP protocol. Both
domains must sample the common synchronous reset asserted so toggle phases
start at zero. If VCLK stops, status remains at its last coherent snapshot and
pending commands complete only when it resumes (A0045).

## Cyclone V-specific notes

To be filled in once `scripts/synth_quartus.sh` produces real reports.
Anticipated items: M10K inference style, DSP usage for the shifter,
clock network choice (regional vs. global) for the core clock.
