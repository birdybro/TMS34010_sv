# Timing notes

> Status: **functional latency and measured Cyclone V implementation evidence
> through Task 0160**. Quartus Prime Lite 17.0.2 closes the complete design at
> 50/200/50 MHz with +0.747 ns worst setup, +0.128 ns worst hold, zero TNS,
> and no ignored constraints.

## Known long paths and measured disposition

| Path                                | Phase introduced | Status   | Mitigation if needed |
|-------------------------------------|------------------|----------|----------------------|
| Decode → dispatch/result boundary   | 3 / Task 0160    | closed with registered decode and ordinary result | retain both explicit register boundaries and their narrow two-cycle SDC |
| Bit-addressed field/XY/graphics logic | 5 / 7          | closed at 50 MHz | keep memory hand-offs registered |
| Wide barrel shifter / field masks   | 2 / 5            | closed at 50 MHz | stage only after new measured evidence |
| Field-window shift/mask and word merge | Task 0136      | closed through registered word boundary | preserve that boundary |
| 8× local-bus phase/pin decode       | Tasks 0147/0159  | closed at 200 MHz and bounded to pins | keep outputs wholly in the 8× domain |
| Core↔8× MCP payload/response paths  | Task 0148        | stable-payload exceptions applied; toggles recognized | preserve source-held payloads and 2FF attributes |
| CPU/I/O classification and completion | Tasks 0149/0160 | closed with registered ingress and I/O snapshot | retain both stages |
| HOLD/EMU/host CDC and pad enables   | Tasks 0151–0153  | constrained; required 2FF chains recognized | preserve the protocol-held payloads and phased OE owner |
| Core↔VCLK mailboxes and screen transaction | Task 0155 | constrained asynchronous groups/MCPs; chains recognized | retain one-outstanding source-held contracts |
| External HSYNC/VSYNC → VCLK         | Task 0157        | constrained inputs; both level chains recognized | retain delayed edge recognition |
| Graphics SRT request classification | Task 0158        | closed through registered fabric ingress | retain captured SRT sideband |
| Board reset / PLL locks             | Task 0159        | assertion cut, three release chains recognized | preserve synchronous destination-domain release |
| HD/LAD/control/sync IOEs            | Task 0159        | 63 fitted pins with bounded min/max paths | re-run full implementation after any pad change |
| MPYS/MPYU 32×32 multiply            | Task 0071        | closed using 6 DSP blocks total | pipeline only after new measured evidence and full regression |

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
  engine. At the final 50/200 MHz ratio, `tb_fpga_refresh_ratio` observes
  complete physical service in at most 11 of 32 available core clocks when
  HOLD is inactive and LRDY is bounded. Unbounded external ownership or wait
  remains the explicit environmental limit.
