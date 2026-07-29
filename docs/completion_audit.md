# Completion audit

> Baseline: functional implementation through Task 0157, with strict RTL
> lint clean. This ledger defines what “complete” still requires for the
> TMS34010-only scope in A0002.

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

## Active architectural assumptions requiring closure

No active architectural compatibility assumption remains. New uncertainty
found during the remaining system integration must still be resolved by
primary-spec evidence plus tests or retained as an explicit project-level
deviation.

A0003 (synchronous active-high FPGA reset), A0004 (explicit project clock
domains), A0006 (functional-first timing), and A0034 (video timing and
synchronization) are intentional design choices. A0035
isolates deterministic collision/undefined behavior around the screen-refresh
handshake, A0036 isolates the direct synchronous host boundary and
otherwise-unpredictable simultaneous high-byte write choice, and A0037
isolates host-engine collisions and the pre-pin synchronous protocol. A0038
isolates the one-entry DRAM-refresh retention bound until the physical
controller proves service before the next interval. A0039 records the 8×
phase representation, synchronous-reset phase origin, deterministic
undefined LAD value, and explicit CDC boundary. A0040 records the MCP's
one-outstanding/common-reset contract and pending Quartus constraint proof.
A0041 records physical HOLD's synchronized level handshake and phased
output-enable implementation. A0042 records the one-outstanding EMU-event
handshake and phase-latched halt indication. A0043 records the asynchronous
host bundled-data/re-arm contract and FPGA I/O timing work. A0044 records the
reserved-location read-zero choice and REFCNT exception. A0045 records the
dedicated VCLK MCP/stopped-clock/active-edge/reset contract. A0046 records
interlaced phase recovery, counter-write priority, and equality-counter
programming requirements. A0047 records external-sync sampling, recognition,
fallback, field classification, direction, and final FPGA I/O choices. These
do not excuse missing architectural state or interface
behavior; any remaining difference at final sign-off must be documented as a
deliberate non-pin-compatible boundary.

## System integration gaps

### Memory and refresh fabric

- Validate the one-entry DRAM-refresh service bound under the final PLL clock
  ratio, external waits, and physical HOLD behavior.

### Video/display

- Add physical VRAM serial-transfer/display-memory behavior, pixel output,
  and arbitration against CPU/graphics traffic.
- Constrain and prove the VCLK phase, clock groups, MCP payload paths,
  external-sync input/output timing, and synchronizer recognition in the real
  Quartus project.

### FPGA realization

- Add the synthesizable FPGA top level and required memory/clock/CDC wrappers.
- Add a real Quartus project for `5CSEBA6U23I7`, QSF assignments, and SDC
  constraints.
- Make `scripts/synth_quartus.sh` run analysis/synthesis, fitting, and
  TimeQuest rather than tool discovery.
- Inspect and archive zero-warning synthesis, resource/inference, CDC, and
  nonnegative setup/hold reports. Simulation alone is not FPGA completion.

## Ordered exit gates

1. **Complete (Task 0135):** resolve all active ISA/status assumptions and
   correct discovered semantic mismatches.
2. **Complete (Tasks 0126–0128):** implement and directly test the two missing
   MOVE forms and EMU behavior; ensure every §12.3 row has a spec citation and
   named test.
3. **Complete (Tasks 0137, 0139, 0141–0144, 0149–0150, 0154):** complete
   I/O side effects and every interrupt source. Source-specific pending bits,
   live video/refresh/display registers, host ownership, completion-qualified
   processor/host I/O paths, and every documented reserved field/location now
   have direct tests. The defined SRT consumer remains in video gate 5;
   cache controls remain in the optional cache/cycle-accuracy
   scope.
4. **Complete (Tasks 0136, 0145–0153):** land the pin-level local memory
   controller, refresh, host, and arbitration fabric with LRDY/reset tests.
   Task 0136 completed field-to-word sequencing; Tasks 0145–0146 landed and
   integrated arbitration; Tasks 0147–0148 landed the 8× phase engine and
   coherent CDC/system path; Tasks 0149–0150 completed both on-chip I/O
   requesters; Tasks 0151–0152 completed HOLD and HLDA/EMUA; and Task 0153
   completed the asynchronous host pins, HRDY, and HD direction. The final
   PLL/SDC service-bound proof belongs to FPGA-realization gate 6.
5. **In progress (Tasks 0155–0157):** the dedicated VCLK boundary, every
   core/video crossing, internal/external noninterlaced/interlaced timing, and
   completed screen-transfer request path have direct/asynchronous-clock
   tests. Complete physical VRAM serial display/pixel output with frame-level
   tests.
6. Land the Cyclone V project and close synthesis, fit, setup, and hold.
7. Run strict lint, every self-checking simulation, the real Quartus flow,
   and a final spec/documentation audit from a clean worktree.

The project is complete only when all seven gates are satisfied and their
evidence is recorded in `tasks.md` and `changelog.md`.
