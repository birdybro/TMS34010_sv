# Tasks

## Current Milestone: Phase 3 — Instruction fetch/decode

## Task index

| ID | Title | Status |
|----|-------|--------|
| 0001 | Add TMS34010_Info reference submodule | complete |
| 0002 | Create project planning and docs scaffolding | complete |
| 0003 | Initial synthesizable core skeleton + smoke test | complete |
| 0004 | PC module + core integration | complete |
| 0005 | Behavioral memory model + fetch-walk test | complete |
| 0006 | A/B register file with shared SP | complete |
| 0007 | ALU + flag generation | complete |
| 0008 | Barrel shifter | complete |
| 0009 | Status register (ST) | complete |
| 0010 | Decode skeleton + full execute cycle | complete |
| 0011 | Wire datapath modules into core | complete |
| 0012 | Implement MOVI IW end-to-end | complete |
| 0013 | Implement MOVI IL end-to-end | complete |
| 0014 | Implement MOVK K, Rd | complete |
| 0015 | Implement ADD Rs, Rd | complete |
| 0016 | Implement SUB Rs, Rd | complete |
| 0017 | Reg-reg logical instructions (AND, ANDN, OR, XOR) | complete |
| 0018 | Implement CMP Rs, Rd | complete |
| 0019 | First branch — JRUC short | complete |
| 0020 | JRcc short conditional (UC, EQ, NE) | complete |
| 0021 | K-form arithmetic (ADDK, SUBK) | complete |
| 0022 | Single-reg unary ops (NEG, NOT) | complete |
| 0023 | Immediate arithmetic IW (ADDI, SUBI, CMPI) | complete |
| 0024 | K-form shifts (RL, SLA, SLL, SRA, SRL) | complete |
| 0025 | Immediate IL batch (ADDI/SUBI/CMPI/ANDI/ORI/XORI) | complete |
| 0026 | MOVE Rs, Rd (register-to-register) | complete |
| 0027 | JRcc unsigned compares (LO, LS, HI, HS) | complete |
| 0028 | NOP (No Operation) | complete |
| 0029 | ADDC / SUBB Rs, Rd (carry-chain reg-reg) | complete |
| 0030 | JRcc condition-code correction + signed compares | complete |
| 0031 | JRcc long form (16-bit displacement) | complete |
| 0032 | JUMP Rs (register-indirect jump) | complete |
| 0033 | DSJ / DSJEQ / DSJNE Rd, Address (decrement-and-jump family) | complete |
| 0034 | JAcc Address (absolute conditional jump) | complete |
| 0035 | DSJS Rd, Address (decrement-and-skip-jump short form) | complete |
| 0036 | ABS / NEGB Rd (complete the unary family) | complete |
| 0037 | BTST K/Rs + per-flag wb_flag_mask refactor | complete |
| 0038 | CLRC / SETC / GETST / PUTST (status-reg ops) | complete |
| 0039 | Shift Rs-form (SLA/SLL/SRA/SRL/RL with Rs amount) | in progress |

---

### Task 0001: Add TMS34010_Info reference submodule
Status: complete
Dependencies: none
Acceptance Criteria:
- `third_party/TMS34010_Info` exists as a git submodule.
- `git submodule status` reports the expected pinned commit.
- Reference contents have been inspected and the primary spec documents are identified.
Tests:
- `git submodule status` succeeds.
- Submodule HEAD matches the pinned commit recorded in `.gitmodules` / parent tree.
Docs:
- `docs/architecture.md` records the reference source.
- `docs/assumptions.md` records the spec-source-of-truth decision.
Commit:
- c8db96c

---

### Task 0002: Create project planning and docs scaffolding
Status: complete
Dependencies:
- Task 0001
Acceptance Criteria:
- `tasks.md` exists with current milestone, task list, and acceptance criteria template.
- `changelog.md` exists.
- `docs/architecture.md`, `docs/assumptions.md`, `docs/instruction_coverage.md`,
  `docs/timing_notes.md`, `docs/memory_map.md` exist as honest scaffolds — they
  describe what is *planned* and explicitly mark unimplemented sections.
- `scripts/sim.sh`, `scripts/lint.sh`, `scripts/synth_quartus.sh` exist as
  minimal launchers that locate the toolchain via env or PATH and fail
  clearly otherwise.
- `CLAUDE.md` reflects the actual project conventions (RTL style, spec
  workflow, doc requirements).
- `.gitignore` excludes simulator work directories and synthesis output.
Tests:
- N/A — documentation-only commit. Marked as documentation-only per project rules.
Docs:
- All of the above are themselves the documentation deliverable.
Commit:
- 676bdb6

---

### Task 0003: Initial synthesizable core skeleton + smoke test
Status: complete
Dependencies:
- Task 0002
Acceptance Criteria:
- `rtl/tms34010_pkg.sv` exists with the minimum widths/typedefs the skeleton
  needs (no invented architectural constants).
- `rtl/core/tms34010_core.sv` exists with explicit clock + active-high reset,
  a typed-enum core FSM (`CORE_RESET → CORE_FETCH`), and a clean memory
  request/valid interface stub.
- `sim/tb/tb_smoke.sv` drives reset, observes the FSM leaves `CORE_RESET`,
  and prints `SMOKE: PASS` / `SMOKE: FAIL` with `$finish`.
- `scripts/sim.sh tb_smoke` exits 0 when Questa or ModelSim is on PATH (or
  via `$VLOG`/`$VSIM` env), and exits with a clear "simulator not found"
  message otherwise — without claiming success.
- The skeleton infers no latches, no combinational loops, no `/` or `%`,
  and uses `always_ff` + nonblocking for sequential state and `always_comb`
  + blocking for combinational paths.
Tests:
- `tb_smoke` reaches `SMOKE: PASS` (FSM observed in `CORE_FETCH` within a
  bounded number of cycles after reset deassertion).
Docs:
- `docs/architecture.md` updated with the actual skeleton module list.
- `docs/instruction_coverage.md` unchanged — no instructions yet.
- `changelog.md` updated.
Commit:
- e65f6db

---

### Task 0004: PC module + core integration
Status: complete
Dependencies:
- Task 0003
Spec sources (citation policy A0007):
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/01-architecture.md`
  §"Datapath summary" — "PC is itself a bit address into instruction
  memory"; "Instructions are 16-bit-aligned half-words … PC … increments
  by 16 per fetch".
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/11-interrupts-reset.md`
  §"Reset" — reset vector lives in trap table at the top of address
  space (near `0xFFFFFFC0` per the bibliography, exact value pending
  SPVU001A Ch. 13). The reset *sequence* (fetch PC from vector, then
  resume normal fetch) is Phase 8 work.
Acceptance Criteria:
- `rtl/core/tms34010_pc.sv` exists as a parameterized bit-addressed PC
  register: `RESET_VALUE` parameter, `load_en`/`load_value` for absolute
  jump, `advance_en`/`advance_amount` for variable forward advance
  measured in bits. Single `always_ff`, single `always_comb` with safe
  defaults. No `/`, no `%`, no implicit width.
- `rtl/tms34010_pkg.sv` gains `INSTR_WORD_BITS = 6'd16` and a
  `PC_ADVANCE_WIDTH = 8` parameter (so the advance amount can express
  up to 31 bytes / 15 16-bit words per advance, covering 1- to 3-word
  instructions plus headroom).
- `rtl/core/tms34010_core.sv` instantiates the PC, drives `mem_addr`
  from `pc_o`, and asserts `advance_en` with `INSTR_WORD_BITS` when
  `mem_ack` arrives in `CORE_FETCH`. `load_en` is tied 0 (no
  branches/jumps yet).
- `sim/tb/tb_pc.sv` covers: reset value, single load, single advance,
  cumulative advances, load-while-advance precedence (load wins),
  no-op cycles (PC stable when neither `load_en` nor `advance_en`).
- `sim/tb/tb_smoke.sv` still passes after PC integration (no observable
  state change since `mem_ack` is tied 0 in the smoke harness).
- `docs/assumptions.md` gains an entry (A0008) for the reset-vector
  value and reset-fetch sequence deferral.
Tests:
- `scripts/sim.sh tb_pc` → `TEST_RESULT: PASS`.
- `scripts/sim.sh tb_smoke` → `TEST_RESULT: PASS` (regression).
- `scripts/lint.sh` → compile clean.
Docs:
- `docs/architecture.md` — PC row updated to "landed".
- `docs/assumptions.md` — A0008 entry added.
- `changelog.md`, `tasks.md`.
Commit:
- 244864d

---

