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

### Changed
- N/A

### Fixed
- N/A

### Known Limitations
- The core is a Phase 0 skeleton only — no PC, no register file, no decode,
  no execute. The CORE_DECODE/EXECUTE/MEMORY/WRITEBACK arms of the FSM
  return to CORE_FETCH and have no side effects.
- Smoke test passes with Intel ModelSim ASE 17.0. Questa FSE 25.1.1 on
  this dev box errors out on a license check (`SALT_LICENSE_SERVER` not
  configured); functionally equivalent for SystemVerilog compile + run.
- No FPGA synthesis flow yet beyond a placeholder script.
