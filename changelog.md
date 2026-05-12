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
- Added `sim/models/sim_memory_model.sv` — non-synthesizable behavioral
  memory with two-state mini-FSM, one-cycle ack pulse, and a guard
  against re-latching while still driving an ack (the producer's
  `mem_req` is combinational from a state register that NBA-updates
  the cycle after, so on the ack cycle `mem_req` is still high
  for one delta-cycle).
- Added `sim/tb/tb_fetch_walk.sv` — end-to-end fetch-loop test
  connecting `tms34010_core` to `sim_memory_model`. Preloads 8 words,
  watches every ack with an active-region monitor, and verifies the
  full handshake: address tracks PC, PC advances by `INSTR_WORD_BITS`
  on each ack, `mem_size` matches, `mem_rdata` low 16 bits match the
  preloaded word and high 16 bits are zero, and the final PC commits
  to `N*16`.
- Added `rtl/core/tms34010_regfile.sv` — A0..A14 + B0..B14 + shared SP
  (aliased as A15/B15). Two combinational read ports, one synchronous
  write port, sync active-high reset clears all entries. SP aliasing
  centralized in the read/write decode so callers never deal with it.
  Package gains `reg_file_t`, `reg_idx_t`, and `REG_SP_IDX`.
- Added `sim/tb/tb_regfile.sv` — coverage: reset clears all 31 slots,
  per-file isolation (A vs B), SP aliasing (write A15 visible via B15
  and `sp_o`), independent read ports, synchronous-write contract
  (same-cycle read returns old value, next-cycle read returns new).
- Added `rtl/core/tms34010_alu.sv` — purely combinational 32-bit ALU
  with operations ADD, ADDC, SUB, SUBB, CMP, AND, ANDN, OR, XOR, NOT,
  NEG, PASS_A, PASS_B. Produces a 32-bit result and an `alu_flags_t`
  struct (N, C, Z, V). Arithmetic ops use a single 33-bit adder for
  carry extraction (`{cout, sum} = a + b + cin`) and the symmetric
  subtractor form (`a + ~b + 1`) for SUB/SUBB/CMP/NEG.
- Added package types `alu_op_t` and `alu_flags_t`.
- Added `sim/tb/tb_alu.sv` — per-operation vectors covering normal,
  zero-result, negative-result, unsigned-carry and signed-overflow
  edge cases. PASS on ModelSim ASE 17.0.
- Added `docs/assumptions.md` A0009 covering the ALU flag-update
  convention until SPVU001A Appendix A is read per-instruction.
- Added `rtl/core/tms34010_shifter.sv` — purely combinational 32-bit
  barrel shifter. Operations: SLL, SLA (same output as SLL in Phase 2;
  the V-on-sign-change quirk is tracked in A0009), SRL, SRA (signed
  `>>>`), RL, RR. amount == 0 is identity (no shifts evaluated for
  flags). Output reuses `alu_flags_t` with V tied 0 for now.
- Added package types `shift_op_t` and `SHIFT_AMOUNT_WIDTH = 5`.
- Added `sim/tb/tb_shifter.sv` — covers amount==0 identity per op,
  small/large shift amounts, the half-word swap on rotate by 16,
  signed extension on SRA, carry from MSB on left shifts/rotates,
  carry from LSB on right shifts/rotates.
- Added `rtl/core/tms34010_status_reg.sv` — 32-bit ST register.
  Update priority: reset → 0, then `st_write_en` (full POPST-style
  write) wins, then `flag_update_en` (selective N/C/Z/V update from
  `alu_flags_t`) updates only the four flag bits and preserves the
  other 28. Exposes named outputs `n_o`/`c_o`/`z_o`/`v_o`.
- Added package parameters `ST_N_BIT/ST_C_BIT/ST_Z_BIT/ST_V_BIT` as
  placeholder bit positions for the four flags, plus assumption A0010
  for the rest of the ST bit layout (deferred to SPVU001A Ch. 2 read).
- Added `sim/tb/tb_status_reg.sv` — reset, selective flag update,
  full ST write, non-flag-bit preservation across selective updates,
  precedence (st_write wins over flag_update).
