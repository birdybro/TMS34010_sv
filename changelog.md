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
- Added **ABS Rd** and **NEGB Rd** (Task 0036) — completes the
  unary-instruction family that NEG and NOT started in Task 0022.
  Per SPVU001A pages 12-34 (ABS) and 12-168 (NEGB), encodings
  `0000 0011 100R DDDD` (ABS) and `0000 0011 110R DDDD` (NEGB).
  - ABS uses a new ALU_OP_ABS that mux-selects between `a` and
    `0-a` based on the sign of `0-a`. V=1 only when Rd was MIN_INT
    (`0x8000_0000`), matching the spec's V-overflow convention.
    N reflects the sign of `0-Rd` (NOT the sign of the result),
    again per spec.
  - NEGB reuses ALU_OP_SUBB with alu_a forced to 0 by a new core
    mux arm; the existing carry-in path (from ST.C) gives
    `Rd ← 0 - Rd - C` as required.
- Added `sim/tb/tb_abs_negb.sv` — 6 ABS test vectors lifted verbatim
  from SPVU001A page 12-34's worked example table (positive max,
  -1 → +1, MIN_INT V-flag case, MIN_INT+1, zero, and a generic
  negative). 4 NEGB vectors from page 12-168 covering both
  carry-in values × representative operands. Final ST.NCZV is
  cross-checked against the last NEGB row's NCZV column.
- Added `docs/assumptions.md` A0024 documenting one deviation: ABS
  currently CLEARS C, but the spec says C should be "Unaffected".
  This is a consequence of the project's still-all-or-nothing
  `wb_flags_en`. The fix is a per-flag mask in
  `decoded_instr_t` + `tms34010_status_reg`, planned to land
  together with BTST (which also needs selective Z-only updates).
- **A0024 RESOLVED in Task 0037** via the per-flag-mask refactor
  described below.

### Changed
- **Per-flag writeback mask** (Task 0037): added
  `wb_flag_mask : alu_flags_t` to `decoded_instr_t` and a
  `flag_update_mask` input to `tms34010_status_reg.sv`. The status
  register's always_ff now gates each of N, C, Z, V independently:
  a flag updates iff `flag_update_en && flag_update_mask.{flag}`.
  The decoder's always_comb defaults `wb_flag_mask = '1` so every
  pre-existing instruction continues with full flag-update behavior
  unchanged. New instructions that need selective updates override
  the mask in their decoder arms.
- ABS arm now sets `wb_flag_mask = '{n:1, c:0, z:1, v:1}` so C is
  truly "Unaffected" per SPVU001A page 12-34. (A0024 was created
  in Task 0036 as a deviation; Task 0037 marks it RESOLVED.)
- `sim/tb/tb_status_reg.sv` updated to drive the new `flag_update_mask`
  port with all-ones for its existing pre-refactor checks.

### Added
- **BTST K, Rd** and **BTST Rs, Rd** (Task 0037) — Bit-Test family.
  Per SPVU001A pages 12-46 / 12-47 + summary table lines
  26942/26943, encodings `0001 11KK KKKR DDDD` (BTST K) and
  `0100 101S SSSR DDDD` (BTST Rs). Semantics: test a single bit
  of Rd (selected by K or by Rs[4:0]); Z = 1 iff that bit is 0.
  Rd is NOT written. N, C, V are truly Unaffected (verified via the
  new mask).
- Implementation:
  - `INSTR_BTST_K = 6'd43`, `INSTR_BTST_RR = 6'd44` in iclass.
  - Decoder arms with `alu_op = ALU_OP_AND`, `wb_reg_en = 0`,
    `wb_flag_mask = '{n:0, c:0, z:1, v:0}`.
  - Core's alu_b mux drives `32'd1 << decoded.k5` for BTST K and
    `32'd1 << rf_rs1_data[4:0]` for BTST Rs. alu_a = Rd via the
    existing rs2-swap group. The resulting AND has a single bit
    set iff that bit was 1 in Rd, so Z falls out of the standard
    "Z = (result == 0)" ALU convention.
