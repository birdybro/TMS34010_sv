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
- Reg-reg logical block: **AND, ANDN, OR, XOR Rs, Rd**. 7-bit
  prefixes `7'b0101_0XX` per SPVU001A A-14. AND/OR/XOR are
  commutative and use the default alu_a/b routing; ANDN
  (`Rd & ~Rs → Rd`) reuses the SUB-style operand swap (`alu_a = Rd`,
  `alu_b = Rs`) so the ALU's `a & ~b` computes the right value.
  All four set N/Z from the result; C, V cleared (logical-op
  convention from A0009).
- Added `sim/tb/tb_logical_rr.sv` — covers all four ops with
  characteristic bit-pattern test cases (alternating bits, bit
  isolation, sign-bit flips). Encoder helper cross-checked against
  the SPVU004 listing `XOR A0,A0 = 0x5600`.
- Tenth instruction: **CMP Rs, Rd**. 7-bit prefix `7'b0100100`.
  Computes the same arithmetic as SUB but with `wb_reg_en = 0` —
  the destination register is **not** modified, only the status
  register changes. First instruction in the project that
  exercises the flag-only writeback path. Reuses the SUB operand-
  swap in the alu_a/b muxes.
- Added `sim/tb/tb_cmp_rr.sv` — verifies (a) Rs and Rd both
  unchanged after CMP, (b) flags match the equivalent SUB.
- **First branch instruction**: **JRUC short** (Jump Relative
  Unconditional, 8-bit signed displacement). Encoding
  `1100 0000 dddd_dddd` per SPVU001A A-14 + condition-code
  table 12-8 (cc = `4'b0000` = UC). Branch target =
  `PC_post_fetch + sign_extend(disp8) * 16`, verified by hand-
  decoding `JRGT L5 = 0xC70B` against the assembler listing in
  SPVU004 (logged as A0016). The PC module's `load_en` /
  `load_value` ports are now driven dynamically by the core's
  `CORE_WRITEBACK` logic.
- Added `sim/tb/tb_jruc_short.sv` — program with three MOVI IL
  instructions where the middle one is skipped by a JRUC +3. Verifies
  the destination register holds the **landing-site** value (proving
  the branch took) and never holds the skipped value.
- Added assumption A0016 covering the branch-target math and pointing
  forward to the future long/conditional/absolute variants.
- Generalized branch handling: `INSTR_JRUC_SHORT` is now
  `INSTR_JRCC_SHORT` with a `branch_cc` field. Decoder accepts the
  three verified condition codes (UC, EQ, NE per A0017); other cc
  values on the JRcc encoding fall through to ILLEGAL. The core
  gains a combinational `branch_taken` evaluator that picks the
  right ST-flag combination for each cc.
- Package adds `CC_UC=0000`, `CC_EQ=0100`, `CC_NE=0111` constants
  for use across decoder and core.
- Added `sim/tb/tb_jrcc_short.sv` — three scenarios: JREQ taken
  (Z=1 from equal-CMP), JRNE taken (Z=0 from unequal-CMP), and JREQ
  not-taken (with fall-through executing). Encoder helper
  cross-checked against hand-computed `JREQ +5 = 0xC405` and
  `JRNE +5 = 0xC705`.
- `tb_jruc_short` unchanged — UC (cc=0000) still encodes the same
  opcodes, so the existing test continues to verify the unconditional
  path through the refactored code.
- K-form arithmetic: **ADDK K, Rd** and **SUBK K, Rd**. Chart top-6
  prefixes `6'b000100` and `6'b000101` (per A0018). Reuses the
  `k5` field that MOVK already populates and the SUB-style operand
  swap pattern (alu_a = Rd, alu_b = K_zero_extended). Updates
  N/C/Z/V from the result.
- Added `sim/tb/tb_addk_subk.sv` — six cases: increment (ADDK 5),
  decrement (SUBK 1), max-K (ADDK 31), unsigned wrap (ADDK 1 of
  0xFFFFFFFF → 0 with C, Z), zero-result (SUBK 5 of 5 → 0 with Z),
  B-file (ADDK 16). Encoder verified against three hand-computed
  encodings (0x1020, 0x17E0, 0x10F5).
