# Completion audit

> Baseline: Task 0123, 111/111 self-checking benches passing with strict RTL
> lint clean. This ledger defines what “complete” still requires for the
> TMS34010-only scope in A0002.

## Official ISA reconciliation

The complete instruction-summary tables in the 1988 TMS34010 User's Guide
§12.3 (pages 12-12 through 12-18) were compared with
`docs/instruction_coverage.md` and `tms34010_decode.sv`. Every summary-table
row not listed below has a corresponding implemented coverage entry. This is
a functional reconciliation; original-silicon cycle counts remain part of the
physical timing work.

| Official row | Current state | Required closure |
|--------------|---------------|------------------|
| `ANDI IL,Rd` / `ANDNI IL,Rd` | One shared opcode is decoded, but the extension-word complement convention and Z-only flag behavior on pages 12-43/12-45 are not implemented correctly. | Correct the shared hardware operation, encode both source-level interpretations in tests, and resolve the affected part of A0009. |
| `CLR Rd` | The word is the `XOR Rd,Rd` alias and reaches the XOR datapath, but the current logical flag policy writes N/C/V contrary to page 12-51. | Correct logical flag masks and add an exact CLR alias test. |
| `DEC Rd` | The word is the `SUBK 1,Rd` alias and already executes through the tested SUBK datapath. | Add an explicit alias/encoding assertion and coverage row; no new execution datapath is expected. |
| `MOVE *Rs(offset),*Rd+ [,F]` | Not decoded or executed. | Add the two-word signed-offset memory-to-memory form and postincrement Rd by FS. |
| `MOVE @SAddress,*Rd+ [,F]` | Not decoded or executed. | Add the three-word absolute-source memory-to-memory form and postincrement Rd by FS. |
| `EMU` | Not decoded; the top level has no EMUA or RUN/EMU interface. | Define the FPGA-facing emulation-pin boundary, implement the RUN-as-NOP behavior and emulator-entry handshake, and test both sampled modes. |

The summary also exposed that “implemented” does not yet mean
spec-verified for every flag. A0009 and A0011 still describe provisional
policies; the ANDI/ANDNI and CLR pages already prove concrete discrepancies.
The remaining logical, move, immediate, and unary rows must be checked against
their individual status-bit tables before ISA closure is claimed.

## Active architectural assumptions requiring closure

These assumptions affect observable compatibility and must be resolved by
primary-spec evidence plus tests, or retained as an explicit project-level
deviation:

- A0005: exact field alignment and cross-boundary behavior at the physical
  memory interface.
- A0009: per-instruction N/C/Z/V write masks.
- A0011: MOVI status behavior.
- A0013 and A0019: K=0 interpretation for constant and shift families.
- A0025: REV value and EXGPC alignment.
- A0027: SUBXY comparison signedness.
- A0029: FILL XY DADDR writeback representation.

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
2. Implement and directly test the two missing MOVE forms and EMU behavior;
   ensure every §12.3 row has a spec citation and named test.
3. Complete I/O side effects and every interrupt source.
4. Land the physical memory, refresh, host, and arbitration fabric with
   wait-state/reset tests.
5. Integrate video/display memory and CDC with frame-level tests.
6. Land the Cyclone V project and close synthesis, fit, setup, and hold.
7. Run strict lint, every self-checking simulation, the real Quartus flow,
   and a final spec/documentation audit from a clean worktree.

The project is complete only when all seven gates are satisfied and their
evidence is recorded in `tasks.md` and `changelog.md`.
