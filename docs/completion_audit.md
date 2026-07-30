# Completion audit

> Baseline: functional implementation and reproducible Cyclone V
> implementation sign-off through Task 0160. Task 0161's production-revision
> GPU re-audit found remaining programmer-visible graphics behavior, so the
> prior seven gates remain historical baseline evidence rather than a
> GPU-complete sign-off. GPU completion is withheld until Tasks 0162–0174.

## Official ISA reconciliation

The complete instruction-summary tables in the 1988 TMS34010 User's Guide
§12.3 (pages 12-12 through 12-18) were compared with
`docs/instruction_coverage.md` and `tms34010_decode.sv`. Every summary-table
row now has a corresponding implemented coverage entry and named
self-checking test. This is a functional reconciliation; original-silicon
cycle counts remain part of the physical timing work.

Task 0125 closed the audited logical findings: every register, unary, and
immediate logical form now uses its individual Z-only status mask;
ANDI/ANDNI implement both extension conventions through their shared
`Rd & ~extension` hardware operation; and CLR and DEC have exact alias tests.

Tasks 0126 and 0127 closed both postincrement-destination MOVE rows with
signed-offset/absolute-address, arbitrary-field, unaligned/straddling,
pointer, register-file, and status-preservation coverage. Task 0128 closed
EMU with explicit RUN-as-NOP, active-low acknowledge, halt-quiescence, and
resume coverage. There are no unimplemented §12.3 rows.

Task 0129 resolved A0013 and A0018 from the individual MOVK, ADDK, and SUBK
pages: their five-bit field encodes constants 1 through 31 directly and
constant 32 as zero. Exact zero-field result and arithmetic-status cases are
now regression-locked.

Task 0130 resolved A0019 across all ten shift forms. Right-shift immediate
encoding, SLA overflow, count zero, and each affected/unaffected status bit
are now tied to the individual instruction pages and direct tests.

Task 0131 resolved A0011 for both MOVI widths. N/Z and forced-zero V updates,
C preservation, IW sign extension, and IL word ordering/results now have
full-status regression evidence.

Task 0132 resolved A0025 directly from the REV and EXGPC pages. REV returns
the guide's `0x00000008` TMS34010 revision value; EXGPC stores the next PC in
Rd and clears all four LSBs of the register-sourced PC. A deliberately
unaligned target and full-status snapshots now lock both rules.

Task 0133 resolved A0029 from the FILL XY destination-array description.
The initial XY DADDR is converted with OFFSET/CONVDP; the final DADDR is the
linear address immediately after the last pixel on the final row. Exact
address, row-pitch, memory-effect, and W=0 full-status checks are regression
locked.

Task 0134 resolved A0027 from §4.3's signed 16-bit XY definition and the
SUBXY status table. C/V use signed source-greater-than comparisons; a direct
negative/positive vector distinguishes them from the prior unsigned-borrow
interpretation.

Task 0135 completed the individual-page N/C/Z/V sweep and resolved A0009.
The static decoder policy is exhaustively checked over all 65,536 opcodes,
while focused runtime tests lock divide/modulo overflow, even/odd multiply
result widths, array preclipping V, and PIXT XY-destination window behavior.
The audit distinguishes Undefined/Indeterminate flags—preserved
deterministically by this RTL—from architecturally Unaffected flags. No
active ISA/status assumption remains.

Task 0136 resolved A0005 from §§3.1, 4.1, and 11.3. A synthesizable field
sequencer now expands the core's bit-addressed 1–32-bit requests into the
specified ascending 16-bit word reads, direct full-word writes, and
partial-word read/modify/write pairs for alignment cases A–G. Tests lock
exact word order/count/data, per-word RMW indivisibility, arbitrary word-side
stalls, and reset recovery. Pin-level local-bus phases remain an integration
gate, not an architectural field-alignment uncertainty.