- Added assumption A0018 documenting the literal-K interpretation
  and flagging the unresolved K=0 → 32 hypothesis that some TI
  K-form ISAs use.
- Single-register unary block: **NEG Rd** and **NOT Rd**.
  Encoding family `0000 0011 XX1R DDDD` (the "unary" group) per
  SPVU001A A-14, with `bits[6:5]` selecting sub-op (01=NEG, 11=NOT).
  Both join the SUB-style alu_a swap group (Rd → alu_a). The ALU's
  existing NEG and NOT ops produce the right flag patterns,
  including V=1 on `NEG 0x8000_0000`.
- Deferred from this batch: **ABS** (needs an ALU op variant that
  conditionally negates based on sign + sets V on MIN_INT) and
  **NEGB** (Rd - 0 - C; needs carry-in routing). Tracked as
  not-started rows in `docs/instruction_coverage.md`.
- Widened `instr_class_t` from 4 bits to 5 bits to make room for
  the growing instruction set.
- Added `sim/tb/tb_neg_not.sv` — six cases covering NEG of a small
  positive, NEG of 0, NEG of MIN_INT (V-flag check), NOT of a
  mixed pattern, NOT of 0 → all-ones, and a B-file NOT.
- IW-form immediate arithmetic batch: **ADDI IW, SUBI IW, CMPI IW**.
  All three share encoding shape `0000 1011 XXXR DDDD` + 16-bit
  immediate word, with bits[7:5] selecting op (000=ADDI, 111=SUBI,
  010=CMPI per SPVU001A A-14). Decoder gets a `top11` view for
  matching the 11-bit prefix. Operand routing: alu_a = Rd,
  alu_b = imm32 (sign-extended from the 16-bit immediate). CMPI
  uses `wb_reg_en = 0` (nondestructive, same contract as CMP Rs,Rd).
- All three reuse MOVI IW's CORE_FETCH_IMM_LO state; no new FSM
  states needed.
- Added `sim/tb/tb_immi_iw.sv` — five cases: ADDI positive,
  SUBI to zero (Z=1), ADDI with negative sign-extended immediate
  (verifies sign-extension), CMPI equal (Z=1, Rd unchanged), and
  a B-file ADDI.
- K-form shift batch: **SLA, SLL, SRA, SRL, RL** (all K K, Rd
  forms). Top-6 prefixes 6'b001000..001100 per SPVU001A A-14.
  Wires the shifter module — previously built but unused — into
  the writeback path via a new `use_shifter` field in
  `decoded_instr_t`. The result-data and flag-input muxes pick
  between ALU and shifter outputs.
- Added package shift-op constant routing in `decoded_instr_t`
  (`shift_op` field of type `shift_op_t`).
- Added `sim/tb/tb_shift_k.sv` — six cases: SLL of 1 (basic left
  shift), SRA of 0x80000000 (sign-extension verification), SRL
  of 0x80000000 (logical right verification), SLA of a pattern,
  RL by 16 (half-word swap), and a B-file SRL.
- Added assumption A0019 covering the literal-K interpretation
  and flagging the unresolved K=0 → 32 hypothesis for shifts
  (parallel to A0018 for ADDK/SUBK).
- IL-form immediate batch: **ADDI IL, SUBI IL, CMPI IL, ANDI IL,
  ORI IL, XORI IL**. Six 32-bit-immediate instructions all sharing
  the 11-bit-prefix encoding shape. SUBI IL is the odd one out with
  a different base prefix (`0000_1101_000` vs `0000_1011_XXX` for
  the others). Reuses MOVI IL's CORE_FETCH_IMM_HI path.
- Added `sim/tb/tb_immi_il.sv` — six cases exercising 32-bit
  immediates that the IW form cannot encode (large values, full
  bit patterns). Includes CMPI IL with `wb_reg_en=0` verification
  and an XORI to invert (B-file).