- Added `rtl/core/tms34010_decode.sv` — Phase 3 combinational decode
  skeleton. Currently flags every 16-bit encoding as ILLEGAL; SPVU004
  opcode-chart rows populate in Task 0011 onwards (one instruction
  per task, each citing the chart row).
- Added package types `instr_word_t` (alias for `logic [15:0]`),
  `instr_class_t` (4-bit enum, currently only `INSTR_ILLEGAL`),
  `decoded_instr_t` (packed `{illegal, iclass}`), and constant
  `INSTR_WORD_WIDTH = 16`.
- Added `sim/tb/tb_illegal_opcode.sv` — preloads memory, runs the
  core, verifies (a) `illegal_opcode_o` is 0 during reset, (b) the
  sticky illegal latch asserts after the first CORE_DECODE, (c)
  remains high (stickiness), (d) `instr_word_o` carries the
  preloaded value `0xDEAD` from the first decode, (e) the PC has
  advanced past reset value.
- Added `initial` block to `sim_memory_model` to zero the backing
  store so tests that don't preload every fetched address see 0,
  not X. Also switched the memory model from `always_ff` to plain
  `always` since `initial` and `always_ff` cannot both write to the
  same array under SV-2009.
- First real instruction: **MOVI IW K, Rd** (move 16-bit sign-extended
  immediate to register). Encoding `0x09C0 | (R<<4) | N` (per A0012);
  flag effects N/Z from result, C/V cleared (per A0011). End-to-end:
  decoder recognizes the pattern, FSM fetches the 16-bit immediate
  word from a new CORE_FETCH_IMM_LO state, ALU PASS_B routes through
  to regfile write, ST flag-update fires on writeback.
- Added `sim/tb/tb_movi.sv` — 5 MOVI IW instructions covering a mix
  of A-file and B-file destinations and immediate values exercising
  N/Z flag semantics (positive, all-ones, zero, max positive, min
  negative sign-extended). Verifies each register value via
  hierarchical reference and the final ST flag bits.
- Added `docs/assumptions.md` A0011 (MOVI flag-update convention)
  and A0012 (MOVI IW encoding extracted from SPVU004 listings).
- Added first real row to `docs/instruction_coverage.md` for MOVI
  IW; placeholder row for MOVI IL until Task 0013.
- Second instruction: **MOVI IL K, Rd** (move 32-bit immediate to
  register). Encoding `0x09E0 | (R<<4) | N` (A0012); 32-bit immediate
  stored as two 16-bit words in memory (low half first, then high).
  Exercises the existing `CORE_FETCH_IMM_HI` state and the
  `imm32 = {imm_hi_q, imm_lo_q}` assembly path. Reuses the same
  ALU PASS_B and writeback logic as MOVI IW; only one new arm in the
  decoder.
- Added `sim/tb/tb_movi_il.sv` — 5 MOVI IL instructions with
  immediates that the IW form physically cannot encode (0xCAFE_BABE,
  0xDEAD_BEEF, 0x0000_FFFF, 0xFFFF_0000, 0x0000_0000).
- Third instruction: **MOVK K, Rd** (move 5-bit constant). Encoding
  `0x1800 | (K<<5) | (R<<4) | N` (A0013); single-word; **does not
  affect ST** per SPVU004. Adds `k5` field to `decoded_instr_t` and a
  new arm to the alu_b mux that zero-extends K to 32 bits.