Task 0137 completed every maskable pending-source path at the core boundary.
Dedicated two-flop synchronizers turn active-low LINT1/LINT2 levels into
read-only X1P/X2P, HIP reflects host INTIN, and DIP/WVP are hardware-set
latches with specification-defined write-zero clearing. Host and display
sidebands make those sources testable until their clock-domain wrappers land;
direct entry tests lock both external vectors and INT1-over-INT2 priority.

Task 0138 corrected the pre-audit refresh model against User's Guide pages
6-45/6-46 and integrated it as the processor-visible REFCNT register.
CONTROL.RR now subtracts two/one from the continuous interval/row counter,
borrow emits the 32/64-clock refresh request with a descending row, and
CONTROL.RM plus request/row are exported at the core boundary. A physical
refresh bus cycle and request retention still belong to the memory fabric.

Task 0139 integrated the internal/noninterlaced timing subset with the I/O
registers. HCOUNT/VCOUNT are live writable counters, DPYCTL.ENV forces blank
and inhibits new display interrupts when clear, and the corrected
`HCOUNT=HSBLNK` event sets the landed DIP latch on the selected DPYINT line.
Timing intervals now leave the core boundary. At that checkpoint, the
independent VCLK/CDC, external-sync, interlace, and display-memory paths
remained exit-gate work.

Task 0140 corrected the inherited standalone timing interval endpoints
against the individual Chapter 6 register pages and §§9.5/9.6. Sync and
leading blank remain active at their programmed end-count equality; trailing
blank becomes active only on the count after HSBLNK/VSBLNK. The HSBLNK
display event remains at equality, before the delayed blank output transition.

Task 0141 completed live DPYADR and the noninterlaced screen-refresh client.
DPYSTRT supplies frame/line reloads, SRE plus LNCNT schedule active-line
requests, and captured SRFADR/DPYTAP remain held until completion acknowledge.
DUDATE/ORG updates now occur only at completion. Physical VRAM
memory-to-register service and arbitration remain in the memory-fabric gate.

Task 0142 completed direct HSTCTL semantics and processor halt behavior.
Complementary low-byte ownership now produces the real HIP/HINT paths, both
sides share masked HSTCTLH fields, HCS can defer reset-vector fetch, and HLT
quiesces processor traffic at an instruction boundary without stopping
refresh/video state. At that checkpoint, the physical asynchronous host port,
HRDY, and indirect HSTADR/HSTDATA memory cycles remained in the
host/memory-fabric gate.

Task 0143 implemented the synchronous HSTADR/HSTDATA engine. It now has
word-aligned address storage, a prefetch/write data buffer, both LBL
byte-last conventions, before-read INCR, after-write INCW, held local-word
requests, and serialization of host side effects. The module remains an
integration boundary until its processor-visible register port, Task 0142
HSTCTL path, and local-word client are connected to the core and arbiter.

Task 0144 connected the register-side boundary. The core now exposes one
synchronous four-register host port; processor HSTADR/HSTDATA accesses share
the engine-owned state without indirect side effects; and the engine's held
aligned-word client leaves the core. At that checkpoint, the remaining
host-memory work was arbiter service plus the asynchronous pin/HRDY/CDC
wrapper.

Task 0145 landed the specification-priority local-cycle arbiter from §11.3.
Registered ownership enforces HOLD, screen, DRAM refresh, host, then CPU
priority without truncating an active cycle. A one-entry latch retains the
pulsed DRAM-refresh row/mode through contention. CPU partial-word RMW pairs
remain indivisible, while different words of one field are preemptable; HOLD
between the partial read and write suppresses that write and restarts the
complete pair after release. Physical cycle generation and integration of the
landed clients with this arbiter remain in the memory-fabric gate.

Task 0146 closed that abstract integration gap. `tms34010_memory_fabric`
composes field-to-word sequencing with fixed-priority arbitration, and
`tms34010_system` connects the core's CPU/graphics, screen, DRAM-refresh, and
host-indirect clients through it. End-to-end regression boots real
instructions, programs and services screen refresh, retains automatic DRAM
refresh, completes host-indirect reads, and verifies HOLD quiescence at one
controller-facing request/ack boundary.