- **MOVE Rs, Rd** (register-to-register move, same file). Encoding
  `1001 00FS SSSR DDDD` (top6 = `6'b100100`) per SPVU001A A-14.
  Routes through ALU PASS_A. The F bit (field-size selector,
  bit[9]) is ignored — Phase 4 implements full-width 32-bit
  register copy. Documented as A0020; field-size mechanics + the
  MOVE indirect-addressing variants are Phase 5 work.
- Added `sim/tb/tb_move_rr.sv` — four cases covering A-to-A move
  of a pattern, MOVE of zero (Z=1), MOVE of MIN_INT (N=1), and a
  B-file move. Encoder verified against hand-decoded
  `MOVE A1,A2 = 0x9022` and `MOVE B5,B7 = 0x90B7`.
- Added **unsigned-compare condition codes** to JRcc: LO (cc=0001,
  C=1), LS (cc=0010, C|Z), HI (cc=0011, ~C&~Z), HS (cc=1001, !C).
  These are universally defined across the field and can be added
  without ambiguity from the garbled spec table. Signed-compare
  codes (LT/LE/GT/GE) remain deferred until cleaner spec access.
- Added `sim/tb/tb_jrcc_unsigned.sv` — six scenarios covering each
  cc's take and skip paths. Uses a "sentinel register" pattern:
  each scenario pre-initializes its sentinel to a recognizable
  marker, then the fall-through MOVI overwrites it only if the
  branch did NOT take. The landing site writes elsewhere. This
  cleanly distinguishes "branch took" from "branch didn't take"
  by checking whether the sentinel still holds its marker.
- Added **NOP (No Operation)** — single fixed encoding `0x0300` per
  SPVU001A §"NOP" page 12-170 (A0021). `INSTR_NOP` joins the
  instruction-class enum; the decoder recognizes the exact 16-bit
  pattern; both writeback gates stay 0 so the only architectural
  effect is the PC advance the FETCH-ack pulse already provides. No
  core changes required. Distinct from the unary family at
  `0000 0011 1xxx xxxx` (ABS A0 = `0x0380`, not `0x0300`).
- Added `sim/tb/tb_nop.sv` — exercises MOVI → NOP → MOVK and verifies
  A0 untouched across NOP, B5 reached (PC advanced), ST.N/ST.Z
  preserved, and `illegal_opcode_o == 0`. Memory is pre-filled with
  NOP so the CPU keeps NOPing past the meaningful program, keeping
  the illegal-flag check meaningful at end-of-test.
- Added `docs/assumptions.md` A0021 capturing the NOP encoding source
  and the encoding distinction from the unary family.
- Added **ADDC Rs, Rd** (`0100 001S SSSR DDDD`) and **SUBB Rs, Rd**
  (`0100 011S SSSR DDDD`) — reg-reg arithmetic with carry-in /
  borrow-in from ST.C, used for extended-precision arithmetic chained
  with ADD/SUB/SUBI/etc. Both write N, C, Z, V from the 33-bit
  adder/subtractor. The ALU already implemented ADDC/SUBB; the work
  here is decode arms, the SUBB operand-swap (alu_a=Rd, alu_b=Rs to
  match SUB), and the test. A0022 captures the semantics and the use
  of SPVU001A page 12-248's worked SUBB examples as test vectors.
- Widened `instr_class_t` from 5 to 6 bits (Task 0029) — INSTR_NOP at
  5'd31 had exhausted the 5-bit space. All existing enumerator values
  preserved; only the enum width and the literal-width prefixes
  changed.
- Added `sim/tb/tb_addc_subb.sv` — five test cases landing in distinct
  destinations: ADDC with C=0; ADDC with C=1; SUBB with C=0; SUBB
  with C=1; and the SPVU001A page 12-248 row 7 spec vector
  (`0x7FFFFFFE - 0xFFFFFFFE` with C=0 → `0x80000000`, NCZV=1101)
  serving as the signed-overflow corner case. The carry-in for each
  test is set up using either MOVI/MOVK (preserve / clear C) or a
  deliberately-overflowing ADD (set C=1).