- Added `sim/tb/tb_btst.sv` — 5 JRZ/JRNE-probed scenarios covering
  BTST K (with K=0, K=1, K=31) and BTST Rs forms; plus a final
  CMP-NCZV=1101 → BTST → halt sequence directly verifying that
  N, C, V are preserved across the BTST (the wb_flag_mask
  end-to-end check).
- Added **CLRC / SETC / GETST / PUTST** (Task 0038) — the
  status-register manipulation family.
  - CLRC (0x0320) / SETC (0x0DE0): single-fixed-encoding control
    instructions. Both use the new wb_flag_mask with c-only
    enabled. The core's flag-input mux gains constant `{c:0,…}`
    and `{c:1,…}` arms so only ST.C is touched; N, Z, V are truly
    Unaffected.
  - GETST Rd (`0x0180 | (R<<4) | Rd`): copies the 32-bit status
    register into Rd. The core's `rf_wr_data` mux gains an arm
    routing `st_value` for this iclass.
  - PUTST Rs (`0x01A0 | (R<<4) | Rs`): full 32-bit write of Rs
    into ST. Uses the existing `st_write_en` + `st_write_data`
    path; the N/C/Z/V bits embedded in Rs become the new flags
    automatically.
- Added `sim/tb/tb_st_ops.sv` — PUTST + GETST round-trip with a
  custom ST value, then SETC and CLRC each followed by a GETST
  capture, then bit-level checks confirming CLRC/SETC truly only
  touch C (N/Z/V preserved from the prior PUTST value).
