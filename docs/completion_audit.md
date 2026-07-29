# Completion audit

> Baseline: functional implementation through Task 0138, with strict RTL
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

## Active architectural assumptions requiring closure

No active architectural compatibility assumption remains. New uncertainty
found during the remaining system integration must still be resolved by
primary-spec evidence plus tests or retained as an explicit project-level
deviation.

A0003 (synchronous active-high FPGA reset), A0004 (single initial core
clock), and A0006 (functional-first timing) are intentional design choices.
They do not excuse missing architectural state or interface behavior; any
remaining difference at final sign-off must be documented as a deliberate
non-pin-compatible boundary.

## System integration gaps

### I/O and interrupt sources

- Complete counter-driven, write-to-clear, set-by-hardware, and host-visible
  behavior for all I/O registers. Current storage is only partially
  specialized.
- Connect the display timing pulse to the landed INTPEND.DI sideband and
  drive HCOUNT/VCOUNT/DPYADR from the video subsystem.
- Connect the host interface to the landed HSTCTLL.INTIN/HIP sideband and
  complete the complementary host-visible HSTCTL semantics.
- Replace the provisional external-ack dependency for on-chip I/O accesses
  with the final bus/controller contract.

### Memory, refresh, and host fabric

- Connect the landed field sequencer to an original-pin local memory-cycle
  controller: row/column/address/data phases, LRDY-controlled waits, and the
  eight post-reset RAS-only initialization cycles.
- Add arbitration among CPU/graphics, display, refresh, and host clients with
  specification-derived priority and request-hold rules.
- Service the exported refresh request in the local-memory arbiter/controller,
  retaining or acknowledging requests through contention and issuing the
  selected RAS-only or CAS-before-RAS cycle.
- Implement the host interface, host-direct/indirect accesses, HCS-selected
  reset halt, HLT behavior, HRDY/HINT signaling, and CDC where host timing is
  asynchronous.

### Video/display

- Integrate I/O timing registers with `tms34010_video`.
- Add display-address generation, VRAM serial-transfer/display-memory
  behavior, pixel output, and arbitration against CPU/graphics traffic.
- Define the pixel/video clock boundary and implement/document every CDC.

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
3. Complete I/O side effects and every interrupt source.
4. Land the pin-level local memory controller, refresh, host, and arbitration
   fabric with LRDY/reset tests. Task 0136 has completed its field-to-word
   sequencing prerequisite.
5. Integrate video/display memory and CDC with frame-level tests.
6. Land the Cyclone V project and close synthesis, fit, setup, and hold.
7. Run strict lint, every self-checking simulation, the real Quartus flow,
   and a final spec/documentation audit from a clean worktree.

The project is complete only when all seven gates are satisfied and their
evidence is recorded in `tasks.md` and `changelog.md`.
