# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Synthesizable FPGA reimplementation of the Texas Instruments TMS34010 Graphics System Processor in SystemVerilog. Initial target is Intel/Altera Cyclone V. This is **RTL, not a software emulator** — write explicit hardware structure (datapaths, muxes, FSMs, register stages), not procedural "software in HDL".

## Specification source of truth

`third_party/TMS34010_Info/` (git submodule, pinned). Authoritative documents:

- `docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf` — ISA and architecture.
- `docs/datasheets/SPVS002C_TMS34010_Graphics_System_Processor_199106_altscan.pdf` — electrical / pin-level timing.
- `docs/ti-official/TMS34061_Users_Guide.pdf` — VRAM/CRTC companion.
- `emulation/mame/UPSTREAM.md` — behavioral cross-check **only**; do not copy emulator structure into RTL.

Do **not** use the older `TMS34010_docs` repo.

Every implementation decision must cite a section/page/file from this submodule. If you cannot, the assumption goes into `docs/assumptions.md` with a `TODO/spec-uncertain` marker and is isolated behind a clear module boundary.

## Project navigation

- `tasks.md` — current milestone, full task list, acceptance criteria, commit hashes. **Update before every commit.**
- `changelog.md` — dated entries. **Update before every commit.**
- `docs/architecture.md` — module map, datapath/control strategy, planned vs. implemented status.
- `docs/assumptions.md` — every non-spec-derived decision, dated.
- `docs/instruction_coverage.md` — per-instruction status table. **Never silently stub** — if decode recognizes but execute doesn't, mark it `decoded, traps as illegal`.
- `docs/timing_notes.md` — long paths, multi-cycle ops, FPGA timing.
- `docs/memory_map.md` — bit-addressed memory model, I/O register table.
- `rtl/tms34010_pkg.sv` — single home for architectural constants and typedefs (no magic numbers elsewhere).

## Build / sim / lint

Local dev box has Questa FSE 25.1.1 at `/c/altera_pro/25.1.1/questa_fse/win64/` and ModelSim ASE 17.0 at `/c/intelFPGA_lite/17.0/modelsim_ase/win32aloem/`. Scripts find them via `$VLOG`/`$VSIM`/`$VLIB` env vars or PATH.

```
scripts/sim.sh <tb_name>     # compile pkg + rtl + sim/tb/<tb_name>.sv, run, expect "PASS"
scripts/lint.sh              # vlog compile-only sweep over rtl/
scripts/synth_quartus.sh     # Cyclone V Quartus check (placeholder until rtl/ is meaningful)
```

Scripts are bash; on Windows run them from git-bash. They exit non-zero with a clear message if the toolchain is missing — they do not silently pass.

## Workflow (mandatory)

One task → one commit. Before each commit:

1. Inspect `tasks.md`; pick one small task; state objective.
2. Read the relevant section(s) of the spec in `third_party/TMS34010_Info/`.
3. Implement.
4. Add or update tests under `sim/tb/`. Tests must be self-checking with explicit `PASS`/`FAIL` output, not waveform-only.
5. Run `scripts/lint.sh` and the relevant `scripts/sim.sh <tb>`.
6. Update `docs/*` for anything the task changed (architecture, assumptions, coverage, timing, memory map).
7. Update `tasks.md` — mark status, fill commit hash after pushing.
8. Update `changelog.md`.
9. `git status` → `git add <files>` → `git commit` → `git push`.
10. Re-run `git status` and confirm clean.
11. Edit `tasks.md` to record the commit hash, amend if needed (or add a follow-up note).

If push fails (auth/network), commit locally and report the block explicitly. Do not claim success.

## SystemVerilog rules (synthesizable RTL)

**Use**: `logic`, `always_ff` + nonblocking for sequential state, `always_comb` + blocking with safe defaults for combinational, `typedef enum logic [N:0]` for FSM states, `typedef struct packed`, `package`, explicit parameters, explicit widths, named constants from `rtl/tms34010_pkg.sv`, small composable modules.

**Forbid in RTL**: `#delay`, `force`/`release`, `fork/join`, classes, dynamic arrays, queues, DPI, file I/O, randomization, simulation system tasks, unbounded `while`, runtime-variable loops, `initial` blocks (except documented FPGA ROM/RAM init), unsynthesizable assertions inside RTL.

**FSMs**: typed enum, explicit reset state, default transition, safe handling of invalid states, state register and next-state logic separated.

**No `/` or `%`** unless (a) divisor is a compile-time power of two implemented as shift/mask, or (b) it lives in a dedicated multi-cycle divider module with documented latency, resources, and tests.

**No accidental latches, no combinational loops, no hidden CDC.** Any clock-domain crossing wraps in a clearly-named CDC module and gets flagged in `docs/timing_notes.md`.

**FPGA memory**: large memories go through `rtl/fpga/bram_*.sv` wrappers. Read latency is documented at the top of each wrapper. The rest of the RTL never assumes combinational read.

**Graphics ops** (PIXBLT, FILL, LINE, etc.) are hardware datapaths + FSMs with counters, explicit memory transactions, and busy/done signals. **Never** a software-style loop in one big combinational block.

## Before writing a new module

State in plain text first: purpose, ports, internal registers, combinational paths, FSM states, expected FPGA resources, RAM/ROM inference, latency, throughput, reset behavior, the User's Guide section it implements, and the tests that will cover it. Then write the smallest useful synthesizable implementation.

After writing, review as an FPGA synthesis engineer: latches, combinational loops, long paths, `/`/`%`, runtime loops, missing resets, blocking/nonblocking misuse, poor RAM inference, magic numbers, missing spec cite, missing tests. Fix or document.

## Reporting after each task

```
Task completed:
- <task name>

Summary:
- <what changed>

Files changed:
- <file list>

Tests:
- <tests run and result>

Documentation:
- <docs updated>

Git:
- Commit: <hash>
- Push: <success/failure and reason>

Known limitations:
- <remaining gaps>

Next recommended task:
- <next small task>
```

Do not claim success if commit or push failed. Do not claim compatibility unless verified against the spec.