- **Integrated video timing** — Task 0155 runs the timing
  path on independent `vclk_i`. In internal NIL=1 mode HCOUNT wraps after HTOTAL and
  advances/wraps VCOUNT after VTOTAL. Task 0156 adds NIL=0 fields: reset starts
  even; the odd field clears VCOUNT at `floor(HTOTAL/2)` without resetting
  HCOUNT; its VESYNC half-line event advances VCOUNT again; and the next even
  field starts at the ordinary full-line VTOTAL event. Delivered counter
  loads take destination-edge priority. The display event is normally the
  `HCOUNT=HSBLNK && VCOUNT=DPYINT && ENV` interval; the coincident odd-field
  VESYNC half-line advance suppresses that one stale compare as §9.7
  requires. Sync/end blank equality remains active for that count; start
  blank equality remains inactive until the following count. The internal
  positive edge represents the original falling-VCLK update edge; Task 0160's
  generated clocks and output constraints close the PLL/pin mapping.
  Task 0157 adds external mode: each raw active-low sync level uses its own
  attributed 2FF plus saved history, so a sampled falling input clears its
  counter on the third update edge (the guide's 2.5-VCLK offset). External
  HSYNC or HTOTAL, whichever arrives first, begins a line unless HSD keeps
  horizontal timing internal. External VSYNC clears only VCOUNT; VTOTAL plus
  line start is its fallback. NIL=0 classifies the next field from
  `HEBLNK < HCOUNT <= HSBLNK` at recognition, while NIL=1 forces even.
  DXV/HSD generate separate horizontal and vertical output enables.
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
  Task 0156 keeps the field phase in VCLK: a DPYSTRT reload preceding the odd
  field is unchanged, while one preceding the even field applies signed
  DUDATE/2. Per-line completion still applies full DUDATE.
- **Program-controlled VRAM transfers** — while DPYCTL.SRT is set, the core
  asserts `mem_srt` only for pixel requests in PIXT, DRAV, LINE, FILL, and
  PIXBLT states. The registered fabric ingress captures that tag with the
  complete field request; each resulting aligned word read/write becomes an
  MTR/RTM arbitration cycle. Explicit transfers consume the same two local
  clocks as screen transfer: initial DEN/DDOUT input selection, TR/QE low
  through RAS fall and early access, then release before RAS. RTM additionally
  holds W low from first-period Q2A through Q3B and releases it before the
  column address. LRDY extends the access period with the same transfer-release
  behavior. No second-period LAD data is exchanged. Direct replace writes
  skip an architectural destination read when PPOP=replace, transparency is
  disabled, PMASK is zero, and no existing window path needs it; alignment-
  required partial writes still use the field sequencer's word RMW.
- **Array completion under stalls** — FILL and PIXBLT sample dimensions and
  implied operands before their pixel loops. A zero dimension returns from
  setup without issuing a pixel request. For nonempty arrays, counters and
  row/address context advance only on the final field acknowledge for that
  pixel; the held request payload cannot change while acknowledge is low.
  FILL's last acknowledge leaves DADDR at final-row next-X, while PIXBLT's
  last acknowledge installs both hypothetical next-row bases before their
  two writeback cycles. `tb_graphics_array_edges` runs all forms with three
  extra physical-word wait cycles and monitors every held field payload.
- **Directional PIXBLT sequencing** — PBH/PBV are latched with the implied
  operands. Reverse-X computes the same field request as a predecrement
  pointer, then holds that address/data through every physical-word wait.
  Counters and traversal pointers advance only after the destination write
  field acknowledge. At a row boundary, the internal base adds or subtracts
  pitch according to PBV, while a separate architectural result pointer
  always adds positive pitch. This prevents stalls or reverse traversal from
  perturbing final SADDR/DADDR. Binary-source forms latch neither direction.
- **W=1 common-rectangle sequencing** — after WSTART/WEND are latched, the
  array/window intersection is purely combinational and issues no memory
  request. On a hit, the existing hit state writes DADDR and performs the
  V/WVP update; one dedicated following state writes DYDX through the same
  single B-register port. A miss returns directly to fetch. Interrupt
  recognition remains at the subsequent fetch boundary, after both hit-result
  writes have retired.
- **W=3 array-preclip sequencing** — the same inclusive intersection is
  evaluated in `CORE_FILL_SETUP_WIN`/`CORE_PBLT_SETUP_WIN`, before the first
  pixel request. The following edge atomically installs effective dimensions,
  row bases, and traversal corners. PIXBLT offsets source and destination by
  the same removed columns/rows before PBH/PBV selection; binary source X
  offsets are one bit and full-color offsets are PSIZE. A disjoint rectangle
  or reversed-axis empty window advances directly to status-only completion,
  so no source/destination field
  request or SRT-tagged MTR/RTM command exists to enter the fabric. Surviving
  read, optional destination-read, and write requests retain the ordinary
  acknowledge-only advancement and held-payload rules. Separate saved result
  pointers publish original-array terminal context after the effective loop.
- **FILL/PIXBLT checkpoint sequencing** — after a completed destination write,
  a nonfinal word or row boundary enters seven quiet B-file writeback states.
  B0/B2/B10-B14 commit in order through the single register-file port; FILL
  skips writes to its unused B0/B13 while retaining the same state cadence.
  No memory request is asserted in this sequence. The final B14 state alone
  marks a coherent `array_checkpoint`, after all held field traffic and any
  physical partial-word read/modify/write have retired. The next cycle
  resumes the array loop. A final pixel bypasses the sequence and uses the
  ordinary post-instruction fetch boundary. This is functional checkpoint
  granularity, not a claim of exact original-silicon cycle parity; Task 0167
  consumes the final state for PBX interrupt entry.
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

- The Task 0159 Cyclone V adapter fixes the clock plan:
  `FPGA_CLK1_50` enters an Intel PLL that emits 50 MHz core and 200 MHz 8×
  local-bus timing clocks; independent continuously running
  `FPGA_CLK2_50` feeds a second PLL with phase-zero 50 MHz internal VCLK and
  a 180-degree 50 MHz pin clock. The phase engine divides its 200 MHz clock
  into eight subphases, so each LCLK waveform has a 25 MHz period. Task 0160
  proves those exact generated clocks and closes 50/200/50 MHz setup/hold on
  `5CSEBA6U23I7`.
- `VIDEO_VCLK` uses the second PLL's 180-degree output, mapping the internal
  positive edge to the original falling-edge update phase without a fabric
  clock inverter. TimeQuest constrains the output relationship and absolute
  sync/blank paths.
- Avoid combinational paths longer than ~10 LUT levels. If a path goes
  longer, register it or note the exception here.
- All clock-domain crossings (local bus, host interface, video) must be
  wrapped in a CDC primitive. Listed here when they land.

## Local-bus clock boundary

Task 0147 keeps the local-bus request, payload, response, and acknowledge
synchronous to `clk8x_i`. LCLK1/LCLK2 are output waveforms decoded from the
internal subphase counter and are never used as fabric clocks. Task 0159's
PLL supplies `clk8x_i` at 200 MHz; the QSF/SDC must prove that generated
clock is on a clock network and constrain the physical LCLK/LAD/control pins.
Task 0160's fitted clock and output-path reports satisfy that requirement.

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
The SDC declares the clocks asynchronous, recognizes both synchronizers, and
cuts only the protocol-protected stable MCP payload paths. Task 0160's
TimeQuest/metastability reports supply the independent FPGA timing evidence.

## Interrupt input CDC

LINT1 and LINT2 are raw asynchronous active-low level inputs. Each passes
through its own `tms34010_sync_bit` instance: two core-clock flops with no
combinational logic between them and Quartus `PRESERVE`,
`SYNCHRONIZER_IDENTIFICATION`, and `useioff=0` attributes. Reset initializes
both synchronized levels inactive-high. The core therefore observes a pin
transition after two core-clock sampling edges; this is the FPGA abstraction
of the guide's one-to-two-state synchronization delay.

The SDC marks pin-to-first-stage paths asynchronous, and the Quartus
metastability report recognizes both chains. The supplemental
`dpyint_set_i` remains a synchronous core-clock event. Task 0155's display
compare lives in VCLK: a sticky event feeds a packed one-bit MCP mailbox and
emits one core pulse, while an already pending architectural DIP makes
multiple intervening events equivalent.

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
requirements verified by `tb_host_bus`. The final SDC constrains
pin-to-first-stage paths, recognizes both 2FF chains, bounds the bundled
payload relative to capture, and closes HRDY plus HD/output-enable paths.
The external host remains responsible for the documented active/inactive
strobe widths.

## Dedicated video clock boundary

Tasks 0155–0157 close the functional video-timing VCLK boundary:

- HCOUNT/VCOUNT, even/odd field phase, timing compares/outputs, DPYADR, and
  the screen scheduler are wholly in `vclk_i`;
- one source-held packed mailbox carries all twelve timing/display
  configuration words atomically, and a second carries coalesced live-owner
  commands;
- a continuously re-armed packed mailbox returns coherent
  `{HCOUNT,VCOUNT,DPYADR}` snapshots. The core view is handshake-latency stale
  but never bit-torn;
- a pending DIP condition crosses through a one-bit toggle mailbox;
- a dedicated request/completion bridge holds SRFADR/DPYTAP/ORG through
  arbitrary core-memory waits;
- raw active-low HSYNC/VSYNC levels pass through individual attributed 2FF
  synchronizers and edge history in VCLK; DXV/HSD direction resolves to
  explicit output enables at the pin-system boundary.

The core and VCLK clocks are asynchronous. The SDC defines both clocks, uses
asynchronous clock groups, preserves/reports every required toggle 2FF, cuts
only payload buses proven stable by the MCP protocol, and constrains external
sync input/output paths. Task 0159 gives each domain a separately synchronized
active-high reset release from one common assertion request, so toggle phases
start at zero without an asynchronously released shared net. If VCLK stops,
status remains at its last coherent snapshot and pending commands complete
only when it resumes (A0045/A0047/A0049/A0050).

Task 0158 adds no new clock crossing: its SRT value and graphics request are
both core-clock signals captured before the already landed core-to-8× MCP.
The expanded cycle kind then crosses as part of the existing stable command
payload. Task 0160 includes the MTR/RTM pin paths in the same 8× absolute
output-delay and output-enable analysis as screen transfer (A0048).

## Cyclone V-specific notes

Task 0159 isolates `altera_pll` under `rtl/fpga/`, isolates every high
impedance assignment in `tms34010_fpga_io`, and provides one reset-release
chain per clock domain. Task 0160 measures 10,017 ALMs (24%), 8,039
registers, zero block-memory bits, 6 DSP blocks (5%), and 2 PLLs (33%). The
fit uses all 63 assigned pins. Across all enabled corners, worst setup is
+0.747 ns, worst hold is +0.128 ns, worst minimum-pulse slack is +1.250 ns,
and TNS is zero. Recovery/removal reports have no paths because asynchronous
assertion is cut before the first stage and release is synchronized. Exactly
54 forced stages form the 27 required two-register synchronizer chains, all
of which enter MTBF analysis. `fpga/IMPLEMENTATION_EVIDENCE.md` records the
complete reproducible result and accepted warning set.