### Fixed
- **JRcc EQ/NE condition codes were WRONG.** A0017 (Task 0020) guessed
  CC_EQ = `4'b0100` and CC_NE = `4'b0111` from a garbled `pdftotext`
  extraction of Table 12-8. SPVU001A actually defines those codes as
  the signed-compare LT and GT, respectively. The correct encodings,
  confirmed by a clean `pdftotext -layout` re-extraction from the
  long-form JRcc page (12-96), are EQ = `4'b1010` and NE = `4'b1011`.
  Task 0030 corrects the package constants. Existing tests passed
  only because their encoding helpers composed the cc field from the
  same wrong constants; with the package fix the helpers now produce
  the spec-correct binary for JREQ (0xCAdd) and JRNE (0xCBdd). The
  two hard-coded hex sanity checks in `tb_jrcc_short.sv` were
  updated. A0017 marked SUPERSEDED; A0023 records the full corrected
  Table 12-8.
- Lesson: `pdftotext` without `-layout` mangles columnar charts beyond
  recoverability. The new `pdf-layout-for-charts` memory captures
  this so future spec extractions use the right invocation.

### Added (continued)
- **Signed-compare JRcc condition codes (Task 0030)**: LT (`4'b0100`,
  `N^V = 1`), GE (`4'b0101`, `N^V = 0`), LE (`4'b0110`, `(N^V) | Z`),
  GT (`4'b0111`, `!(N^V) & !Z`). The decoder accepts all 11 confirmed
  cc codes now (UC, LO, LS, HI, LT, GE, LE, GT, HS, EQ, NE). Codes
  not in this list still trap as ILLEGAL.
- Added `sim/tb/tb_jrcc_signed.sv` — eight scenarios spanning all
  four signed cc's in both directions, using the sentinel-register
  pattern from `tb_jrcc_unsigned.sv` (each sentinel is pre-set to a
  marker; if the JRcc takes, the marker survives; if it falls through,
  the marker is overwritten). The operand pairs (Rd, Rs) = (-5, 5),
  (5, -5), and (5, 5) drive the (N, V, Z) flags such that each cc's
  take and skip paths are both exercised.
- Added `docs/assumptions.md` A0023 with the full corrected Table
  12-8 (11 currently-recognized codes; deferred codes for P/N, V/NV,
  JRYxx XY-compares explicitly listed).
- Added **JRcc long form (16-bit displacement)** — Task 0031. Per
  SPVU001A page 12-96, when the opcode word's low byte is `0x00`,
  the next 16-bit word is a signed word-displacement and the range
  becomes ±32K words. `INSTR_JRCC_LONG` joins the iclass enum; the
  decoder routes the long form to `needs_imm16 = 1`; the core's
  `branch_target_long` adds the sign-extended disp×16 to the PC
  value seen at CORE_WRITEBACK (which has already advanced through
  both fetches, matching the spec's PC').
- Added `sim/tb/tb_jrcc_long.sv` — four scenarios: JRUC long taken
  (small positive disp), JREQ long taken via CMPI Z=1, JREQ long
  NOT taken via CMPI Z=0, and JRUC long with disp = +64 words to
  exercise the high byte of the disp word. Memory NOP-pre-filled.
- Added **JUMP Rs (register-indirect jump)** — Task 0032. Per
  SPVU001A page 12-98: encoding `0000 0001 011R DDDD`; semantics
  `PC ← (Rs & ~0xF)` (word-aligned). Single-word instruction, no
  status effect. `INSTR_JUMP_RS` joins the iclass enum; the
  decoder routes the rs1 port to read Rs; the core's PC-load mux
  gains an unconditional JUMP arm that masks the bottom 4 bits of
  rf_rs1_data before writing it to the PC.
- Added `sim/tb/tb_jump_rs.sv` — two scenarios: aligned A-file
  target; messy-LSB B-file target (verifies the bottom-nibble mask).
  Plus a sentinel check confirming no fall-through MOVI ran, and
  the standard illegal-flag check (memory NOP-pre-filled).