Task 0147 landed the standalone original-pin phase engine.
`tms34010_local_bus` uses a dedicated 8× timing clock to generate
LCLK1/LCLK2 plus the documented LAD/RAS/CAS/LAL/W/TR/DEN/DDOUT phases for
ordinary word, screen memory-to-register, RAS-only, CAS-before-RAS, and I/O
cycles. It implements word/refresh/screen address-status formats, end-Q1 LRDY
sampling and whole-clock extensions, mid-Q4 read capture, I/O LRDY bypass,
and eight zero-row RAS-only cycles after reset.

Task 0148 connected that phase engine to the functional system.
`tms34010_local_bus_bridge` uses a source-held two-phase MCP command and
reverse response handshake; only request/ack toggles pass through attributed
2FF synchronizers. `tms34010_pin_system` composes the core-clock system,
bridge, and 8× controller. Opcode IAQ and captured screen ORG now propagate
end to end, and the pin-level regression proves reset initialization precedes
the two-word vector and real instruction fetches. At that checkpoint,
physical HOLD release, on-chip I/O bus completion, host pins, and Quartus CDC
sign-off remained; Tasks 0149–0153 close every functional pin-side item,
while Quartus CDC sign-off remains.

Task 0149 completes physical on-chip I/O cycles for processor accesses. A
registered fabric stage classifies and holds the architectural CPU request;
external fields still use the field sequencer, while I/O bypasses it and
selects the landed two-clock I/O cycle kinds with internal read data. IAQ is
inactive, physical completion returns through the MCP bridge, and I/O writes
commit only on that single completion. The guide separately requires the same
cycle for host-indirect I/O addresses.

Task 0150 completes that host-indirect half. The held host word address now
selects the I/O cycle kinds for the complete internal page, and an independent
register-owner read view supplies its data. Arbitration samples live read data
at host selection; the existing MCP/phase path returns it to HSTDATA. Writes
commit only on physical completion, including live registers and the
host-side HSTCTLL ownership rules. Pin-level regression locks one processor
write/read plus host prefetch/read/write as exactly five RAS/LAL-only cycles.

Task 0151 closes physical HOLD release. The 8× phase engine samples
active-low HOLD at the end of Q1, synchronizes that level into the core
arbiter, and synchronizes its quiescent grant back. HOLDA becomes active only
in Q3/Q4 before the bus is released; the LAD/majority-control output enables
drop at the following Q2 and DEN/DDOUT drop at Q3. The inverse sequence
reacquires the bus after release. Active cycles still finish, queued commands
cannot start while held, and the arbiter retains its partial-RMW restart
contract. That task deliberately left the final shared HLDA/EMUA output mux
as physical-wrapper work.

Task 0152 closes the shared output that Task 0151 deliberately left split.
Physical RUN/EMU is synchronized into the core with RUN as the safe reset
value. Each architectural EMU event becomes a held CDC request that is
acknowledged only after one complete Q1/Q2 pulse, while the separately
registered halt level is sampled only at Q4-to-Q1 boundaries. The integrated
pin system now exports one original HLDA/EMUA signal: EMUA owns every
LCLK1-high Q1/Q2 half and HLDA owns every LCLK1-low Q3/Q4 half. Focused and
end-to-end tests lock RUN-mode pulse count, halt/release, simultaneous HOLD,
and phase exclusivity.

Task 0153 closes the asynchronous physical host port. HCS, exactly one of
HREAD/HWRITE, and at least one byte strobe qualify an access. HRDY falls
immediately while a synchronized access level establishes a stable
HFS/direction/byte/data bundle, then the bridge holds one synchronous request
through acknowledgement and retains returned data until physical release.
Reads enable only selected HD lanes. HCS alone starts the HSTCTL wait, a
completed access remains ready even if it launches a busy indirect operation,
and that busy state waits the following access. `tb_host_bus` locks these
rules with clock-offset pin transitions; `tb_pin_system` now performs all
host register traffic through the physical pins.

