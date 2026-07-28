# TMS34010_sv

A synthesizable SystemVerilog reimplementation of the Texas Instruments
TMS34010 Graphics System Processor, initially targeting Intel/Altera Cyclone V.
This is FPGA RTL, not a software emulator.

## Current status

Functional implementation work is complete through Task 0129. Task 0124
reconciled the official instruction summary and all remaining system
integration work into `docs/completion_audit.md`; Task 0125 closed the
logical-status and ANDI/ANDNI semantic findings, and Tasks 0126–0127 landed
the two missing memory-to-memory MOVE forms. Task 0128 implemented the EMU
handshake and completed every row in the official instruction summary. Task
0129 corrected the MOVK/ADDK/SUBK encoded-zero constant to the specified
value 32. The repository currently contains:

- a multicycle 32-bit core with bit-addressed instruction and data access;
- A/B register files, shared stack pointer, status register, ALU, shifter,
  multiplier, and multicycle divider;
- the instruction families tracked in `docs/instruction_coverage.md`, including
  field-aware MOVE, stack/trap/interrupt operations, and conditional control;
- PIXT, FILL, PIXBLT, DRAV, and LINE graphics datapaths with pixel processing,
  plane masking, transparency, and all window modes;
- on-chip I/O-register storage plus maskable and nonmaskable interrupt entry;
- architectural reset and illegal-opcode vector entry;
- RUN/EMU sampling, active-low EMUA acknowledgement, halt, and resume;
- standalone video-timing and DRAM-refresh modules;
- 115 self-checking SystemVerilog testbenches.

This is not yet a complete FPGA system. The audit records the remaining ISA
verification work plus the host/memory fabric, bus arbitration, I/O side-
effect completion, video/refresh integration, real Quartus project/
constraints, and timing/resource validation.

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

- `rtl/` — synthesizable package, core, I/O, video, and refresh RTL.
- `sim/models/` — nonsynthesizable behavioral memory model.
- `sim/tb/` — focused self-checking testbenches.
- `docs/` — architecture, assumptions, coverage, memory/timing notes, and the
  authoritative Cyclone V HDL coding-guideline bundle.
- `docs/completion_audit.md` — primary-spec reconciliation and ordered exit
  gates for project completion.
- `scripts/` — lint, simulation, and Quartus entry points.
- `tasks.md` / `changelog.md` — task-level design and implementation history.
- `third_party/TMS34010_Info/` — pinned primary/reference documentation.