- Added **DSJ / DSJEQ / DSJNE Rd, Address** (Task 0033) — the
  Decrement-and-Skip-Jump family for loop primitives. Per SPVU001A
  pages 12-70..12-73, encodings `0000 1101 100R DDDD`,
  `_101R_`, `_110R_` followed by a 16-bit signed word-offset.
  Semantics: decrement Rd (if pre-condition holds for the
  conditional variants — Z=1 for DSJEQ, Z=0 for DSJNE); if the
  post-decrement value is non-zero, branch by `offset×16`; else
  fall through. Status register unaffected.
- The core gains a `dsj_precondition` signal that gates `rf_wr_en`
  (so DSJEQ Z=0 / DSJNE Z=1 leave Rd untouched per spec) and the
  PC-load (so the branch only fires when both the pre-condition and
  the `alu_result != 0` post-decrement check hold). Branch target
  reuses the existing `branch_target_long` computation. DSJ-family
  joins the alu_a operand-swap group (Rd routes to alu_a) and the
  K-form alu_b mux arm (decoded.k5 = 1 → alu_b = 32'd1).
- Added `sim/tb/tb_dsj.sv` — eight scenarios using DISTINCT counter
  registers per scenario (so end-of-test checks aren't clobbered by
  subsequent scenarios), covering the SPVU001A spec-table boundary
  cases for all three instructions. Test ends with a `0xC0FF`
  infinite-loop halt to prevent memory wraparound re-executing the
  program. Both gotchas (the comment-swallow and the halt pattern)
  are now captured in the `testbench-pitfalls` memory.
- DSJS (Decrement and Skip Jump — Short, single-word, 5-bit offset +
  direction bit) explicitly deferred — different encoding shape.
- Added **JAcc Address (absolute conditional jump)** — Task 0034.
  Per SPVU001A page 12-91: when the JRcc-shape opcode word's low
  byte is `0x80`, the next two words are a 32-bit absolute target
  address (LO, HI). PC ← address with bottom 4 bits forced to 0
  (spec-mandated word alignment). `INSTR_JACC` joins the iclass
  enum; the decoder routes it to `needs_imm32 = 1`; the core's new
  `branch_target_jacc` assembles `{imm_hi_q, imm_lo_q[15:4], 4'h0}`
  and feeds it into a new PC-load arm gated by the existing JRcc
  `branch_taken` evaluator.
- Added `sim/tb/tb_jacc.sv` — three scenarios: JAUC absolute taken
  with deliberately-messy bottom nibble (verifies the alignment
  mask), JAEQ absolute taken via CMPI Z=1, JANE absolute NOT taken
  via CMPI Z=1 (fall-through MOVI runs).
- Added **DSJS Rd, Address** (Task 0035) — the single-word
  short-form decrement-and-skip-jump that completes the DSJ family.
  Per SPVU001A page 12-74: encoding `0011 1Dxx xxxR DDDD`. The
  D bit (10) selects direction (0 = forward, 1 = backward); the
  5-bit offset (bits[9:5]) gives the word-displacement. Target =
  PC' ± offset×16. Rd is decremented unconditionally; branch is
  taken iff post-decrement Rd != 0. Status N/C/Z/V unaffected.
- The core extracts the direction bit and offset combinationally
  from `instr_word_q[10]` and `[9:5]` for `branch_target_dsjs`,
  rather than carrying them in the decoded struct. `INSTR_DSJS`
  joins the DSJ-family alu_a swap group, the K-form alu_b mux
  arm, and the dsj_precondition logic (with precondition = 1
  like DSJ). A new PC-load mux arm fires the branch when
  `dsj_rd_nonzero` (the post-decrement is nonzero).
- Added `sim/tb/tb_dsjs.sv` — four scenarios: forward take (9→8),
  forward skip (1→0), backward take (choreographed with a pre-
  executed back-target MOVI so the backward jump lands at a known
  sentinel), and the 0→0xFFFFFFFF spec corner case. Distinct
  counter registers per scenario; halt at end-of-program.

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
