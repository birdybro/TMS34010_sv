# Completion audit

> Baseline: functional implementation through Task 0134, with strict RTL
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
A0009 and A0011 remain provisional outside that resolved logical subset.
Remaining move, immediate, arithmetic, and graphics status rows must still be
checked against their individual tables before ISA closure is claimed.

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

## Active architectural assumptions requiring closure

These assumptions affect observable compatibility and must be resolved by
primary-spec evidence plus tests, or retained as an explicit project-level
deviation:

- A0005: exact field alignment and cross-boundary behavior at the physical
  memory interface.
- A0009: per-instruction N/C/Z/V write masks.

A0003 (synchronous active-high FPGA reset), A0004 (single initial core
clock), and A0006 (functional-first timing) are intentional design choices.
They do not excuse missing architectural state or interface behavior; any
remaining difference at final sign-off must be documented as a deliberate
non-pin-compatible boundary.

## System integration gaps

### I/O and interrupt sources

- Complete read-only, write-to-clear, set-by-hardware, and host-visible
  behavior for all I/O registers. Current storage is only partially
  specialized.
- Add and synchronize the two external interrupt inputs and reflect their
  level-sensitive state in INTPEND.
- Connect display timing to DPYINT/INTPEND.DI and hardware-driven
  HCOUNT/VCOUNT/DPYADR.
- Replace the provisional external-ack dependency for on-chip I/O accesses
  with the final bus/controller contract.

### Memory, refresh, and host fabric

- Implement the original 16-bit physical memory-cycle controller, including
  bit-address translation, unaligned field phasing, wait states, and the eight
  post-reset RAS-only initialization cycles.
- Add arbitration among CPU/graphics, display, refresh, and host clients with
  specification-derived priority and request-hold rules.
- Integrate the standalone DRAM-refresh generator and expose REFCNT behavior.
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

1. Resolve all active ISA/status assumptions and correct discovered semantic
   mismatches.
2. **Complete (Tasks 0126–0128):** implement and directly test the two missing
   MOVE forms and EMU behavior; ensure every §12.3 row has a spec citation and
   named test.
3. Complete I/O side effects and every interrupt source.
4. Land the physical memory, refresh, host, and arbitration fabric with
   wait-state/reset tests.
5. Integrate video/display memory and CDC with frame-level tests.
6. Land the Cyclone V project and close synthesis, fit, setup, and hold.
7. Run strict lint, every self-checking simulation, the real Quartus flow,
   and a final spec/documentation audit from a clean worktree.

The project is complete only when all seven gates are satisfied and their
evidence is recorded in `tasks.md` and `changelog.md`.
