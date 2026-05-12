# Changelog

All notable changes to this project will be documented here.
Dates are ISO 8601. Each completed task should add at least one entry.

## Unreleased

## 2026-05-12

### Added
- Added `https://github.com/birdybro/TMS34010_Info` as a git submodule under
  `third_party/TMS34010_Info`, pinned at commit `0f5094bf`. This is the
  authoritative specification source — the 1988 TMS34010 User's Guide and
  the SPVS002C datasheet inside it are the primary references for all RTL
  decisions.
- Added project planning files: `tasks.md`, `changelog.md`.
- Added documentation scaffolds: `docs/architecture.md`,
  `docs/assumptions.md`, `docs/instruction_coverage.md`,
  `docs/timing_notes.md`, `docs/memory_map.md`. All marked as scaffolds with
  unimplemented sections explicitly flagged.
- Added build/sim/lint launcher scripts under `scripts/`.
- Added `CLAUDE.md` describing project conventions for future Claude Code
  sessions (RTL style, spec workflow, doc requirements, git workflow).
- Added `.gitignore` for simulator work directories and synthesis output.
- Added `rtl/tms34010_pkg.sv` with `ADDR_WIDTH`, `DATA_WIDTH`,
  `FIELD_SIZE_WIDTH`, and the `core_state_t` typed enum.
- Added `rtl/core/tms34010_core.sv` — Phase 0 skeleton: single sequential
  always_ff for state, single always_comb for next-state + memory IF
  outputs with safe defaults, observability `state_o` port. CORE_RESET →
  CORE_FETCH on first clock after reset; CORE_FETCH asserts `mem_req`
  with 16-bit field size and waits for `mem_ack`.
- Added `sim/tb/tb_smoke.sv` — drives reset for 3 cycles, releases,
  watches the FSM advance to CORE_FETCH within 8 cycles, checks
  `mem_req` is asserted there. Prints `TEST_RESULT: PASS`/`FAIL` for
  the `scripts/sim.sh` grep-based pass/fail check.
- Updated `scripts/sim.sh` to capture transcript and grep for
  `TEST_RESULT: PASS` (vsim batch exit code is unreliable for test
  status).
- Added `rtl/core/tms34010_pc.sv` — bit-addressed program counter with
  parameterized `RESET_VALUE`, absolute-load port, and forward-advance
  port measured in bits. Single `always_ff` + single `always_comb` with
  safe defaults; no `/`, no `%`, no implicit-width adds.
- Extended `rtl/tms34010_pkg.sv` with `INSTR_WORD_BITS = 6'd16`,
  `PC_ADVANCE_WIDTH = 8`, and `RESET_PC` (placeholder until Phase 8
  resolves the architectural reset-vector fetch sequence — see
  assumption A0008).
- Added `sim/tb/tb_pc.sv` — unit test covering reset, hold-when-idle,
  single advance by `INSTR_WORD_BITS`, cumulative advances, absolute
  load, and load-wins-over-advance precedence.
- Added `docs/assumptions.md` entry A0008 (reset-vector deferral).

### Changed
- `rtl/core/tms34010_core.sv` now instantiates `tms34010_pc`, drives
  `mem_addr` from `pc_o`, and asserts `pc_advance_en` for one cycle on
  `mem_ack` in `CORE_FETCH`. New observability port `pc_o` on the core.
- `sim/tb/tb_smoke.sv` consumes the new `pc_o` and additionally asserts
  that `mem_addr === pc_o` while in `CORE_FETCH`.
- `scripts/sim.sh` discovers all `rtl/**/*.sv` sources automatically
  (package first, then everything else, then the TB), so new modules
  don't require editing the script.

### Fixed
- N/A

### Known Limitations
- No register file, decode, or execute yet. The CORE_DECODE / EXECUTE /
  MEMORY / WRITEBACK arms of the FSM return to CORE_FETCH and have no
  side effects.
- The PC starts at the placeholder `RESET_PC = '0`; the architecturally-
  correct reset-vector fetch is Phase 8 work (assumption A0008).
- No branches/jumps yet, so the PC's `load_en` is currently tied 0 at
  the core boundary. The port is wired and tested in `tb_pc`.
- Smoke + tb_pc pass with Intel ModelSim ASE 17.0. Questa FSE 25.1.1
  on this dev box errors out on a license check
  (`SALT_LICENSE_SERVER` not configured); functionally equivalent for
  SystemVerilog compile + run.
- No FPGA synthesis flow yet beyond a placeholder script.