Task 0154 closes the remaining unscoped I/O-register storage behavior.
CONTROL bits 1:0, DPYCTL bit 1, and DPYTAP bits 15:14 are masked on both
processor and host-indirect completion paths. Reserved indices 17h–1Ah ignore
writes and return zero, including the PMASK future-compatibility word whose
write the guide explicitly says has no effect. Existing specialized owners
for host, interrupt, refresh, counter, and display registers are unchanged;
A0033 continues to isolate REFCNT bits 1:0. Defined DPYCTL modes awaiting
consumers are assigned to the video gate rather than left as ambiguous I/O
state.

Task 0155 closes the independent core/VCLK boundary. HCOUNT/VCOUNT, all timing
compares, DPYADR, and screen scheduling now live exclusively in `vclk_i`.
Packed source-held mailboxes carry atomic configuration, coalesced live
commands, and coherent bounded-stale status; DIP uses a held event crossing;
and each screen request retains its bundled SRFADR/DPYTAP/ORG payload through
core-memory completion. `tb_video_cdc` exercises every crossing under a
non-integer clock ratio. External synchronization and serial display/pixel
behavior remain gate-5 work.

Task 0156 closes internally generated interlace. NIL=0 selects repeated
even/odd fields: the odd field begins at the HTOTAL/2 event without resetting
HCOUNT, its VESYNC half-line compare advances VCOUNT again, and the even field
returns at the ordinary full-line VTOTAL event. The resulting count sequence
also implements the §9.7 odd-field DPYINT suppression. Field phase remains
wholly in VCLK and selects an unchanged DPYSTRT reload before odd fields or
signed DUDATE/2 before even fields. A cycle-by-cycle timing test plus direct
display-address cases cover both fields and both ORG directions.

Task 0157 closes external synchronization. DPYCTL.DXV/HSD now select the
documented input/output combinations; separately attributed synchronizers and
edge history recognize active-low HSYNC/VSYNC at the specified 2.5-VCLK
offset. External edges and total-register fallbacks control the counters,
HSD retains internally generated horizontal timing when requested, NIL
selects noninterlaced or horizontal-phase-based field discrimination, and
explicit output enables propagate through the pin-system boundary.
`tb_video_external_sync` locks recognition latency, both fallbacks, HSD,
field selection, NIL, and direction.

Task 0158 closes DPYCTL.SRT and the remaining TMS34010 video-memory boundary.
Only graphics pixel accesses are tagged; reads become explicit VRAM
memory-to-register cycles and writes become register-to-memory cycles, while
all instruction, ordinary data, I/O, host, refresh, and scheduled screen
traffic remains unchanged. The phase engine now emits the ordinary address
with active TR status, the specified TR/QE transfer envelope, and the RTM
W-at-RAS distinction. Direct replace graphics writes avoid an unnecessary
destination read, while PPOP, transparency, PMASK, and applicable window
operations retain it. The TMS34010 has no pixel-data output pins: attached
VRAM emits pixels from its serial port, so modeling that external device is
not a missing TMS34010 feature.

## Active architectural assumptions requiring closure

No active architectural compatibility assumption remains. New uncertainty in
future work must still be resolved by primary-spec evidence plus tests or
retained as an explicit project-level deviation.

