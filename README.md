# TMS34010_sv

A synthesizable SystemVerilog reimplementation of the Texas Instruments
TMS34010 Graphics System Processor, initially targeting Intel/Altera Cyclone V.
This is FPGA RTL, not a software emulator.

## Current status

Functional implementation work is complete through Task 0137. Task 0124
reconciled the official instruction summary and all remaining system
integration work into `docs/completion_audit.md`; Task 0125 closed the
logical-status and ANDI/ANDNI semantic findings, and Tasks 0126–0127 landed
the two missing memory-to-memory MOVE forms. Task 0128 implemented the EMU
handshake and completed every row in the official instruction summary. Task
0129 corrected the MOVK/ADDK/SUBK encoded-zero constant to the specified
value 32. Task 0130 corrected all shift encodings, SLA overflow, and
per-instruction status masks. Task 0131 corrected MOVI C preservation for
both immediate widths. Task 0132 resolved the REV value and EXGPC alignment
rules directly against their individual instruction pages. Task 0133 resolved
FILL XY's final linear DADDR writeback and W=0 status preservation. Task
0134 corrected SUBXY's coordinate comparisons to signed 16-bit
semantics. Task 0135 completed the primary-page instruction status audit,
resolved A0009, corrected divide/modulo and odd-result multiply edge cases,
and completed W=3/PIXT graphics-window status behavior. Task 0136 resolved
the remaining field-alignment assumption and added exact
specification-derived sequencing from 1–32-bit architectural fields onto
aligned 16-bit physical words. Task 0137 implemented the source-specific
INTPEND/INTENB contract, synchronized both active-low external interrupt
pins, and exposed synchronous host/display request sidebands. The repository
currently contains:

- a multicycle 32-bit core with bit-addressed instruction and data access;
- A/B register files, shared stack pointer, status register, ALU, shifter,
  multiplier, and multicycle divider;
- the instruction families tracked in `docs/instruction_coverage.md`, including
  field-aware MOVE, stack/trap/interrupt operations, and conditional control;
- PIXT, FILL, PIXBLT, DRAV, and LINE graphics datapaths with pixel processing,
  plane masking, transparency, and all window modes;
- on-chip I/O-register storage plus every maskable pending-source boundary
  and maskable/nonmaskable entry path;
- architectural reset and illegal-opcode vector entry;
- RUN/EMU sampling, active-low EMUA acknowledgement, halt, and resume;
- a synthesizable field-to-word sequencer covering §4.1 alignment cases A–G,
  partial-word RMW locking, and arbitrary word-side stalls;
- standalone video-timing and DRAM-refresh modules;
- 123 self-checking SystemVerilog testbenches, including an exhaustive
  65,536-opcode static status-policy sweep.

This is not yet a complete FPGA system. ISA/status reconciliation is complete;
the audit records the remaining pin-level local-bus controller, host/memory
fabric, bus arbitration, remaining I/O/host side effects, video/refresh
integration, real Quartus project/constraints, and timing/resource validation.

## Getting started

```sh
git submodule update --init --recursive
scripts/lint.sh
scripts/regress.sh
scripts/sim.sh tb_smoke
scripts/sim.sh tb_pixt_win
```

The scripts prefer Questa/ModelSim and fall back to Verilator. Testbenches must
print `TEST_RESULT: PASS`; the simulator exit code alone is not treated as a
pass. `scripts/regress.sh` discovers and runs all testbenches; set
`REGRESS_JOBS` to parallelize the Verilator flow. `scripts/synth_quartus.sh` is
still a placeholder and does not perform a real synthesis or timing run.

Before changing RTL, read [AGENTS.md](AGENTS.md), [tasks.md](tasks.md),
[architecture.md](docs/architecture.md), and the relevant specification in the
pinned `third_party/TMS34010_Info` submodule.

## Repository map

- `rtl/` — synthesizable package, core, memory sequencing, I/O, video, and
  refresh RTL.
- `sim/models/` — nonsynthesizable behavioral memory model.
- `sim/tb/` — focused self-checking testbenches.
- `docs/` — architecture, assumptions, coverage, memory/timing notes, and the
  authoritative Cyclone V HDL coding-guideline bundle.
- `docs/completion_audit.md` — primary-spec reconciliation and ordered exit
  gates for project completion.
- `docs/status_audit.md` — complete individual-instruction N/C/Z/V policy,
  undefined-bit handling, and regression evidence.
- `scripts/` — lint, simulation, and Quartus entry points.
- `tasks.md` / `changelog.md` — task-level design and implementation history.
- `third_party/TMS34010_Info/` — pinned primary/reference documentation.