### Task 0005: Behavioral memory model + fetch-walk test
Status: complete
Dependencies:
- Task 0004
Spec sources:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/01-architecture.md`
  §"Datapath summary" — 16-bit-aligned instruction words; PC is bit-
  addressed and increments by 16 per fetch.
Acceptance Criteria:
- `sim/models/sim_memory_model.sv` exists as a non-synthesizable
  behavioral memory: 16-bit-word backing store indexed by
  `mem_addr[IDX_WIDTH+3:4]`, two-state mini-FSM (`MEM_IDLE`/`MEM_ACK`)
  with a one-cycle ack pulse. Lives under `sim/models/` so it is
  never compiled into a synthesis flow.
- The model enforces the request/ack handshake: a new request is only
  accepted when `!mem_ack`, so the producer's "stale `mem_req` on the
  ack cycle" (a property of a synchronous req/valid protocol where
  `mem_req` is combinational from a state register that NBA-updates
  one cycle later) does not retrigger a duplicate latch.
- `sim/tb/tb_fetch_walk.sv` connects core to memory model, preloads
  8 instruction words, watches every ack via an active-region monitor,
  and verifies (a) `mem_addr === pc_o` at each ack, (b) PC sequence is
  `0, 16, 32, ..., 112`, (c) `mem_size === INSTR_WORD_BITS` at each
  ack, (d) `mem_rdata[15:0]` matches the preloaded word, (e)
  `mem_rdata[31:16] === 0` (zero-extension contract), (f) final PC =
  `N*16` after the ack-driven advance commits.
- `scripts/sim.sh` discovers `sim/models/*.sv` automatically.
Tests:
- `scripts/sim.sh tb_fetch_walk` → PASS.
- `scripts/sim.sh tb_smoke` → PASS (regression).
- `scripts/sim.sh tb_pc` → PASS (regression).
- `scripts/lint.sh` → clean.
Docs:
- `docs/architecture.md` — note the memory model substrate.
- `changelog.md`, `tasks.md`.
Commit:
- 2f6bdb9

---

### Task 0006: A/B register file with shared SP
Status: complete
Dependencies:
- Task 0003
Spec source:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/03-registers.md`
  §"General-purpose register files A and B":
  - Two banks, 15 32-bit registers each (A0..A14, B0..B14).
  - One shared SP, accessible from both files as A15/B15.
  - All 32 bits.
  - Graphics ops implicitly read the B file (Phase 7 work).
Acceptance Criteria:
- `rtl/core/tms34010_regfile.sv` exists. Storage: 15-entry A array,
  15-entry B array, single SP register. Two read ports (combinational
  / async read for FPGA distributed-RAM friendliness — regfile is
  ~1 Kb so block RAM is overkill). One synchronous write port.
- Selector encoding: 1-bit file select + 4-bit index. Index 4'hF on
  either file routes to the shared SP for both read and write.
- Synchronous active-high reset clears all entries (bounded for-loop,
  fully unrollable, no inferred latches).
- Observability `sp_o` port for testbenches.
- Package typedefs added: `reg_file_t` (enum A/B), `reg_idx_t` (4-bit).
- `sim/tb/tb_regfile.sv` covers reset, isolated A/B writes, read-after-
  write same and different ports, SP aliasing (write A15 → read B15
  returns the value, and `sp_o` matches), file-A and file-B index 15
  both alias to SP.
Tests:
- `scripts/sim.sh tb_regfile` → PASS.
- All previous tests still PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — regfile row → landed.
- `changelog.md`, `tasks.md`.
Commit:
- afc4381

---

### Task 0007: ALU + flag generation
Status: complete
Dependencies:
- Task 0006
Spec sources:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/02-instruction-set.md`
  §"Flag effects" (per-instruction flag list in SPVU001A Appendix A is
  authoritative).
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/03-registers.md`
  §"Status register" (N, C, Z, V from the ALU).
Acceptance Criteria:
- `rtl/core/tms34010_alu.sv` exists as a purely combinational module.
  Operations: ADD, ADDC, SUB, SUBB, CMP, AND, ANDN, OR, XOR, NOT,
  NEG, PASS_A, PASS_B. Output: 32-bit `result` + packed `alu_flags_t`
  (N, C, Z, V).
- One 33-bit adder + one 33-bit subtractor (a + ~b + cin) shared
  across all arithmetic ops — no per-op duplicated adders.
- Logical ops set C = V = 0 per the convention in A0009. Arithmetic
  ops use the standard two's-complement carry/borrow/overflow rules.
- Package gains `alu_op_t` (4-bit enum) and `alu_flags_t` (packed
  struct with n/c/z/v).
- `sim/tb/tb_alu.sv` covers every operation with at least 2-3 vectors,
  including the corner cases: signed-overflow on ADD, borrow on SUB,
  Z on ADD producing 0 via carry, V on NEG of MIN_INT.
Tests:
- `scripts/sim.sh tb_alu` → PASS.
- All previous tests still PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — ALU row → landed.
- `docs/assumptions.md` — A0009 entry added.
- `changelog.md`, `tasks.md`.
Commit:
- cae8f71

---

### Task 0008: Barrel shifter
Status: complete
Dependencies:
- Task 0007
Spec source:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/01-architecture.md`
  §"Top-level blocks" — "32-bit barrel shifter; the shifter is critical
  for field operations and pixel shifts".
- `02-instruction-set.md` lists SLA, SLL, SRA, SRL, RL as shift/rotate
  primitives.
Acceptance Criteria:
- `rtl/core/tms34010_shifter.sv` exists as a purely combinational
  module. Ops: SLL, SLA (alias of SLL for now), SRL, SRA, RL, RR.
  5-bit shift amount. Output: 32-bit result + `alu_flags_t` with V
  tied 0.
- amount==0 identity (result = a, C = 0).
- C semantics: SLL/SLA/RL use the MSB-departing bit `a[32 - amount]`;
  SRL/SRA/RR use the LSB-departing bit `a[amount - 1]`.
- Package: `shift_op_t` (3-bit enum) and `SHIFT_AMOUNT_WIDTH = 5`.
- `sim/tb/tb_shifter.sv` covers each op with identity (amount=0),
  small shift, large shift, rotate-by-16 half-word swap, sign-
  extension on SRA, MSB/LSB carry capture.
Tests:
- `scripts/sim.sh tb_shifter` → PASS.
- All previous tests still PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — shifter row → landed.
- `changelog.md`, `tasks.md`.
Commit:
- 08fae79

---

### Task 0009: Status register (ST)
Status: complete
Dependencies:
- Task 0007 (ALU produces alu_flags_t)
Spec source:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/03-registers.md`
  §"Status register".
Acceptance Criteria:
- `rtl/core/tms34010_status_reg.sv` exists. 32-bit ST. Update priority:
  reset → 0, then `st_write_en` (full POPST-style write), then
  `flag_update_en` (selective N/C/Z/V update via `alu_flags_t`).
- Bit positions parameterized as `ST_N_BIT/C/Z/V` in
  `tms34010_pkg.sv` (placeholders pending SPVU001A; documented in
  assumption A0010).
- Named flag outputs: `n_o`, `c_o`, `z_o`, `v_o`.
- `sim/tb/tb_status_reg.sv` covers reset, selective flag update,
  full write, non-flag bit preservation, st_write-wins-over-flag-
  update.
Tests:
- `scripts/sim.sh tb_status_reg` → PASS.
- All previous tests still PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — ST row → landed.
- `docs/assumptions.md` — A0010 entry added.
- `changelog.md`, `tasks.md`.
Commit:
- 24edaee

---

### Task 0010: Decode skeleton + full execute cycle
Status: complete
Dependencies:
- Task 0005 (memory model + fetch substrate)
Spec sources:
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/02-instruction-set.md`
  §"Encoding shape" (16-bit-aligned half-words; SPVU004 opcode chart
  is authoritative; decode space is dense, no top-bits-give-class).
Acceptance Criteria:
- `rtl/core/tms34010_decode.sv` exists as a purely combinational
  decoder. Phase 3 skeleton always flags ILLEGAL.
- Package gains `instr_word_t`, `instr_class_t` (currently
  `INSTR_ILLEGAL` only), `decoded_instr_t` (`{illegal, iclass}`),
  `INSTR_WORD_WIDTH = 16`.
- Core wiring: latch `instr_word_q` from `mem_rdata[15:0]` on
  `mem_ack` in CORE_FETCH; combinational decode runs over
  `instr_word_q`; FSM now walks `FETCH → DECODE → EXECUTE →
  WRITEBACK → FETCH` (5 cycles per instruction in the current
  placeholder loop, was 3 before).
- Sticky `illegal_opcode_o` observability output: latches on the
  first CORE_DECODE cycle where `decoded.illegal == 1`, cleared
  only by reset.
- `sim/tb/tb_illegal_opcode.sv` verifies the end-to-end path.
- `sim_memory_model.sv` deterministic-init: backing store zeroed in
  an `initial` block so unpreloaded addresses read as 0, not X.
Tests:
- `scripts/sim.sh tb_illegal_opcode` → PASS.
- All previous tests still PASS (8/8).
- Lint clean.
Docs:
- `docs/architecture.md` — decode row → skeleton landed.
- `docs/instruction_coverage.md` — note that Phase 3 skeleton routes
  every encoding to ILLEGAL; first real instruction lands Task 0011.
- `changelog.md`, `tasks.md`.
Commit:
- a959c28

---

### Task 0011: Wire datapath modules into core
Status: complete
Dependencies:
- Task 0010 (decode skeleton already wired)
- Tasks 0006, 0007, 0009 (regfile, ALU, ST modules ready to instantiate)
Acceptance Criteria:
- `rtl/core/tms34010_core.sv` instantiates `tms34010_regfile`,
  `tms34010_alu`, and `tms34010_status_reg`. The shifter is NOT
  wired yet (no shift instruction lands until shifts are added).
- Datapath connections: ALU `result` → regfile `wr_data` port;
  ALU `flags` → status-register `flags_in` port; status-register
  `c_o` → ALU `cin`. ALU `a` and `b` come from the regfile's two
  read ports.
- All "go" signals (`rf_wr_en`, `st_flag_update_en`, `st_write_en`)
  tied 0 — no observable behavior change in this commit.
- Control selectors (`rf_rs*_idx/file`, `rf_wr_idx/file`, `alu_op`,
  `st_write_data`) tied to safe defaults (file A, index 0,
  `ALU_OP_PASS_A`, 0).
- Existing 8 testbenches all PASS with no test modifications.
- Lint clean.
Tests:
- Full regression: 8/8 PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — module-instantiation comment updated.
- `changelog.md`, `tasks.md`.
Commit:
- 8f8a1ec

---

### Task 0012: Implement MOVI IW end-to-end
Status: complete
Dependencies:
- Task 0011 (datapath wired)
Spec sources:
- `third_party/TMS34010_Info/tools/assembler/TMS34010_Assembly_Language_Tools_Users_Guide_SPVU004.pdf`
  — assembler listings provide ground-truth encodings; the description
  "Move Immediate - Short or Long" provides the semantics.
  Captured in `docs/assumptions.md` A0011 (flag policy) and A0012
  (encoding).
- `third_party/TMS34010_Info/bibliography/hdl-reimplementation/02-instruction-set.md`
  §"Encoding shape" — long-immediate forms are 16-bit opcode followed
  by 16 or 32 bits of immediate data.
Acceptance Criteria:
- Decoder recognizes the MOVI IW encoding (top 10 bits = 0x027,
  bit[5]=0). Returns `iclass=INSTR_MOVI_IW`, destination from bits
  [4:0], `needs_imm16=1`, `imm_sign_extend=1`, `alu_op=PASS_B`,
  `wb_reg_en=1`, `wb_flags_en=1`.
- Core FSM adds CORE_FETCH_IMM_LO (and reserves CORE_FETCH_IMM_HI
  for IL). Latches `imm_lo_q` on mem_ack, advances PC by 16 bits.
- ALU operand B selects `imm32` (sign-extended `imm_lo_q`) when the
  decoded class is `INSTR_MOVI_IW`. Result routed to regfile write
  port; flags routed to ST flag-update port. Writes gated by
  `state_q == CORE_WRITEBACK` and the corresponding decoded `wb_*_en`.
- `sim/tb/tb_movi.sv` exercises 5 MOVI IW instructions covering both
  files, positive/zero/negative immediates, and verifies (a) each
  destination register holds the sign-extended value via
  hierarchical reference, (b) ST flags after the last MOVI match the
  expected N/Z/C/V, (c) `illegal_opcode_o` stays 0 during the valid
  program window.
- Full regression: 9/9 PASS; lint clean.
Tests:
- `scripts/sim.sh tb_movi` → PASS.
- All previous 8 tests still PASS.
- Lint clean.
Docs:
- `docs/architecture.md` — decode row updated.
- `docs/instruction_coverage.md` — first real row (MOVI IW) added.
- `docs/assumptions.md` — A0011 (flag policy), A0012 (encoding).
- `changelog.md`, `tasks.md`.
Commit:
- e1ff18e

---

### Task 0013: Implement MOVI IL end-to-end
Status: complete
Dependencies:
- Task 0012 (MOVI IW; FSM IMM_HI state already in place; imm32 assembly
  already handles needs_imm32)
Spec sources:
- A0012 in `docs/assumptions.md` — encoding for MOVI IW/IL.
- SPVU004 description: "In the long form, the operand is a 32-bit
  signed value."
Acceptance Criteria:
- Decoder adds an arm matching `top10 == 0x027 && instr[5] == 1`.
  Sets `iclass=INSTR_MOVI_IL`, `needs_imm32=1`, `imm_sign_extend=0`,
  `alu_op=PASS_B`, `wb_reg_en=1`, `wb_flags_en=1`.
- No core changes required — the FETCH_IMM_LO → FETCH_IMM_HI path,
  imm32 assembly, and writeback wiring all already work.
- `sim/tb/tb_movi_il.sv` runs 5 MOVI IL instructions with immediates
  the IW form cannot encode (upper 16 bits ≠ sign-extension of
  lower). Verifies destination registers via hierarchical reference.
- Full regression: 10/10 PASS; lint clean.
Tests:
- `scripts/sim.sh tb_movi_il` → PASS.
- All previous 9 tests still PASS.
- Lint clean.
Docs:
- `docs/instruction_coverage.md` — MOVI IL row → implemented.
- `changelog.md`, `tasks.md`.
Commit:
- aebf99a

---

### Task 0014: Implement MOVK K, Rd
Status: complete
Dependencies:
- Task 0011 (datapath wired)
Spec sources:
- SPVU004 §"Move Constant - 5 Bits" plus assembler listings
  `MOVK 1,A12 → 0x182C` and `MOVK 8,B1 → 0x1911` (captured in A0013).
Acceptance Criteria:
- Decoder recognizes `bits[15:10] == 0x06`; sets `iclass=INSTR_MOVK`,
  extracts K from bits[9:5] into `decoded.k5`, sets `alu_op=PASS_B`,
  `wb_reg_en=1`, `wb_flags_en=0` (MOVK does NOT affect ST).
- Package: `INSTR_MOVK` added to `instr_class_t`; `k5` field added
  to `decoded_instr_t` (5 bits).
- Core: alu_b mux gains an arm for INSTR_MOVK that zero-extends
  `decoded.k5` to DATA_WIDTH.
- `sim/tb/tb_movk.sv` exercises K=0, K=1, K=16, K=31 across A and B
  files. Verifies both regfile content AND that ST is unchanged
  from reset zeros.
- Encoding helper sanity-checked against the two SPVU004 listings.
- Full regression: 11/11 PASS; lint clean.
Tests:
- `scripts/sim.sh tb_movk` → PASS.
- All previous 10 tests still PASS.
- Lint clean.
Docs:
- `docs/instruction_coverage.md` — MOVK row added.
- `docs/assumptions.md` — A0013 added.
- `changelog.md`, `tasks.md`.
Commit:
- 2c351a3

---

### Task 0015: Implement ADD Rs, Rd
Status: complete
Dependencies:
- Task 0011 (datapath wired)
Spec sources:
- SPVU001A Appendix A page A-14 (A0014, A0015).
Acceptance Criteria:
- Decoder recognizes `bits[15:9] == 7'b0100000`; sets
  `iclass=INSTR_ADD_RR`, `rs_idx=instr[8:5]`, `rd_file=instr[4]`,
  `rd_idx=instr[3:0]`, `alu_op=ALU_OP_ADD`, both wb enables.
- Package: `INSTR_ADD_RR` added to `instr_class_t`; `rs_idx` field
  added to `decoded_instr_t`.
- Core: regfile rs1 reads Rs and rs2 reads Rd. Both use
  `decoded.rd_file` for the file bit (TMS34010 architectural
  constraint).
- `sim/tb/tb_add_rr.sv` covers four cases including signed overflow
  and unsigned wrap; encoding helper independently re-derives the
  hand-decoded `ADD A1,A2 → 0x4022`.
- Full regression: 12/12 PASS; lint clean.
Tests:
- `scripts/sim.sh tb_add_rr` → PASS.
- All previous 11 tests still PASS.
- Lint clean.
Docs:
- `docs/instruction_coverage.md` — ADD Rs,Rd row added.
- `docs/assumptions.md` — A0014 (chart source) and A0015 (ADD
  encoding) added.
- `changelog.md`, `tasks.md`.
Commit:
- 4e7cacb

---

### Task 0016: Implement SUB Rs, Rd
Status: complete
Dependencies:
- Task 0015 (ADD; same encoding shape, same datapath wiring approach)
Spec source: SPVU001A A-14 chart row `0100 010S SSSR DDDD`.
Acceptance Criteria:
- Decoder arm for `top7 == 7'b0100010` setting `iclass=INSTR_SUB_RR`,
  `alu_op=ALU_OP_SUB`, both wb enables.
- Core: alu_a mux swaps to `rf_rs2_data` (Rd) for SUB so ALU's
  `a - b` produces `Rd - Rs` matching the spec.
- `sim/tb/tb_sub_rr.sv`: five cases (simple, equal, borrow,
  signed overflow, B-file).
- Full regression: 13/13 PASS; lint clean.
Tests: tb_sub_rr PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md, changelog.md, tasks.md.
Commit:
- ac0dbbf

---

### Task 0017: Reg-reg logical instructions (AND, ANDN, OR, XOR)
Status: complete
Dependencies:
- Tasks 0015/0016 (reg-reg shape, operand-swap pattern from SUB).
Spec source: SPVU001A A-14 chart rows for AND/ANDN/OR/XOR.
Acceptance Criteria:
- Four new decoder arms with 7-bit prefixes 7'b0101_000..011.
  iclass enum values INSTR_AND_RR / ANDN_RR / OR_RR / XOR_RR.
- alu_op selects ALU_OP_{AND,ANDN,OR,XOR}. ANDN reuses the SUB
  operand-swap (alu_a=Rd, alu_b=Rs) so the ALU's `a & ~b` produces
  the spec-mandated `Rd & ~Rs`.
- `sim/tb/tb_logical_rr.sv`: characteristic patterns for each op,
  encoder cross-checked against `XOR A0,A0=0x5600`.
- Full regression: 14/14 PASS; lint clean.
Tests: tb_logical_rr PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (4 rows), changelog.md, tasks.md.
Commit:
- e13e6a4

---

### Task 0018: Implement CMP Rs, Rd
Status: complete
Dependencies: Task 0016 (SUB infrastructure: alu_op CMP, operand-swap mux).
Spec source: SPVU001A A-14 chart row `0100 100S SSSR DDDD`.
Acceptance Criteria:
- Decoder arm `top7 == 7'b0100100`; `iclass = INSTR_CMP_RR`;
  `alu_op = ALU_OP_CMP`; `wb_reg_en = 0`; `wb_flags_en = 1`.
- Core: alu_a/b muxes add INSTR_CMP_RR to the SUB-style swap group.
- `sim/tb/tb_cmp_rr.sv` confirms Rd untouched after a CMP and the
  flags exactly match an equivalent SUB.
- Full regression: 15/15 PASS; lint clean.
Tests: tb_cmp_rr PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (CMP row), changelog.md, tasks.md.
Commit:
- 4ba4171

---

### Task 0019: First branch — JRUC short
Status: complete
Dependencies:
- Task 0011 (PC module instantiated in core but with load_en tied 0).
Spec sources:
- SPVU001A A-14 chart row `JRcc Address 1100 code xxxx xxxx`.
- SPVU001A Table 12-8 (cc=0000 = UC).
- A0016 (target math verified against SPVU004 assembler listing).
Acceptance Criteria:
- Decoder recognizes `instr[15:8] == 8'hC0 && instr[7:0] != 8'h00 &&
  instr[7:0] != 8'h80`. Returns `iclass=INSTR_JRUC_SHORT`,
  `wb_reg_en=0`, `wb_flags_en=0`.
- Core computes `branch_target_short = pc_value +
  $signed({instr[7:0], 4'h0})` combinationally.
- Core drives `pc_load_en=1`, `pc_load_value=branch_target_short`
  during `CORE_WRITEBACK` when `iclass == INSTR_JRUC_SHORT`.
- `sim/tb/tb_jruc_short.sv` proves the branch took (destination
  register holds landing-site value, not skipped-instruction value).
- Full regression: 16/16 PASS; lint clean.
Tests: tb_jruc_short PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md, assumptions.md A0016, changelog.md, tasks.md.
Commit:
- dc01463

---

### Task 0020: JRcc short — conditional branches (UC, EQ, NE)
Status: complete
Dependencies: Task 0019 (PC load_en path + branch_target_short already
  computed combinationally).
Spec source: SPVU001A Table 12-8 (subset verified per A0017).
Acceptance Criteria:
- Refactor: `INSTR_JRUC_SHORT` replaced with `INSTR_JRCC_SHORT`;
  `branch_cc` (4 bits) added to `decoded_instr_t`. Package gets
  `CC_UC/EQ/NE` constants.
- Decoder accepts the three verified cc values; other cc on the
  JRcc shape falls through to ILLEGAL.
- Core gains combinational `branch_taken` evaluator switching on
  `decoded.branch_cc` against ST flags. PC load only fires when
  `branch_taken=1` in `CORE_WRITEBACK`.
- `sim/tb/tb_jrcc_short.sv` covers JREQ taken, JRNE taken, JREQ
  not-taken. tb_jruc_short continues to verify the UC path.
- Full regression: 17/17 PASS; lint clean.
Tests: tb_jrcc_short PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md, assumptions.md A0017, changelog.md, tasks.md.
Commit:
- 4c5e69a

---

### Task 0021: K-form arithmetic (ADDK, SUBK)
Status: complete
Dependencies: Task 0014 (MOVK k5 infrastructure), Task 0016 (SUB swap pattern).
Spec source: SPVU001A A-14 chart rows for ADDK/SUBK; A0018 for K=0 interpretation.
Acceptance Criteria:
- Decoder arms for `top6 == 6'b000100` (ADDK) and `6'b000101` (SUBK).
- `decoded.k5` populated from `instr[9:5]`; `decoded.rd_file/idx` from
  `instr[4:0]`. alu_op = ADD / SUB. wb_reg_en = 1, wb_flags_en = 1.
- Core's alu_a/b muxes route Rd → alu_a and zero-extended K → alu_b
  for both ADDK and SUBK (joining the existing swap group).
- `sim/tb/tb_addk_subk.sv` covers increment/decrement, max-K,
  unsigned-wrap, zero-result, and a B-file case. Encoder verified
  against three hand-decoded encodings.
- A0018 added documenting the literal-K choice and flagging the
  unresolved K=0 → 32 hypothesis.
- Full regression: 18/18 PASS; lint clean.
Tests: tb_addk_subk PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (ADDK + SUBK rows), assumptions.md A0018,
  changelog.md, tasks.md.
Commit:
- f286298

---

### Task 0022: Single-reg unary ops (NEG, NOT)
Status: complete
Dependencies: Task 0007 (ALU already has NEG and NOT ops).
Spec source: SPVU001A A-14 unary chart rows.
Acceptance Criteria:
- Decoder recognizes the unary family by `instr[15:7] == 9'b000000111`.
  Sub-op `instr[6:5]`: 01 = NEG, 11 = NOT. ABS (00) and NEGB (10)
  fall through to ILLEGAL (deferred).
- INSTR_NEG and INSTR_NOT added to iclass enum; widened to 5 bits.
- Core: alu_a routes `rf_rs2_data` (Rd value) for both NEG and NOT.
- `sim/tb/tb_neg_not.sv` covers NEG of 5, NEG of 0, NEG of MIN_INT
  (V-flag), NOT of a mixed pattern, NOT of 0, NOT of -1 in B file.
- Full regression: 19/19 PASS; lint clean.
Tests: tb_neg_not PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (NEG + NOT rows + ABS/NEGB placeholders),
  changelog.md, tasks.md.
Commit:
- 7b9135d

---

### Task 0023: Immediate arithmetic IW (ADDI, SUBI, CMPI)
Status: complete
Dependencies: Task 0012 (MOVI IW IMM_LO fetch infra), Task 0018 (CMP wb_reg_en=0 pattern).
Spec source: SPVU001A A-14 chart rows for ADDI/SUBI/CMPI IW.
Acceptance Criteria:
- Three new INSTR_*_IW enum values (ADDI/SUBI/CMPI).
- Decoder grows a `top11` view; three new arms matching 11-bit prefixes:
  ADDI=11'b0000_1011_000, SUBI=11'b0000_1011_111, CMPI=11'b0000_1011_010.
- All three set needs_imm16=1, imm_sign_extend=1.
- alu_a routes Rd via the swap group; alu_b routes imm32 via the
  MOVI-IW arm.
- CMPI has wb_reg_en=0 (same as CMP Rs, Rd).
- `sim/tb/tb_immi_iw.sv` covers add-positive, sub-to-zero, add-
  negative-immediate (verifies sign-extension), CMPI equal, B-file
  add.
- Full regression: 20/20 PASS; lint clean.
Tests: tb_immi_iw PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (3 rows), changelog.md, tasks.md.
Commit:
- 574ed33

---

### Task 0024: K-form shifts (RL, SLA, SLL, SRA, SRL)
Status: complete
Dependencies: Task 0008 (shifter module), Task 0011 (datapath wired).
Spec source: SPVU001A A-14 chart rows for shift K-forms; A0019 for K
  treatment.
Acceptance Criteria:
- Five new INSTR_*_K enum values.
- Decoder: five new top6 patterns matching `001000..001100`.
- `decoded_instr_t` gains `shift_op` (shift_op_t) and `use_shifter`
  (bool).
- Core: shifter instantiated; result-data and flag-input muxes
  select between ALU and shifter outputs based on `use_shifter`.
- `sim/tb/tb_shift_k.sv` covers each op with characteristic patterns
  (sign-extension, logical-vs-arithmetic, rotate half-word swap, B
  file). Encoders verified against hand-decoded 0x2020 / 0x3200.
- A0019 added documenting K=0 literal interpretation and deferred
  K=0 → 32 hypothesis.
- Full regression: 21/21 PASS; lint clean.
Tests: tb_shift_k PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (5 rows), assumptions.md A0019,
  changelog.md, tasks.md.
Commit:
- 6a107ef

---

### Task 0025: Immediate IL batch (ADDI/SUBI/CMPI/ANDI/ORI/XORI)
Status: complete
Dependencies: Task 0013 (MOVI IL IMM_HI fetch infra).
Spec source: SPVU001A A-14 chart rows for each IL-form.
Acceptance Criteria:
- Six new INSTR_*_IL enum values.
- Decoder: six new top11 patterns. ADDI/CMPI/ANDI/ORI/XORI share
  base prefix 0000_1011_XXX; SUBI IL has its own base 0000_1101_000.
- All set needs_imm32=1 (use MOVI IL fetch path).
- alu_a and alu_b muxes extended with all six new iclasses.
- CMPI IL uses wb_reg_en=0.
- `sim/tb/tb_immi_il.sv` covers all six with characteristic 32-bit-
  immediate cases. Encoder verified against 0x0B20 (ADDI IL,A0)
  and 0x0D00 (SUBI IL,A0).
- Full regression: 22/22 PASS; lint clean.
Tests: tb_immi_il PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (6 rows), changelog.md, tasks.md.
Commit:
- 61c608f

---

### Task 0026: MOVE Rs, Rd (register-to-register)
Status: complete
Dependencies: Task 0011 (datapath wired).
Spec source: SPVU001A A-14 chart row for MOVE Rs, Rd.
Acceptance Criteria:
- INSTR_MOVE_RR enum value.
- Decoder arm `top6 == 6'b100100`. F bit at [9] ignored (A0020).
- alu_op = PASS_A (alu_a routes rf_rs1_data which is Rs).
- wb_reg_en = 1, wb_flags_en = 1 (N/Z from result per A0009).
- `sim/tb/tb_move_rr.sv` covers four cases.
- Full regression: 23/23 PASS; lint clean.
- Documentation: A0020 added for the F-bit deferral.
Tests: tb_move_rr PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md, assumptions.md A0020, changelog.md, tasks.md.
Commit:
- 95e0a29

---

### Task 0027: JRcc unsigned compares (LO, LS, HI, HS)
Status: complete
Dependencies: Task 0020 (JRcc framework).
Spec source: SPVU001A Table 12-8 (universally defined codes; less
  ambiguous than the signed compares).
Acceptance Criteria:
- Four new CC_* parameters in the package: CC_LO=0001, CC_LS=0010,
  CC_HI=0011, CC_HS=1001.
- Decoder accepts all four; the existing list-of-allowed-cc-values
  expands.
- Core's branch_taken evaluator computes each condition from ST flags.
- `sim/tb/tb_jrcc_unsigned.sv` covers each cc's take and skip arms,
  using a "sentinel register" pattern so the test cleanly
  distinguishes "branch took" from "branch did not take".
- Full regression: 24/24 PASS; lint clean.
Tests: tb_jrcc_unsigned PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (JRcc row updated), changelog.md, tasks.md.
Commit:
- 1addcc2

---

### Task 0028: NOP (No Operation)
Status: complete
Dependencies:
- Task 0010 (decode skeleton; FSM walks FETCH→DECODE→EXECUTE→WRITEBACK
  → FETCH with default writeback gates).
Spec source: SPVU001A §"NOP" page 12-170 plus instruction-summary table
  on the same page (A0021). Encoding = `0000 0011 0000 0000` = `0x0300`.
Acceptance Criteria:
- `INSTR_NOP` added to `instr_class_t` enum (5'd31).
- Decoder recognizes the single fixed encoding `0x0300` and returns
  `iclass = INSTR_NOP`, `wb_reg_en = 0`, `wb_flags_en = 0`, no
  needs_imm*.
- No core changes required — defaults handle "valid but no datapath
  action"; PC advance comes for free via the existing FETCH-ack pulse.
- `sim/tb/tb_nop.sv` validates: NOP encoding helper = 0x0300; A0
  retains the MOVI value across NOP; B5 holds the post-NOP MOVK value
  (proves PC advanced through NOP); ST.N and ST.Z preserved across
  NOP+MOVK (proves NOP did not update flags); `illegal_opcode_o == 0`
  (NOP not flagged). Memory pre-filled with NOP so end-of-program
  doesn't trip the illegal latch — also exercises NOP many more times
  as a bonus.
- A0021 documents the encoding source and the distinction from the
  unary family (ABS A0 = `0x0380`, not `0x0300`).
- Full regression: clean on the testbenches that pass under both
  Questa and Verilator; lint clean.
Tests: tb_nop PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (NOP row), assumptions.md A0021,
  changelog.md, tasks.md.
Commit:
- 0288d0f

---

### Task 0029: ADDC / SUBB Rs, Rd (carry-chain reg-reg arithmetic)
Status: complete
Dependencies:
- Task 0015/0016 (reg-reg shape + ALU has ADDC/SUBB ops + cin wired
  from st_c + SUB-style operand swap pattern available).
Spec source: SPVU001A page 12-37 (ADDC), page 12-248 (SUBB), plus the
  instruction-summary table. Encodings `0100 001S SSSR DDDD` (ADDC)
  and `0100 011S SSSR DDDD` (SUBB). A0022 captures the carry/borrow
  semantics and the use of the spec's worked examples as test vectors.
Acceptance Criteria:
- `instr_class_t` widened from 5 to 6 bits to make room past
  INSTR_NOP (5'd31). All existing enumerators kept their integer
  values; new entries are INSTR_ADDC_RR = 6'd32 and
  INSTR_SUBB_RR = 6'd33.
- Decoder: two new arms with 7-bit prefixes `7'b0100_001` (ADDC) and
  `7'b0100_011` (SUBB), each setting `alu_op = ALU_OP_{ADDC,SUBB}`,
  `wb_reg_en = 1`, `wb_flags_en = 1`.
- Core: SUBB joins the alu_a / alu_b operand-swap groups (alu_a = Rd,
  alu_b = Rs) so the ALU computes `Rd - Rs - cin`. ADDC uses the
  default routing because the operation is commutative on its
  register operands.
- `sim/tb/tb_addc_subb.sv` covers five cases landing in distinct
  destinations: ADDC C=0; ADDC C=1; SUBB C=0; SUBB C=1; and the
  SPVU001A page 12-248 row 7 signed-overflow vector
  (`0x7FFFFFFE - 0xFFFFFFFE` with C=0 → `0x80000000`, NCZV=1101).
  Final ST is checked against the spec NCZV row. Memory is pre-filled
  with NOP so end-of-program stays valid.
- A0022 records the semantics and test-vector source.
- Full Verilator regression of the 13 testbenches that already pass
  cleanly under Verilator: 13/13 PASS. RTL lint clean. Questa
  regression to be run on the Windows dev box.
Tests: tb_addc_subb PASS; the previous Verilator-clean regression set
  still PASS; lint clean.
Docs: instruction_coverage.md (ADDC + SUBB rows), assumptions.md
  A0022, changelog.md, tasks.md.
Commit:
- ccf6450

---

### Task 0030: JRcc condition-code correction + signed compares
Status: complete
Dependencies:
- Task 0027 (unsigned-compare JRcc framework).
Spec source: SPVU001A Table 12-8, re-extracted with `pdftotext -layout`
  from the long-form JRcc page (page 12-96). A0023 captures the
  corrected table; A0017 marked superseded.
Acceptance Criteria:
- Recognize and correct the EQ/NE encoding bug introduced in Task
  0020 / A0017: `CC_EQ` from `4'b0100` → `4'b1010`, `CC_NE` from
  `4'b0111` → `4'b1011`. The original guesses turned out to be the
  signed-compare LT and GT codes, not EQ/NE.
- Add the four signed-compare cc parameters: `CC_LT = 4'b0100`,
  `CC_GE = 4'b0101`, `CC_LE = 4'b0110`, `CC_GT = 4'b0111`.
- Decoder accepts all 11 verified cc values (UC, LO, LS, HI, LT, GE,
  LE, GT, HS, EQ, NE); other JRcc-shape codes still fall through to
  ILLEGAL (defensive).
- Core's `branch_taken` evaluator gains four new arms with the
  standard signed-compare logic: LT = `N^V`; GE = `!(N^V)`;
  LE = `(N^V) | Z`; GT = `!(N^V) & !Z`.
- `tb_jrcc_short.sv` sanity hex-constants updated from `0xC405` /
  `0xC705` → `0xCA05` / `0xCB05` for JREQ/JRNE +5. The
  encoding helper itself composes the cc by name and tracks the
  package change automatically.
- `tb_jrcc_signed.sv` added: 8 scenarios spanning all 4 signed cc's
  in both directions (take + skip), using the sentinel-register
  pattern from `tb_jrcc_unsigned.sv`.
- A0023 added (full corrected cc table). A0017 marked superseded but
  preserved for historical context. A0009-style lesson about
  `pdftotext -layout` on charts cross-referenced.
- Full Verilator regression of 24 testbenches that pass cleanly under
  Verilator: 24/24 PASS. Lint clean.
Tests: tb_jrcc_signed PASS; tb_jrcc_short/unsigned/jruc_short PASS;
  the previously Verilator-clean regression set still PASS; lint clean.
Docs: instruction_coverage.md (JRcc row updated to 11 cc codes),
  assumptions.md (A0023 added, A0017 superseded), changelog.md,
  tasks.md.
Commit:
- 61c5b1c

---

### Task 0031: JRcc long form (16-bit displacement)
Status: complete
Dependencies:
- Task 0030 (cc encoding fix + signed compares).
- Tasks 0012/0013 (CORE_FETCH_IMM_LO path; needs_imm16 already wired
  for MOVI IW and IW-immediate arithmetic).
Spec source: SPVU001A page 12-96 ("Jump Relative Conditional - ±32K
  Words"), referring to the same Table 12-8 the short form uses.
Acceptance Criteria:
- INSTR_JRCC_LONG added to instr_class_t (6'd34).
- Decoder recognizes JRCC-shape encodings where the opcode word's
  low byte is exactly `0x00` (the long-form marker) and the cc field
  is one of the 11 recognized codes from A0023. Sets
  `iclass = INSTR_JRCC_LONG`, `needs_imm16 = 1`, `branch_cc = cc`,
  `wb_reg_en = 0`, `wb_flags_en = 0`. The absolute-form marker
  (low byte = `0x80`) remains deferred.
- Core gains a combinational `branch_target_long = pc_value +
  sign_extend({imm_lo_q, 4'h0})`. The PC at CORE_WRITEBACK already
  reflects both fetches (opcode + disp), so `pc_value` is the
  spec's PC' — same target formula shape as the short form.
- PC-load mux extended with an INSTR_JRCC_LONG arm gated by
  `branch_taken`.
- `sim/tb/tb_jrcc_long.sv` covers four scenarios: JRUC long taken
  with small positive disp; JREQ long taken via CMPI Z=1; JREQ long
  NOT taken via CMPI Z=0; JRUC long with a larger positive disp
  (+64 words) that exercises the high byte of the disp word. Memory
  pre-filled with NOP so end-of-program doesn't trip
  `illegal_opcode_o`.
- Verilator regression of the 25 Verilator-friendly testbenches:
  25/25 PASS. Lint clean.
Tests: tb_jrcc_long PASS; the existing Verilator-clean regression
  set still PASS; lint clean.
Docs: instruction_coverage.md (new JRcc-long row), changelog.md,
  tasks.md.
Commit:
- 355dad5

---

### Task 0032: JUMP Rs (register-indirect jump)
Status: complete
Dependencies:
- Task 0019 (PC load_en path); Task 0011 (regfile rs1 port).
Spec source: SPVU001A page 12-98 ("Jump Indirect") + summary table.
  Encoding `0000 0001 011R DDDD`; top11 = 11'b00000001_011 = 0x00B.
Acceptance Criteria:
- INSTR_JUMP_RS added to instr_class_t (6'd35).
- Decoder recognizes the top11 prefix; `decoded.rd_file` and
  `decoded.rs_idx` populated so the regfile's rs1 port reads Rs.
  No writeback enables; no status update.
- Core's PC-load mux gains an INSTR_JUMP_RS arm that unconditionally
  loads PC with `{rf_rs1_data[31:4], 4'h0}` — Rs with the bottom
  4 bits forced to 0 for word alignment.
- `sim/tb/tb_jump_rs.sv` covers two scenarios: aligned target
  (A-file Rs holding a word-aligned bit-address); messy LSBs
  (B-file Rs with bottom nibble = 0xF, target should land at the
  aligned position anyway). Plus a sentinel-untouched check
  confirming neither fall-through MOVI ran, and the standard
  illegal-flag check (memory NOP-pre-filled).
- Encoding helper independently verified against
  `jump_rs_enc(A, 1) = 0x0161` and `jump_rs_enc(B, 7) = 0x0177`.
- Full Verilator regression: 26/26 PASS. Lint clean.
Tests: tb_jump_rs PASS; full regression PASS; lint clean.
Docs: instruction_coverage.md (JUMP Rs row), changelog.md, tasks.md.
Commit:
- 19b075b

---

### Task 0033: DSJ / DSJEQ / DSJNE Rd, Address (decrement-and-skip-jump family)
Status: complete
Dependencies:
- Task 0014 (K-form alu_b path; reused with k5=1).
- Task 0016 (SUB-style operand swap; reused with alu_a=Rd, alu_b=1).
- Task 0031 (16-bit signed-displacement target math; reused from JRcc long).
Spec source: SPVU001A pages 12-70 (DSJ), 12-72 (DSJEQ), 12-73 (DSJNE)
  + the instruction-summary table. All three: encoding
  `0000 1101 1xxR DDDD` followed by a 16-bit signed word-offset.
Acceptance Criteria:
- INSTR_DSJ, INSTR_DSJEQ, INSTR_DSJNE added to instr_class_t (6'd36..38).
- Decoder: one combined arm that recognizes any of the three top11
  prefixes (`11'b00001101_100`, `_101`, `_110`) and dispatches the
  iclass via an inner `unique case`. Sets `alu_op = ALU_OP_SUB`,
  `decoded.k5 = 5'd1`, `needs_imm16 = 1`, `wb_reg_en = 1`,
  `wb_flags_en = 0` (status unaffected per the spec).
- Core gains:
  - `dsj_precondition` signal: 1 for DSJ; `st_z` for DSJEQ; `!st_z`
    for DSJNE; 1 (default — no-op) for other iclasses. This gates
    rf_wr_en so DSJEQ Z=0 / DSJNE Z=1 leave Rd untouched per spec.
  - `dsj_rd_nonzero = (alu_result != 0)`: true when the
    post-decrement Rd is non-zero.
  - PC-load mux arm for the three iclasses fires
    `dsj_precondition && dsj_rd_nonzero`, reusing `branch_target_long`.
- DSJ-family joins the alu_a swap group (Rd via rs2 port) and the
  alu_b K-form mux arm (decoded.k5 = 1 → alu_b = 32'd1).
- `sim/tb/tb_dsj.sv` exercises 8 scenarios across all three
  instructions, with distinct counter registers per scenario so the
  end-of-test checks don't get clobbered by subsequent scenarios.
  Includes the four SPVU001A spec-table boundary cases (Rd=9 take;
  Rd=1 skip; Rd=0 take wraps to -1; Z=mismatch no-op). Test ends
  with a `0xC0FF` halt (JRUC short -1 = jump-to-self) to prevent
  memory wraparound re-executing the program and clobbering the
  per-scenario counter registers.
- Encoding helpers verified against `dsj_enc(A,5) = 0x0D85`,
  `dsjeq_enc(A,5) = 0x0DA5`, `dsjne_enc(A,5) = 0x0DC5`.
- DSJS (single-word short form with 5-bit offset + direction bit)
  explicitly deferred to a future task — different encoding shape.
- Full Verilator regression: 27/27 PASS. Lint clean.
Tests: tb_dsj PASS; full Verilator-friendly regression PASS;
  lint clean.
Docs: instruction_coverage.md (3 new rows + DSJS deferred note),
  changelog.md, tasks.md.
Commit:
- 23b3aa7

---

### Task 0034: JAcc Address (absolute conditional jump)
Status: complete
Dependencies:
- Task 0030 (corrected cc encoding + signed compares).
- Tasks 0012-0013 (CORE_FETCH_IMM_HI path; needs_imm32 already wired
  for MOVI IL etc.).
Spec source: SPVU001A page 12-91 ("Jump Absolute Conditional") +
  summary table. Encoding: opcode word `1100 cccc 1000 0000` (low
  byte = `0x80` unlocks the absolute form), followed by 32-bit
  absolute target address (LO word first, then HI word).
Acceptance Criteria:
- INSTR_JACC added to instr_class_t (6'd39).
- Decoder recognizes JRCC-shape encodings with `disp8 == 0x80` and
  one of the 11 recognized cc codes (A0023). Sets
  `iclass = INSTR_JACC`, `needs_imm32 = 1`, `branch_cc = cc`,
  `wb_reg_en = 0`, `wb_flags_en = 0` (status unaffected).
- Core gains `branch_target_jacc = {imm_hi_q, imm_lo_q[15:4], 4'h0}`
  (32-bit absolute target with bottom 4 bits forced to 0 per spec
  page 12-91 word-alignment requirement).
- PC-load mux extended with INSTR_JACC arm gated by `branch_taken`,
  reusing the existing JRcc condition evaluator.
- `sim/tb/tb_jacc.sv` covers three scenarios: JAUC absolute taken
  with messy bottom-nibble target (verifies alignment mask); JAEQ
  absolute taken via CMPI Z=1; JANE absolute NOT taken via CMPI Z=1.
  Memory NOP-pre-filled; final scenario ends with `0xC0FF` halt.
Tests: tb_jacc PASS; Verilator regression PASS; lint clean.
Docs: instruction_coverage.md (new JAcc row), changelog.md, tasks.md.
Commit:
- ae618c3

---

### Task 0035: DSJS Rd, Address (decrement-and-skip-jump short form)
Status: complete
Dependencies:
- Task 0033 (DSJ-family precondition/nonzero gating + alu_a/alu_b
  mux entries; reused with INSTR_DSJS added).
Spec source: SPVU001A page 12-74 ("Decrement Register and Skip Jump
  - Short") + summary table line 13844. Encoding `0011 1Dxx xxxR DDDD`
  (top5 = 5'b00111). bit[10] = D (direction); bits[9:5] = 5-bit
  unsigned offset; bit[4] = R; bits[3:0] = Rd index. Single-word
  instruction, no immediate fetch.
Acceptance Criteria:
- INSTR_DSJS = 6'd40 added to instr_class_t.
- Decoder: top5 == 5'b00111 → INSTR_DSJS, with alu_op=SUB, k5=1,
  wb_reg_en=1, wb_flags_en=0. Direction and offset are NOT captured
  in the decoded struct — they're extracted in the core directly
  from instr_word_q[10] and instr_word_q[9:5].
- Core:
  - INSTR_DSJS joins the alu_a swap group (Rd via rs2) and the
    K-form alu_b mux arm (k5=1 → alu_b=1).
  - dsj_precondition for DSJS = 1'b1 (unconditional, like DSJ).
  - New branch_target_dsjs = pc_value + (D ? -off*16 : +off*16),
    where pc_value at WRITEBACK already equals PC' (= PC_original
    + 16 after the single-word opcode fetch). PC-load mux gains a
    new INSTR_DSJS arm gated by dsj_rd_nonzero.
- `sim/tb/tb_dsjs.sv` covers four scenarios:
  - Forward DSJS Rd=9→8 take (sentinel preserved);
  - Forward DSJS Rd=1→0 skip (fall-through runs);
  - Backward DSJS Rd=5→4 take, choreographed so the backward target
    is a known MOVI that writes a sentinel (verifies the D=1 path
    end-to-end);
  - Forward DSJS Rd=0→0xFFFFFFFF take (verifies the decrement-of-0
    case from the spec example table).
- Encoding helper verified: `dsjs_enc(D=0, off=5, A, 5) = 0x38A5`,
  `dsjs_enc(D=1, off=5, A, 5) = 0x3CA5`.
- Branch-family regression: all 9 branch tbs PASS.
Tests: tb_dsjs PASS; branch-family regression PASS; lint clean.
Docs: instruction_coverage.md (DSJS row), changelog.md, tasks.md.
Commit:
- c60c723

---

### Task 0036: ABS / NEGB Rd (complete the unary family)
Status: complete
Dependencies:
- Task 0022 (unary-family decoder framework + ALU_OP_NEG / NOT).
- Task 0029 (ALU_OP_SUBB; NEGB is implemented as SUBB with alu_a=0).
Spec source: SPVU001A page 12-34 (ABS), page 12-168 (NEGB). Encodings
  from the unary chart (`0000 0011 1ooR DDDD` with `oo` selecting
  sub-op): ABS = bits[6:5]=00; NEGB = bits[6:5]=10.
Acceptance Criteria:
- INSTR_ABS = 6'd41 and INSTR_NEGB = 6'd42 added to instr_class_t.
- ALU_OP_ABS = 4'd13 added to alu_op_t.
- `tms34010_alu.sv` gains an ALU_OP_ABS arm: result is the conditional
  select between `a` (when `0-a` has its sign bit set — either a was
  already non-negative or a == MIN_INT) and `0-a` (when `0-a` is
  non-negative — i.e., a was negative and small enough to flip).
  N is set to the sign of `0-a` per spec; Z = (a == 0); V on MIN_INT
  overflow. **C is cleared (A0024 deviation)** — spec says "Unaffected"
  but the project's wb_flags_en is currently all-or-nothing.
- NEGB reuses ALU_OP_SUBB. Core's alu_a mux gains an `INSTR_NEGB`
  arm forcing `alu_a = '0`; the default alu_b mux already routes
  `rf_rs2_data` (Rd) when not overridden, so ALU computes
  `0 - Rd - C` as required.
- Decoder's unary-family case statement gains the `2'b00` (ABS) and
  `2'b10` (NEGB) sub-op arms; ILLEGAL fallthrough removed.
- `sim/tb/tb_abs_negb.sv` runs 6 ABS test vectors from the spec
  example table (page 12-34) and 4 NEGB vectors from page 12-168.
  Final ST.NCZV checked against the spec NCZV column for NEGB's
  last scenario (`-1 - 1 → 0, NCZV = 0110` per the last row).
- Encoding helper verified: `abs_enc(A,1) = 0x0381`,
  `negb_enc(A,1) = 0x03C1`.
- A0024 added to docs/assumptions.md documenting the C-clear
  deviation and the deferred per-flag-mask refactor (also flagging
  BTST as the natural next instruction to motivate that refactor).
Tests: tb_abs_negb PASS; tb_neg_not / tb_alu / tb_sub_rr /
  tb_addc_subb regression PASS; lint clean.
Docs: instruction_coverage.md (ABS / NEGB rows updated from "not
  started" to "implemented"), assumptions.md A0024, changelog.md,
  tasks.md.
Commit:
- aac06d5

---

### Task 0037: BTST K/Rs + per-flag wb_flag_mask refactor
Status: complete
Dependencies:
- Tasks 0009 (status register), 0017 (logical ops + ALU_OP_AND).
- Task 0036 (ABS — its A0024 C-clear deviation is RESOLVED by the
  refactor that lands here).
Spec source: SPVU001A pages 12-46 (BTST K, Rd) and 12-47 (BTST Rs, Rd)
  + summary table lines 26942/26943. Encodings `0001 11KK KKKR DDDD`
  (BTST K) and `0100 101S SSSR DDDD` (BTST Rs). Status: Z = !bit;
  N, C, V "Unaffected" per spec.
Acceptance Criteria:
- **wb_flag_mask refactor** (architectural):
  - `decoded_instr_t` gains `wb_flag_mask : alu_flags_t` field.
  - `tms34010_status_reg.sv` gains a `flag_update_mask` input;
    per-bit gating on N/C/Z/V update in the always_ff.
  - `tms34010_core.sv` wires `decoded.wb_flag_mask` into the
    status_reg's new input.
  - Decoder's always_comb defaults `decoded.wb_flag_mask = '1` (all
    flags update) so every existing arm Just Works — no per-arm
    changes needed except for instructions that DO want selective
    updates.
  - `tb_status_reg.sv` updated for the new port (driven all-ones by
    default; existing checks unchanged).
- **A0024 resolved**: ABS arm in the decoder now sets
  `wb_flag_mask = '{n:1, c:0, z:1, v:1}`. ABS becomes spec-correct
  for C — the flag is truly "Unaffected". A0024 marked RESOLVED.
- **BTST**:
  - INSTR_BTST_K = 6'd43 and INSTR_BTST_RR = 6'd44 added to
    instr_class_t.
  - Decoder: top6 = 6'b000111 (BTST K) and top7 = 7'b0100_101
    (BTST Rs) arms with `alu_op = ALU_OP_AND`, `wb_reg_en = 0`,
    `wb_flag_mask = '{n:0, c:0, z:1, v:0}`.
  - Core's alu_a mux: INSTR_BTST_K and INSTR_BTST_RR join the
    swap group (alu_a = Rd via rs2 port).
  - Core's alu_b mux: new arms drive `32'd1 << decoded.k5` for
    BTST K and `32'd1 << rf_rs1_data[4:0]` for BTST Rs.
- `sim/tb/tb_btst.sv`: 5 scenarios using JRZ/JRNE probes to verify
  Z-flag behavior for each BTST (since the JRcc destination
  register reveals Z without needing direct ST sampling between
  BTSTs). Plus a final CMP-NCZV=1101 → BTST → halt sequence that
  verifies N, C, V are preserved unchanged across the BTST.
- Encoding helpers verified: `btst_k_enc(0,A0) = 0x1C00`,
  `btst_k_enc(1,A2) = 0x1C22`, `btst_k_enc(31,A0) = 0x1FE0`,
  `btst_rr_enc(A3,A4) = 0x4A64`.
- Full Verilator regression: all existing tbs still PASS after the
  flag-mask refactor. tb_btst PASS. tb_status_reg unit test PASS
  (with the new port wired with mask=all-ones).
- BTST Rs/K is the first instruction in the project to exercise the
  per-flag mask; ABS retroactively becomes the second instruction.
Tests: tb_btst PASS; broader regression including tb_movi/tb_movk/
  tb_add_rr/tb_sub_rr/tb_cmp_rr/tb_logical_rr/tb_addc_subb/
  tb_immi_iw/tb_shift_k/tb_neg_not/tb_abs_negb/tb_jrcc_short/
  tb_jrcc_signed/tb_dsj PASS; lint clean.
Docs: instruction_coverage.md (BTST K + Rs rows added; ABS row
  updated to reflect resolved deviation), assumptions.md (A0024
  marked RESOLVED), changelog.md, tasks.md.
Commit:
- d9a75b0

---

### Task 0038: CLRC / SETC / GETST / PUTST (status-register manipulation)
Status: complete
Dependencies:
- Task 0037 (wb_flag_mask used by CLRC/SETC for selective C-only updates).
- Task 0009 (status register has full ST-write path used by PUTST).
Spec source: SPVU001A summary table page A-14:
  CLRC  : 0x0320
  SETC  : 0x0DE0
  GETST Rd : 0000 0001 100R DDDD
  PUTST Rs : 0000 0001 101R DDDD
Acceptance Criteria:
- Four new iclass enumerators (INSTR_CLRC/SETC/GETST/PUTST,
  6'd45..48).
- Decoder arms:
  - CLRC/SETC: single fixed encodings, `wb_reg_en=0`,
    `wb_flags_en=1`, `wb_flag_mask = {c-only}`.
  - GETST: top11 = 0x00C, `wb_reg_en=1`, no flag update.
  - PUTST: top11 = 0x00D, `wb_reg_en=0`, no flag update; the
    full-ST-write happens via st_write_en in the core.
- Core:
  - Flag-input mux gains SETC arm (`flags_in.c = 1`) and CLRC arm
    (`flags_in.c = 0`); paired with the c-only mask from the
    decoder, only ST.C updates.
  - rf_wr_data mux gains GETST arm routing `st_value`.
  - `st_write_en` now derives from `(CORE_WRITEBACK && iclass == PUTST)`;
    `st_write_data = rf_rs1_data`.
- `sim/tb/tb_st_ops.sv` verifies a PUTST → GETST round-trip with a
  custom ST value, then a SETC followed by GETST, then a CLRC
  followed by GETST. Each captured GETST result is cross-checked
  bit-by-bit, and the final ST.{N,C,Z,V} are checked individually
  to confirm CLRC/SETC truly leave N/Z/V alone.
- Encoding helpers verified: `getst_enc(A,5) = 0x0185`,
  `putst_enc(B,7) = 0x01B7`.
Tests: tb_st_ops PASS; full Verilator regression PASS; lint clean.
Docs: instruction_coverage.md (4 new rows), changelog.md, tasks.md.
Commit:
- 1236868

---

### Task 0039: Shift Rs-form (SLA/SLL/SRA/SRL/RL with Rs amount)
Status: in progress
Dependencies:
- Task 0024 (K-form shifter wired; this task extends with a second
  amount source).
Spec source: SPVU001A summary table page A-15 + page 12-219 prose
  (the per-shift detail pages). Encodings `0110 0NNS SSSR DDDD`
  where NN selects {SLA, SLL, SRA, SRL, RL} per top7 prefixes
  `7'b0110_000..100`.
Acceptance Criteria:
- Five new iclass values (INSTR_{SLA,SLL,SRA,SRL,RL}_RR) at
  6'd49..53.
- Decoder arms with the corresponding top7 prefixes, populating
  `decoded.shift_op`, `decoded.rs_idx`, `decoded.rd_*`,
  `use_shifter = 1`, `wb_reg_en = 1`, `wb_flags_en = 1`.
- Core gains a `shifter_amount` mux signal:
  - For `INSTR_SLA_RR/SLL_RR/RL_RR`: `shifter_amount = rf_rs1_data[4:0]`.
  - For `INSTR_SRA_RR/SRL_RR`: `shifter_amount = (~rf_rs1_data[4:0]) + 1`
    (2's complement per A0019-extended; the assembler emits the
    negated amount).
  - Default (K-form): `shifter_amount = decoded.k5` (unchanged).
- `sim/tb/tb_shift_rr.sv` covers all 5 Rs-form shifts with shift
  amount = 4. For SRA/SRL it uses A1 = 28 (5-bit 2's-comp of 4)
  to drive the HW into a magnitude-4 right shift.
- Encoding helper verified: `shift_rr_enc(SLL_top7, A1, A, A2) = 0x6222`,
  `shift_rr_enc(SRA_top7, A3, A, A4) = 0x6464`.
- Full Verilator regression PASS; lint clean.
Tests: tb_shift_rr PASS; tb_shift_k unchanged; full regression PASS.
Docs: instruction_coverage.md (5 new rows), changelog.md, tasks.md.
Commit:
- pending

---

## Task entry template (for future tasks)

```
### Task NNNN: <short imperative title>
Status: <pending|in progress|complete|blocked>
Dependencies:
- Task NNNN (or "none")
Acceptance Criteria:
- <observable, testable bullets>
Tests:
- <named tests that must pass; or explicitly state why testing is deferred>
Docs:
- <which doc files this task updates>
Commit:
- <hash, or "pending">
```

---

## Roadmap (post-Phase 0)

Tracked at coarse granularity here; each phase expands into numbered tasks
when its predecessor lands.

- **Phase 1 — Core shell**: package constants, top-level ports, clock/reset,
  PC skeleton, memory IF, fetch/decode/execute FSM scaffold.
- **Phase 2 — Register/ALU foundation**: register file (A/B + SP + ST + PC),
  ALU, flag logic, shifter, targeted tests.
- **Phase 3 — Instruction fetch/decode**: opcode decode tables, operand
  decode, illegal-opcode trap, `docs/instruction_coverage.md` populated.
- **Phase 4 — Simple execution**: reg-reg, immediates, branches, basic
  load/store, flag updates.
- **Phase 5 — Addressing modes**: architectural modes, field/pixel
  addressing, alignment + boundary behavior.
- **Phase 6 — Memory and bus**: external memory IF, host-visible behavior,
  bus arbitration, wait states.
- **Phase 7 — Graphics**: PIXBLT/FILL/LINE, plane masking, transparency,
  window checking, multi-cycle graphics FSMs.
- **Phase 8 — Interrupts/traps**: reset, IRQ recognition, trap entry/return,
  status save/restore, priority + masking.
- **Phase 9 — Video/display**: video timing, refresh, display memory.
- **Phase 10 — Synthesis & optimization**: Cyclone V build, timing closure,
  resource reduction, regression.