A0003 (synchronous active-high FPGA reset), A0004 (explicit project clock
domains), A0006 (functional-first timing), and A0034 (video timing and
synchronization) are intentional design choices. A0035
isolates deterministic collision/undefined behavior around the screen-refresh
handshake, A0036 isolates the direct synchronous host boundary and
otherwise-unpredictable simultaneous high-byte write choice, and A0037
isolates host-engine collisions and the pre-pin synchronous protocol. A0038
records the one-entry DRAM-refresh retention bound; Task 0160 proves physical
service before the next minimum interval under its documented external-wait
assumptions. A0039 records the 8×
phase representation, synchronous-reset phase origin, deterministic
undefined LAD value, and explicit CDC boundary. A0040 records the MCP's
one-outstanding/common-reset contract and completed Quartus constraint proof.
A0041 records physical HOLD's synchronized level handshake and phased
output-enable implementation. A0042 records the one-outstanding EMU-event
handshake and phase-latched halt indication. A0043 records the asynchronous
host bundled-data/re-arm contract and completed FPGA I/O timing work. A0044
records the reserved-location read-zero choice and REFCNT exception. A0045
records the dedicated VCLK MCP/stopped-clock/active-edge/reset contract. A0046 records
interlaced phase recovery, counter-write priority, and equality-counter
programming requirements. A0047 records external-sync sampling, recognition,
fallback, field classification, direction, and final FPGA I/O choices. A0048
records explicit SRT transfer classification/phases, the deterministic
no-LAD read result, and the processor/external-VRAM scope boundary. Task
0159's A0049 records the Cyclone V clock ratio, independent board VCLK,
per-domain reset release, physical video-clock phase, and top-level-only
tri-state choices. A0050 records Task 0160's Quartus/tool/pin/constraint,
report-validation, CDC, resource, and refresh-service closure. These do not
excuse missing architectural state or interface behavior; future differences
from the signed-off baseline must be documented as deliberate boundaries.

## Production-revision GPU completion gaps

Task 0161 found concrete functional gaps beyond the Task 0160 baseline:
FILL, PIXBLT, and LINE lacked their architectural mid-instruction
interrupt/resume contracts, and the now-closed early tasks included
empty-array/context, direction, and W=1/W=3 geometry defects.
The existing tests also lack a complete graphics/display conformance matrix,
pinned MAME differential coverage, and TI-shipped graphics workloads.

Task 0162 closed the empty-array and terminal-context findings. Zero DX or DY
now exits every FILL/PIXBLT form without graphics traffic or architectural
writeback. PIXBLT final SADDR/DADDR identify the hypothetical next-row starts,
whereas FILL retains the final-row next-X result. The 24-case
`tb_graphics_array_edges` matrix covers all forms, signed/non-unit pitches,
multiple pixel sizes, and injected word-side stalls.

Task 0163 closed directional traversal. All full-color forms now honor PBH/PBV;
L,L consumes software-adjusted corners, mixed/XY forms automatically adjust
both arrays, binary forms ignore direction, and independent result pointers
retain exact completion context. `tb_pixblt_direction` covers the 16-case
form/direction matrix, degenerate edges, signed traversal, stalls, and safe
forward/reverse overlapping copies.

Task 0164 closed W=1 common-rectangle results. FILL XY and all
XY-destination PIXBLTs compute the inclusive destination/window intersection
without pixel traffic and return exact DADDR/DYDX on a hit. Full-color
direction selects the returned corner without changing geometry; FILL and
binary forms use the lowest-address corner. The 26-case
`tb_window_common_rect` matrix covers all forms/directions and geometry
classes, exact V/WVP and B-register results, empty arrays, stalls, and
memory quiescence.

Task 0165 closed true W=3 preclipping. FILL XY and PIXBLT
B,XY/L,XY/XY,XY now replace private working geometry before the first
transfer; PIXBLT advances both arrays by identical excluded pixel offsets
before applying direction. Clipped and fully excluded pixels cannot issue
source, destination, MTR, RTM, or write traffic, while original-array final
context and V-only/no-WVP behavior remain intact. The 23-case
`tb_window_preclip` reference model checks exact request sequences,
framebuffer alignment, every form/direction/edge, all pixel sizes, legal
pitches, PPOP/PMASK destination reads, SRT, and arbitrary waits.

Task 0166 closed checkpointable FILL/PIXBLT execution. Every form now
publishes a coherent B-file restart image after completed destination-word
and nonfinal-row boundaries, with no active request and only after any
partial-word RMW has retired. The final B14 commit is the sole safe
recognition point. `tb_array_checkpoint` checks all eight forms and proves
that every captured B0/B2/B10-B14 image reconstructs the exact remaining
request suffix under direction, W=3, processing, SRT, and stalls.