- Added **Shift Rs-form family** — SLA / SLL / SRA / SRL / RL with
  the shift amount sourced from Rs's low 5 bits instead of a 5-bit
  literal (Task 0039). Five new iclass values and decoder arms with
  the `0110_0NN` top-7 prefix shape from SPVU001A page A-15. The
  core's shifter-amount input gains a new mux: K-form arms drive
  `decoded.k5` (unchanged); Rs-form left/rotate shifts (SLA/SLL/RL)
  drive `rf_rs1_data[4:0]` directly; Rs-form right shifts (SRA/SRL)
  drive `(~rf_rs1_data[4:0]) + 1` to apply the 2's-complement
  convention spelled out on page 12-219 ("the SRA Rs, Rd and SRL
  Rs, Rd use the 2s complement value of the 5 LSBs in Rs"). This
  extends A0019 to cover the Rs form.
- Added `sim/tb/tb_shift_rr.sv` — five scenarios, one per opcode,
  each shifting by 4. For SRA/SRL the test loads A1 = 28 (5-bit
  2's-comp of -4) to drive a magnitude-4 right shift, verifying
  the negation in the shifter-amount mux end-to-end.
- Added **GETPC / EXGPC / REV** (Task 0040) — three small
  PC/register-context ops.
  - GETPC Rd: copies the current pc_value (at CORE_WRITEBACK, i.e.,
    one word past the GETPC opcode) into Rd.
  - EXGPC Rd: atomic swap PC ↔ Rd. The new PC has its bottom 4 bits
    forced to 0 (word alignment per A0025); the regfile's async-read
    rf_rs2_data delivers the OLD Rd value during the same WRITEBACK
    cycle that writes the new Rd, so no extra pipeline stage is
    needed.
  - REV Rd: writes the chip-revision constant 0x0000_0008 into Rd,
    per the spec's worked example on page 12-233.
- Added `docs/assumptions.md` A0025 capturing two related choices:
  the REV constant value and the EXGPC bottom-nibble PC mask. Both
  are clean reads of the 1988 User's Guide.
- Added `sim/tb/tb_pc_ops.sv` — verifies GETPC's PC bit-address
  capture, REV's constant write, and EXGPC's atomic swap (with a
  trap-sentinel MOVI right after EXGPC that must NOT execute, plus
  a known landing-site MOVI at the EXGPC target verifying the swap
  actually transferred control there).
- Added **LMO Rs, Rd** (Task 0041) — Find Leftmost-One priority
  encoder. Per SPVU001A page 12-108, encoding `0110 101S SSSR DDDD`
  (top7 = 7'b0110_101). Semantics: Rd ← 31 - bit_pos(leftmost-1 in
  Rs) in the bottom 5 bits (upper 27 = 0). If Rs == 0, Rd = 0 and
  Z = 1. N, C, V Unaffected (via the wb_flag_mask from Task 0037).
- Core gains a combinational LMO datapath: a synthesizable
  low-to-high scan over Rs's 32 bits (the last hit wins, so we
  end up with the highest-set bit position), then a conditional
  one's-complement (5 bits) into the bottom of Rd. The `flag_input`
  mux delivers `{z: (rs == 0), others: 0}` for INSTR_LMO_RR.
- Added `sim/tb/tb_lmo.sv` — all 5 worked examples from the spec's
  page-12-108 table (Rs=0, 1, 0x10, 0x08000000, 0x80000000) plus
  an N/C/V-preservation check that runs a CMP to set NCZV=1101,
  then an LMO, then verifies the three flags survived.

### Changed (Task 0042 — Phase 5 foundation)
- **Status register layout finalized** against SPVU001A §5.2 Table 5-2
  (page 5-18). The N/C/Z/V positions at 31..28 (originally A0010
  placeholders) happened to match the spec; the new constants pin
  down FS0[4:0], FE0[5], FS1[10:6], FE1[11], IE[21], PBX[25] to
  their authoritative positions.
- `tms34010_pkg.sv` gains six new ST-bit-position parameters plus
  `ST_RESET_VALUE = 32'h0000_0010` (per spec page 5-18 — FS0 = 16
  at reset, all flags clear).
- `tms34010_status_reg.sv` initializes `st_q` to `ST_RESET_VALUE`
  on reset instead of all-zeros.
- `sim/tb/tb_status_reg.sv`'s "after reset" check updated for the
  new reset value.
- `docs/assumptions.md` A0010 marked RESOLVED with the full layout
  spelled out.
- No instruction changes in this task — it's foundational for the
  upcoming SETF / EXGF / SEXT / ZEXT / DINT / EINT tasks.

### Added (Task 0043 — SETF FS, FE, F)
- Implemented **SETF FS, FE, F** per SPVU001A page 12-237. Encoding
  `0000 01F1 01FE FFFFF` — bit[9]=F selector, bit[5]=FE, bits[4:0]=FS.
  When F=0, updates FS0/FE0; when F=1, updates FS1/FE1. FS=0 encodes
  field-size 32 (per Table 5-3). Other ST bits (flags, the other FS/FE
  pair, IE, PBX, reserved) are preserved — verified end-to-end by a
  CMP-set-NCZV → SETF → GETST sequence in tb_setf.
- Core changes:
  - `st_write_en` now fires for both INSTR_PUTST (existing) and
    INSTR_SETF.
  - `st_write_data` is a small case mux: PUTST routes Rs unchanged;
    SETF routes a spliced-ST value built by reading the current
    `st_value` and overwriting the F-selected FS/FE bits with the
    literal values pulled directly from `instr_word_q[4:0]` and
    `instr_word_q[5]`.
- Added `sim/tb/tb_setf.sv` — 5 scenarios covering FS0/FE0 update,
  FS1/FE1 update, FS=0 encodes 32, FS=31 boundary, and N/C/V/Z
  preservation across SETF.

### Added (Task 0044 — SEXT and ZEXT)
- Implemented **SEXT Rd, F** (sign-extend a field) per SPVU001A page
  12-238 and **ZEXT Rd, F** (zero-extend) per page 12-256. Both
  share the encoding shape `0000 01F1 SS_R_DDDD` with bits[7:5]
  selecting sub-op (000 = SEXT, 001 = ZEXT). The F bit at instr[9]
  selects FS0/FS1 from ST.
- Core gains a field-extension datapath: `fs_selected` reads the
  F-chosen FS bits from `st_value`; `field_mask` is built dynamically
  (`(1 << fs_selected) - 1`, with FS=0 treated as identity per
  Table 5-3's "encoding 00000 = size 32"); `sext_result` and
  `zext_result` are then a mask + optional sign-fill.
- Flag policy via wb_flag_mask: SEXT updates N, Z (C, V Unaffected);
  ZEXT updates only Z (N, C, V Unaffected) — both spec-correct.
- Added `sim/tb/tb_sext_zext.sv` running the spec's worked examples
  verbatim: 6 SEXT vectors (FS = 15, 16, 17 × F = 0, 1) and 5 ZEXT
  vectors (FS = 32-encoded-as-0, 31, 1, 16 × F = 0/1).

### Added (Task 0045 — EXGF Rd, F)
- Implemented **EXGF Rd, F** per SPVU001A page 12-77. Encoding
  `1101 01F1 000R DDDD` — top6 = 0x35, F at instr[9]. Atomic swap of
  Rd's low 6 bits with the F-selected `{FE, FS}` pair in ST; Rd's
  upper 26 bits are cleared.
- Core gains a small atomic-swap datapath: `exgf_cur_fs`/`exgf_cur_fe`
  read the OLD field values from ST; `exgf_new_rd = {26'b0, cur_fe,
  cur_fs}`; `exgf_new_st` splices the OLD Rd[5:0] (from the
  async-read rf_rs2_data, which sees the value BEFORE the same-cycle
  write) into the F-selected slot. `st_write_en` now triggers for
  INSTR_EXGF as well as PUTST and SETF; the st_write_data mux gains
  the matching arm.
- Added `sim/tb/tb_exgf.sv` running both spec-page-12-77 worked
  examples (F=0 and F=1) verbatim. Test-design note in the file
  documents a gotcha: MOVI must precede PUTST when seeding ST,
  because MOVI's default wb_flag_mask updates N/C/Z/V and would
  otherwise clobber the freshly-PUTST'd ST.

### Added (Task 0046 — DINT and EINT)
- Implemented **DINT (`0x0360`)** and **EINT (`0x0D60`)** — single-
  fixed-encoding interrupt-enable control instructions. DINT clears
  ST.IE (bit 21); EINT sets it. All status flag bits Unaffected.
  Implemented via the existing full-ST-write path with a small
  st_write_data mux extension:
    INSTR_DINT → `st_value & ~(1 << ST_IE_BIT)`
    INSTR_EINT → `st_value |  (1 << ST_IE_BIT)`
- `st_write_en` now triggers for {PUTST, SETF, EXGF, DINT, EINT}.
- Finally uses the `ST_IE_BIT` constant from Task 0042 — resolves
  one of the UNUSEDPARAM lint warnings.
- Added `sim/tb/tb_dint_eint.sv` — PUTSTs the seed value
  `0xA5A5_05A5 & ~IE`, then EINT → GETST → check IE=1 and other
  bits preserved, then DINT → GETST → check IE=0 and other bits
  still preserved. The scattered bit pattern in the seed catches
  any accidental wider write.

### Added (Task 0047 — Memory-write infrastructure + PUSHST)
- **Memory-write infrastructure** is now live. The core's
  previously-stubbed `CORE_MEMORY` FSM state actively drives
  `mem_req`/`mem_we`/`mem_addr`/`mem_size`/`mem_wdata` for write
  transactions and transitions to `CORE_WRITEBACK` on `mem_ack`.
  A new `decoded.needs_memory_op` field signals the decoder's
  intent to slot a memory transaction between EXECUTE and WRITEBACK.
- `sim_memory_model.sv` now handles 32-bit reads and writes
  atomically: when `latched_size == 32`, two adjacent 16-bit words
  are written/read in a single ack. (16-bit transactions remain
  single-word as before.)
- `instr_class_t` widened from 6 to 7 bits (INSTR_PUSHST = 64
  overflowed the prior 6-bit cap).
- **PUSHST** (= 0x01E0) implemented as the first user of the
  memory-write path. `SP <- SP - 32; mem[SP] <- ST`. ALU computes
  the new SP via SUB with `alu_b = 32` (new mux entry); the
  CORE_MEMORY state writes ST to mem[alu_result] as a 32-bit
  transfer; WRITEBACK updates SP (regfile index 15 = SP alias).
  Status bits Unaffected per spec.
- Added `sim/tb/tb_pushst.sv` — initializes SP to a mid-memory
  bit-address, PUTSTs a seed pattern, runs PUSHST, then verifies
  (a) SP decremented by 32, (b) both 16-bit memory words at the
  new SP hold the low/high halves of ST, (c) ST itself is unchanged.
- Going forward: POPST, CALL/CALLA/CALLR, RETS/RETI, TRAP, MMTM/
  MMFM, MOVE memory-indirect, and MOVB all unblock on this
  infrastructure.

### Added (Task 0048 — POPST)
- Implemented **POPST** (= 0x01C0) — the inverse of PUSHST and the
  first instruction in the project that reads a 32-bit memory word
  and writes it to a non-regfile destination (ST). Per SPVU001A:
  `ST <- mem[SP]; SP <- SP + 32`. All four status flags are taken
  from the popped value's bits[31:28].
- INSTR_POPST = 7'd65. Decoder arm matches the literal opcode and
  sets `alu_op = ADD` (so the ALU produces `SP + 32` for the
  regfile-SP writeback), `wb_reg_en = 1`, `needs_memory_op = 1`.
  `wb_flags_en` stays 0 because the ST update goes through
  `st_write_en`/`st_write_data`, not the per-flag mask path.
- Core changes:
  - `alu_b` mux: INSTR_POPST joins PUSHST's `→ 32'd32` entry.
  - `CORE_MEMORY` arm for POPST drives `mem_we=0`,
    `mem_addr = rf_rs1_data` (= OLD SP, NOT `alu_result`), `mem_size=32`.
  - `st_write_en` triggers for INSTR_POPST as well as PUTST/SETF/
    EXGF/DINT/EINT.
  - `st_write_data` mux: INSTR_POPST → `mem_rdata` (the popped
    32-bit value).
- Added `sim/tb/tb_popst.sv` — runs a full PUSHST/POPST round-trip:
  seed ST, PUSHST, clobber ST with a different value, POPST,
  verify ST recovered, SP restored, and the four flag bits in the
  popped ST match `ST_SEED[31:28]`.

### Added (Task 0049 — CALL Rs)
- Implemented **CALL Rs** (= `0x0920 | (R<<4) | Rs`) — the first
  subroutine-call instruction. Per SPVU001A page 12-47:
    SP -= 32
    mem[new SP] = PC'      (return address)
    PC = Rs                 (with bottom 4 bits cleared for alignment)
- INSTR_CALL_RS = 7'd66. Decoder arm with top11 = 0x049. Reuses the
  memory-write path from PUSHST plus the bottom-nibble-mask PC-load
  pattern from JUMP Rs.
- Core changes:
  - `alu_a` swap group factored: INSTR_PUSHST, INSTR_POPST, and
    INSTR_CALL_RS all read SP via rs2 (since rd_idx=15 for all three).
  - `alu_b` mux: all three constants converge on `32'd32`.
  - CORE_MEMORY: new INSTR_CALL_RS arm. mem_addr = alu_result
    (= new SP), mem_we=1, mem_size=32, mem_wdata=pc_value (= PC',
    which is the bit-address of the instruction following the CALL
    opcode at this point in the FSM).
  - PC-load mux: INSTR_CALL_RS unconditionally loads PC with
    `{rf_rs1_data[31:4], 4'h0}` (Rs with bottom nibble cleared).
- Added `sim/tb/tb_call_rs.sv` — places a subroutine at word 100
  that writes A6 = 0xCAFE_BABE; CALL A5 (= 0x640 = word 100*16);
  verifies (a) subroutine ran, (b) SP decremented, (c) mem[126..127]
  holds PC' (= bit-address of the instruction right after the CALL).

### Added (Task 0050 — RETS [N])
- Implemented **RETS [N]** per SPVU001A page 12-231. Encoding
  `0000 1001 011N NNNN` (`0x0960 | N`). Semantics:
    PC <- mem[SP]    (32-bit pop)
    SP <- SP + 32 + 16*N
  Status bits all "Unaffected". N at instr[4:0] is an optional
  argument-pop count (0..31); RETS without N defaults to N=0.
- INSTR_RETS = 7'd67. The decoder routes `instr[4:0] → decoded.k5`.
- Core changes:
  - alu_a swap group: INSTR_RETS joins (alu_a = SP via rs2).
  - alu_b mux new entry: `INSTR_RETS → 32'd32 + (decoded.k5 << 4)`.
    Computes 32 + 16*N. For N=0 → 32; for N=31 → 528 (per the spec
    page-12-231 worked example showing `SP -> SP+0x210` for N=31).
  - CORE_MEMORY: INSTR_RETS arm reads 32 bits from `rf_rs2_data` (=
    old SP), `mem_we=0`, `mem_size=32`.
  - PC-load mux: INSTR_RETS unconditionally loads `mem_rdata` into
    PC (no bottom-nibble mask, since the popped PC was already
    word-aligned when pushed).
- Added `sim/tb/tb_rets.sv` — full CALL → subroutine → RETS
  round-trip. Pre-CALL sentinel `A7 = 0xAAAA_AAAA`; subroutine
  writes A6 = 0xCAFE_BABE then RETS; post-CALL MOVI writes
  A7 = 0x0000_BEEF — that MOVI only runs if RETS actually returned
  correctly. So end-of-test `A7 == 0xBEEF` directly confirms the
  full subroutine round-trip, with `SP` restored to the original
  value.

### Added (Task 0051 — CALLA + CALLR)
- Implemented **CALLA Address** (= `0x0D5F` + 32-bit absolute) and
  **CALLR Address** (= `0x0D3F` + 16-bit signed disp). Both per
  SPVU001A pages 12-48 / 12-49. Each pushes PC' (the post-CALL
  return address) and jumps:
    CALLA  PC <- absolute address (low 4 bits cleared)
    CALLR  PC <- PC' + sign_ext(disp16) * 16
- INSTR_CALLA = 7'd68, INSTR_CALLR = 7'd69.
- Decoder: two new single-fixed-encoding arms. CALLA sets
  `needs_imm32 = 1`; CALLR sets `needs_imm16 = 1`. Both set
  `needs_memory_op = 1`, `alu_op = SUB`, `wb_reg_en = 1`,
  `wb_flags_en = 0`.
- Core changes:
  - Both join the alu_a swap group (alu_a = SP via rs2) and the
    constant-32 alu_b mux entry.
  - CORE_MEMORY: CALLA / CALLR / CALL_RS now share a single arm
    that pushes `pc_value` (the FSM-advanced PC' for each variant)
    to `mem[alu_result]`.
  - PC-load mux: CALLA → `branch_target_jacc` (same as JAcc);
    CALLR → `branch_target_long` (same as JRcc long form). Both
    target paths were already in place from Tasks 0031 / 0034.
- Added `sim/tb/tb_calla_callr.sv` — two full call/return round
  trips. Scenario A uses CALLA with target = 0x0640 (= word 100
  bit-address). Scenario B uses CALLR with a computed positive
  disp that lands on word 200. Each subroutine writes a distinct
  marker register and ends with RETS; each post-CALL MOVI writes
  another marker that only runs if the return landed correctly.
  Final SP must equal the original SP after both round-trips.

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
