# TMS34010_sv

A synthesizable SystemVerilog reimplementation of the Texas Instruments
TMS34010 Graphics System Processor, initially targeting Intel/Altera Cyclone V.
This is FPGA RTL, not a software emulator.

## Current status

Functional implementation work is complete through Task 0123, and the strict
whole-repository validation baseline is complete through Task 0119. The
repository currently contains:

- a multicycle 32-bit core with bit-addressed instruction and data access;
- A/B register files, shared stack pointer, status register, ALU, shifter,
  multiplier, and multicycle divider;
- the instruction families tracked in `docs/instruction_coverage.md`, including
  field-aware MOVE, stack/trap/interrupt operations, and conditional control;
- PIXT, FILL, PIXBLT, DRAV, and LINE graphics datapaths with pixel processing,
  plane masking, transparency, and all window modes;
- on-chip I/O-register storage plus maskable and nonmaskable interrupt entry;
- architectural reset and illegal-opcode vector entry;
- standalone video-timing and DRAM-refresh modules;
- 111 self-checking SystemVerilog testbenches.

This is not yet a complete FPGA system. The host/memory fabric, bus
arbitration, I/O side-effect completion, video/refresh integration, real
Quartus project/constraints, and timing/resource validation remain open.

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
- `scripts/` — lint, simulation, and Quartus entry points.
- `tasks.md` / `changelog.md` — task-level design and implementation history.
- `third_party/TMS34010_Info/` — pinned primary/reference documentation.