Task 0167 closed PBX-based array interrupt/resume. Every legal checkpoint now
accepts maskable or NMIM=0 nonmaskable entry with the rewound opcode PC and a
PBX-marked stacked ST. RETI refetches the opcode and reconstructs private
engine state exclusively from the handler-preserved architectural image;
later checkpoints remain interruptible and final completion clears PBX.
`tb_array_checkpoint` interrupts every checkpoint in all eight forms and
retains its exact uninterrupted request/framebuffer/context oracle under
stalls. Ordinary and LINE entries are explicit PBX-negative controls.

Task 0168 closed LINE pixel-boundary continuation. Every nonfinal completed
pixel publishes B0/B2/B10 before accepting entry; LINE stacks the rewound
opcode PC with PBX clear, and RETI reuses normal implied-B setup. The
all-octant reference matrix interrupts every checkpoint with DI/NMI under
RMW, W=3, SRT, and stalls while retaining exact traffic/context. W=1/W=2
aborting pixels are verified final completions without restart images.

Tasks 0169–0171 close the remaining functional and pin-integration items, Tasks
0172–0173 add independent differential and surviving-software evidence, and
Task 0174 performs the final full-regression and Quartus sign-off. External
VRAM/DRAM, level translation, board-level signal integrity, and the VRAM
serial-pixel path remain surrounding-system responsibilities rather than
unfinished processor behavior.

## Historical Task 0160 exit gates

1. **Complete (Task 0135):** resolve all active ISA/status assumptions and
   correct discovered semantic mismatches.
2. **Complete (Tasks 0126–0128):** implement and directly test the two missing
   MOVE forms and EMU behavior; ensure every §12.3 row has a spec citation and
   named test.
3. **Complete (Tasks 0137, 0139, 0141–0144, 0149–0150, 0154):** complete
   I/O side effects and every interrupt source. Source-specific pending bits,
   live video/refresh/display registers, host ownership, completion-qualified
   processor/host I/O paths, and every documented reserved field/location now
   have direct tests. Task 0158 consumes SRT; cache controls remain in the
   optional cache/cycle-accuracy scope.
4. **Complete (Tasks 0136, 0145–0153):** land the pin-level local memory
   controller, refresh, host, and arbitration fabric with LRDY/reset tests.
   Task 0136 completed field-to-word sequencing; Tasks 0145–0146 landed and
   integrated arbitration; Tasks 0147–0148 landed the 8× phase engine and
   coherent CDC/system path; Tasks 0149–0150 completed both on-chip I/O
   requesters; Tasks 0151–0152 completed HOLD and HLDA/EMUA; and Task 0153
   completed the asynchronous host pins, HRDY, and HD direction. Task 0160's
   final-ratio refresh proof closes the one-entry service bound.
5. **Complete (Tasks 0155–0158):** the dedicated VCLK boundary, every
   core/video crossing, internal/external noninterlaced/interlaced timing,
   completed screen-transfer request path, and DPYCTL.SRT graphics MTR/RTM
   path have direct/asynchronous-clock and physical-phase tests. Pixel data is
   emitted by attached VRAM, not by a TMS34010 pin, so external serial-memory
   behavior is outside the processor implementation gate.
6. **Complete (Tasks 0159–0160):** the Cyclone V adapter, Quartus 17 project,
   63-pin QSF, complete SDC, map/fit/assembly, multicorner setup/hold and I/O
   timing, CDC/metastability reporting, and fixed resource envelopes are
   validated by one deterministic command.
7. **Complete (Task 0160):** strict lint, all 147 self-checking simulations,
   the clean real Quartus flow, and the final spec/documentation audit pass.

All seven historical baseline gates are satisfied. They do not supersede the
Task 0161 GPU findings or establish production-revision GPU completion. The
new ordered gate is Task 0162 through Task 0174 in `tasks.md`; Task 0174 may
restore the scoped GPU-complete claim only after every predecessor passes.
Task evidence is recorded in `tasks.md`, `changelog.md`, and
`fpga/IMPLEMENTATION_EVIDENCE.md`.