- Added `sim/tb/tb_movk.sv` — 5 MOVK instructions covering K range
  edges (1, 31, 0, 16, 5) and verifying both regfile content and
  that ST is unchanged from reset zeros (confirming the "no flag
  update" contract).
- Added `docs/assumptions.md` A0013 covering MOVK encoding, the
  no-flag-effect contract, and the K=0 = literal-0 hypothesis.
- Fourth instruction (first arithmetic): **ADD Rs, Rd**. Encoding
  `0100 000S SSSR DDDD` from SPVU001A Appendix A page A-14
  (A0014/A0015). The TMS34010 reg-reg encoding shares a single R
  bit between Rs and Rd, so **Rs and Rd must be in the same file**
  for ADD and the rest of the reg-reg family. `decoded_instr_t` now
  includes `rs_idx`; the core's regfile rs1/rs2 selectors are driven
  from `decoded.rs_idx`/`decoded.rd_idx` (file shared).
- Added `sim/tb/tb_add_rr.sv` — 4 ADD RR cases: simple positive add,
  signed-overflow (0x7FFF_FFFF + 1 → 0x8000_0000 with N=1, V=1),
  unsigned wrap to zero (0xFFFF_FFFF + 1 → 0 with C=1, Z=1), and a
  B-file add (0x1111_1111 + 0x2222_2222 → 0x3333_3333) with all
  flags clear. Encoding helper independently verified against the
  hand-decoded `ADD A1,A2 → 0x4022`.
- Resolved encoding-source uncertainty: extracted SPVU001A page A-14
  via `pdftotext -layout` — this is the authoritative opcode chart
  for every '34010 instruction. Logged as A0014.
- Fifth instruction: **SUB Rs, Rd** (Rd - Rs → Rd). 7-bit prefix
  `7'b0100010` from SPVU001A A-14. Added `alu_a` mux in the core
  that swaps operands for INSTR_SUB_RR so the ALU's natural `a - b`
  produces the spec-mandated `Rd - Rs`.
- Added `sim/tb/tb_sub_rr.sv` — five cases: simple positive, equal
  operands (Z=1), borrow (3-10 = -7 with C, N), signed-overflow
  (MIN_INT - 1 = MAX_INT with V), and a B-file SUB.

### Changed
- `rtl/core/tms34010_core.sv` now also instantiates `tms34010_regfile`,
  `tms34010_alu`, and `tms34010_status_reg`. Datapath wires connect
  ALU `result` to the regfile's `wr_data` port and ALU `flags` to the
  status register's `flags_in` port. Every control signal (`rf_wr_en`,
  `st_flag_update_en`, `st_write_en`) is tied 0 in this commit so no
  visible behavior changes; Task 0012 replaces those tie-offs with
  decoded-instruction-driven values for the first real instruction.
- `rtl/core/tms34010_core.sv` then: latches imm_lo_q in the new
  CORE_FETCH_IMM_LO state, drives the writeback path
  (`rf_wr_en = (state == CORE_WRITEBACK) && decoded.wb_reg_en`),
  selects `alu_b` from the assembled `imm32` when the decoded class is
  `INSTR_MOVI_*`. CORE_FETCH_IMM_HI state added in preparation for
  MOVI IL (Task 0013) but not yet reachable.
- `tms34010_pkg.sv` core_state_t enum widened to 3 bits and two new
  states added: CORE_FETCH_IMM_LO, CORE_FETCH_IMM_HI. `decoded_instr_t`
  extended with `rd_file`, `rd_idx`, `needs_imm16`, `needs_imm32`,
  `imm_sign_extend`, `alu_op`, `wb_reg_en`, `wb_flags_en`.
- `instr_class_t` adds INSTR_MOVI_IW (used) and INSTR_MOVI_IL
  (reserved, decoded but currently routed to ILLEGAL).
- `rtl/core/tms34010_core.sv` now instantiates `tms34010_pc`, drives
  `mem_addr` from `pc_o`, and asserts `pc_advance_en` for one cycle on
  `mem_ack` in `CORE_FETCH`. New observability port `pc_o` on the core.
- `rtl/core/tms34010_core.sv` now also: (a) latches the fetched
  instruction word into `instr_word_q` on `mem_ack` in `CORE_FETCH`,
  (b) instantiates `tms34010_decode`, (c) walks the full FSM
  `CORE_FETCH → CORE_DECODE → CORE_EXECUTE → CORE_WRITEBACK → CORE_FETCH`
  (no instruction reaches `CORE_MEMORY` yet), and (d) maintains a
  sticky `illegal_q` latch set when a CORE_DECODE sees
  `decoded.illegal = 1`. Two new observability ports `instr_word_o`
  and `illegal_opcode_o`.
- `sim/tb/tb_smoke.sv` consumes the new `pc_o` and additionally asserts
  that `mem_addr === pc_o` while in `CORE_FETCH`.
- `scripts/sim.sh` discovers all `rtl/**/*.sv` and `sim/models/**/*.sv`
  sources automatically (package first, then RTL, then behavioral
  models, then the TB).

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
