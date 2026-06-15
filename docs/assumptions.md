# Assumptions

Anything in this file is something the RTL relies on that is **not** directly
quoted from the spec, or is an interpretation of an ambiguous passage. Every
entry must cite the spec section it relates to (file + page or section in
`third_party/TMS34010_Info`) and explain the chosen interpretation.

Entries are dated. Once an entry is confirmed against the spec or replaced
by definitive behavior, mark it `RESOLVED` with the resolving commit hash.

## A0001 — Specification source of truth
- **Date**: 2026-05-12
- **Status**: active (project-wide)
- **Source**: `third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf`
- **Assumption**: The 1988 TI User's Guide is the authoritative reference
  for ISA, register set, and architectural behavior. The SPVS002C datasheet
  is authoritative for electrical/timing pin-level behavior. When the 1986
  first-edition User's Guide and the 1988 edition disagree, the 1988
  edition wins.
- **Rationale**: 1988 is the second edition and reflects later silicon
  errata. MAME's CPU core is *not* treated as authoritative — only as a
  behavioral cross-check.

## A0002 — TMS34010 only, no TMS34020/34082 hybridization
- **Date**: 2026-05-12
- **Status**: active
- **Source**: `third_party/TMS34010_Info/README.md`
- **Assumption**: The initial RTL targets the TMS34010 only. TMS34020-specific
  instructions, register additions, and behavioral differences are
  out of scope. TMS34082 FPU coprocessor support is out of scope.
- **Rationale**: Tight scope, clean first milestone. Revisited if/when the
  '34020 superset becomes useful.

## A0003 — FPGA-friendly synchronous reset
- **Date**: 2026-05-12
- **Status**: active
- **Source**: project convention (not in spec).
- **Assumption**: Reset is active-high synchronous to the core clock.
  This differs from the original silicon's asynchronous reset signaling
  but is correct for FPGA timing closure and global-reset-network sharing
  on Cyclone V.
- **Rationale**: Original device pin-compat is not a project goal. Internal
  reset *behavior* (which registers initialize, to what values, when) will
  match the User's Guide.

## A0004 — Single core clock for the first milestones
- **Date**: 2026-05-12
- **Status**: active
- **Source**: project convention (not in spec).
- **Assumption**: All RTL through Phase 8 runs on a single clock. The video
  output subsystem (Phase 9) will introduce a pixel clock and a clearly
  documented CDC boundary.

## A0005 — Bit-addressed memory exposed at the interface boundary
- **Date**: 2026-05-12
- **Status**: active, **TODO/spec-uncertain** for exact field alignment rules
- **Source**: TMS34010 User's Guide bit-addressing chapter (to be cited by
  page once Phase 1 lands).
- **Assumption**: The core's external memory interface uses **bit addresses**
  (32-bit address, low bits select a bit within a word), plus a 6-bit field
  size (1–32 bits). External RAM glue is responsible for translating to
  byte/word addresses and handling unaligned access.
- **Rationale**: This matches the device's architectural model. Doing the
  bit-alignment outside the core keeps the core RTL clean and lets the
  external glue (and tests) take any shape.
- **Open question**: exact behavior on field reads that cross a 32-bit
  natural word boundary — needs a spec-cited resolution before Phase 5.

## A0006 — No cycle-accuracy contract in Phase 0–4
- **Date**: 2026-05-12
- **Status**: active
- **Source**: project convention.
- **Assumption**: Early phases target **functional correctness** (correct
  result, correct flags, correct memory effects), not cycle-by-cycle
  timing match with original silicon. Cycle-accuracy work begins in
  Phase 6 with bus timing and is tracked in `docs/timing_notes.md`.
- **Rationale**: Trying to hit cycle-exact timing before the ISA works
  is premature. The skeleton FSM is structured so adding states later
  is safe.

## A0007 — Spec quotes captured by section, not page screenshots
- **Date**: 2026-05-12
- **Status**: active
- **Assumption**: When citing the spec in code comments or this file, use
  the document filename + section title (and page number if helpful). Do
  not paste large quoted passages from the PDFs — link to the file path.
- **Rationale**: The PDFs in the submodule are the source. Duplicating
  large passages in-tree adds drift risk and isn't needed for review.

---

## A0008 — Reset PC and reset-vector fetch sequence deferred to Phase 8
- **Date**: 2026-05-12
- **Status**: active, **TODO/spec-uncertain**
- **Source**: `third_party/TMS34010_Info/bibliography/hdl-reimplementation/11-interrupts-reset.md`
  §"Reset" — "PC = reset vector (fixed bit address — see SPVU001A Ch. 13)"
  and "Vector-fetch is a normal local-bus read. No special path. The
  reset and interrupt sequences just program PC = vector value, then
  resume normal fetch."
- **Assumption**: The TMS34010's architectural reset sequence is:
  1. Set internal PC to the reset-vector trap-table slot (near
     `0xFFFFFFC0` per the bibliography file; exact value pending a read
     of SPVU001A Ch. 13).
  2. Fetch a 32-bit value from that slot via the normal local-bus read.
  3. Load PC with that fetched value.
  4. Resume normal fetch.
  In Phase 1, the core does **not** perform this sequence. Instead, the
  PC register starts at the package's `RESET_PC` parameter (currently
  `'0`), and the core's `CORE_RESET → CORE_FETCH` transition is the
  full reset behavior. The architecturally-correct sequence is a
  Phase 8 deliverable along with the rest of the trap/interrupt
  subsystem.
- **Rationale**: The reset-fetch sequence depends on the trap-table
  layout, the I/O register page address, and the bus-cycle ordering
  rules, all of which are Phase 6+ work. Implementing it now would
  pin in dependencies that don't yet exist. The parameterized
  `RESET_PC` keeps the test surface easy to reason about.
- **How to apply**: When Phase 8 lands, replace `RESET_PC` with the
  vector-table address and add a `CORE_RESET → CORE_FETCH_VECTOR →
  CORE_LOAD_VECTOR → CORE_FETCH` sub-sequence in the core FSM. Any
  test that relied on `RESET_PC = '0` must be updated. Open question
  in this entry until then: the exact address of the reset slot
  (`0xFFFFFFC0`, `0xFFFFFFE0`, or other — the bibliography is unsure).

---

## A0009 — ALU flag-update convention before per-instruction read
- **Date**: 2026-05-12
- **Status**: active, **TODO/spec-uncertain** (per-instruction nuances)
- **Source**: `third_party/TMS34010_Info/bibliography/hdl-reimplementation/02-instruction-set.md`
  ("Instructions document which flags they affect; some pixel ops set
  flags based on the last pixel transferred or the comparison result
  against the window rather than on a regular ALU outcome — read
  SPVU001A entries individually."); 03-registers.md ("Condition flags
  N, C, Z, V from the ALU").
- **Assumption**: Until each instruction's flag entry in SPVU001A
  Appendix A is read individually, the ALU computes flags using the
  obvious two's-complement convention:
  - Arithmetic: N = result[31], Z = (result == 0), C = unsigned overflow
    (carry out of bit 31 for ADD; *borrow* = `!carry-out-of-(a + ~b + 1)`
    for SUB), V = signed overflow (operand-sign agreement-disagreement
    rule).
  - Logical: N = result[31], Z = (result == 0), C = 0, V = 0.
  - PASS: N = src[31], Z = (src == 0), C = 0, V = 0.
- **Rationale**: This is the convention SPVU001A almost certainly
  documents (it's the convention shared by every contemporary CPU TI
  had on staff), and any per-instruction quirks (MOVE's flag policy,
  ABS's V-on-MIN-NEG, CPW's window-relative flag semantics, etc.) are
  per-instruction concerns that surface in Phases 4+ when those
  instructions land.
- **How to apply**: When implementing each instruction in decode, cite
  the SPVU001A appendix entry and update `docs/instruction_coverage.md`
  with the exact flag list. If the spec disagrees with this ALU's
  default flag-update, either (a) update the ALU op enum to add a
  variant that matches, or (b) override flags in the surrounding
  control logic.

---

## A0010 — Status-register bit layout placeholder
- **Date**: 2026-05-12
- **Status**: active, **TODO/spec-uncertain**
- **Source**: `third_party/TMS34010_Info/bibliography/hdl-reimplementation/03-registers.md`
  §"Status register" ("Read SPVU001A Chapter 2 for the exact bit
  layout").
- **Assumption**: Until SPVU001A Ch. 2 is read, the N/C/Z/V flag bit
  positions in ST are placeholders defined in `tms34010_pkg.sv`:
  `ST_N_BIT = 31`, `ST_C_BIT = 30`, `ST_Z_BIT = 29`, `ST_V_BIT = 28`.
  Field-mode bits (FE0/FE1 + extension bits), interrupt enables (E,
  IE), and privilege bits are not yet allocated to specific positions;
  the unused bits hold whatever was last written via `st_write_en`.
- **Rationale**: Consumers in the rest of the design reference the
  ST module's named outputs (`n_o`/`c_o`/`z_o`/`v_o`), so the bit
  positions are visible only to PUSHST / POPST / MMTM ST / MMFM ST
  (Phase 4) and to debug. Picking placeholders lets Phase 2 close
  without blocking on the spec read; only the parameters change when
  the layout is confirmed.
- **How to apply**: When SPVU001A Ch. 2 is read, update the four
  `ST_*_BIT` parameters and add positions for FE0/FE1, IE/E, and any
  other bits. Re-run `tb_status_reg`. Add an entry to
  `docs/instruction_coverage.md` for PUSHST/POPST when those land.

---

## A0011 — MOVI flag-update convention
- **Date**: 2026-05-12
- **Status**: active, **TODO/spec-uncertain**
- **Source**: `third_party/TMS34010_Info/tools/assembler/TMS34010_Assembly_Language_Tools_Users_Guide_SPVU004.pdf`
  page describing MOVI ("Move Immediate - Short or Long"). The text
  documents the operation but does not explicitly enumerate flag
  effects; the closely-paired MOVK entry explicitly notes "this
  instruction does not affect the status register", suggesting by
  contrast that MOVI DOES.
- **Assumption**: MOVI IW updates flags from the moved value: N =
  result[31], Z = (result == 0), C = 0, V = 0. This matches the
  default ALU PASS_B flag behavior in `tms34010_alu.sv`.
- **Rationale**: The spec strongly hints at flag effects via the MOVK
  contrast. Common convention for "move" instructions across CPU
  families with separate K-class encodings is "K instructions don't
  affect flags; I instructions do". Until SPVU001A Appendix A is
  read, this is the working convention.
- **How to apply**: When SPVU001A's MOVI entry is read, if it
  documents different flag behavior, only `decoded_instr_t.wb_flags_en`
  for `INSTR_MOVI_IW` in the decoder needs to change (and any
  per-flag suppression added). `tb_movi` already checks all four
  flags so a regression will catch any update.

## A0012 — MOVI IW encoding extracted from SPVU004 listings
- **Date**: 2026-05-12
- **Status**: active
- **Source**: `third_party/TMS34010_Info/tools/assembler/TMS34010_Assembly_Language_Tools_Users_Guide_SPVU004.pdf`
  pages with assembler listings, e.g. `MOVI pbuf_sz, A4 → 0x09C4 0005`
  (page near line 1357 in pdftotext output) and `MOVI array_size, A2
  → 0x09C2 0x0640` (page near line 3823). Cross-referenced against the
  bibliography's note in `02-instruction-set.md` §"Encoding shape"
  that long-immediate forms are "16-bit opcode + 16 or 32 bits of
  immediate data".
- **Conclusion**: `MOVI IW K, Rd` encodes as:
    bits[15:6] = 10'b00_0010_0111  (= 0x027)
    bit[5]     = 0                  (1 = MOVI IL, 32-bit immediate)
    bit[4]     = R                  (file: 0 = A, 1 = B)
    bits[3:0]  = N                  (register index 0..15; idx 15 = SP alias)
  Followed by one 16-bit word containing the immediate, sign-extended
  to 32 bits on writeback.
- **How to apply**: If a different encoding is discovered when
  SPVU004 Appendix B is read in full, update `tms34010_decode.sv`'s
  `MOVI_TOP10` constant and the `bit[5]` test. `tb_movi`'s
  `movi_iw_enc` helper would need the same update.

---

## A0013 — MOVK K=0 semantics + encoding
- **Date**: 2026-05-12
- **Status**: active (encoding confirmed; K=0 semantics is a working hypothesis)
- **Source**: `third_party/TMS34010_Info/tools/assembler/TMS34010_Assembly_Language_Tools_Users_Guide_SPVU004.pdf`
  pages containing:
  - "MOVK K, Rd. Move Constant - 5 Bits. Operation: K → Rd. Move a
    5-bit constant into the destination register. Note that this
    instruction does not affect the status register."
  - Assembler listings: "MOVK 1, A12 → 0x182C" and
    "MOVK 8, B1 → 0x1911".
- **Conclusion**: `MOVK K, Rd` encodes as:
    bits[15:10] = 6'b000110  (= 0x06)
    bits[9:5]   = K          (5-bit unsigned)
    bit[4]      = R          (file: 0 = A, 1 = B)
    bits[3:0]   = N          (register index 0..15)
  Operation: zero-extend K to 32 bits → Rd. Status register
  unchanged.
- **K=0 hypothesis**: Per the manual text "Move a 5-bit constant",
  K=0 is treated as the literal value 0 (clearing the register).
  Some other K-form instructions in the TMS34010 ISA (notably ADDK
  and SUBK) special-case K=0 to mean K=32 because adding/subtracting
  0 would be a no-op; MOVK has no such no-op concern since "move 0"
  is a useful operation in its own right. SPVU001A Appendix A should
  be consulted to confirm.
- **How to apply**: The implementation treats K=0 as literal 0. If
  SPVU001A documents otherwise, change the K-extension in
  `tms34010_decode.sv`'s MOVK arm and the alu_b mux for INSTR_MOVK
  in `tms34010_core.sv`. `tb_movk` includes a `MOVK 0, A1` test
  case that will catch the regression.

---

## A0014 — SPVU001A Appendix A encoding chart confirmed available
- **Date**: 2026-05-12
- **Status**: resolved (source confirmed)
- **Source**: `third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf`
  pages A-14 through A-15 contain the "General Instructions" 16-bit
  opcode-chart table for every '34010 mnemonic. Extracted to
  `/tmp/spvu001a.txt` via `pdftotext -layout` and verified against
  cross-references (e.g. ADD Rs,Rd matches the assembler-listing
  encoding `0x4022` for `ADD A1,A2`).
- **Conclusion**: Future instruction implementations should cite the
  SPVU001A A-14 chart row for their encoding rather than re-deriving
  from assembler listings. This is the authoritative source.
- **Architectural note from the chart**: TMS34010 reg-reg instructions
  (ADD, ADDC, AND, ANDN, CMP, MOVE, XOR, MPYS/MPYU, DIVS/DIVU, ...)
  share a single R bit (bit[4]) governing the file for BOTH Rs and
  Rd. This means **Rs and Rd of a reg-reg op MUST be in the same
  file** (A or B). Some MOVE variants and `EXGF` may use the
  cross-file form in different bit positions; verify per-instruction.

## A0015 — ADD Rs, Rd encoding (SPVU001A A-14)
- **Date**: 2026-05-12
- **Status**: active
- **Source**: SPVU001A Appendix A, page A-14:
    `ADD Rs,Rd    Add Registers    0100 000S SSSR DDDD    NCZV`
- **Conclusion**:
    bits[15:9] = 7'b0100000 (= 0x40)
    bits[8:5]  = Rs index (4 bits; Rs file = R bit below)
    bit[4]     = R          (file: 0 = A, 1 = B; for BOTH Rs and Rd)
    bits[3:0]  = Rd index (4 bits)
  Operation: Rs + Rd → Rd. Flags: N, C, Z, V from the sum.
- **How to apply**: Verified against hand-computed
  `ADD A1,A2 = 0x4022` and `ADD B5,B7 = 0x40B7` in
  `tb_add_rr.sv`. If the chart row's "SSSR DDDD" interpretation
  proves wrong (e.g. if there's a separate Rs file bit), update
  decode and the test's encoding helper together.

---

## A0016 — JRUC short displacement: bit-target = PC_post_fetch + disp8*16
- **Date**: 2026-05-12
- **Status**: active
- **Source**: SPVU001A Appendix A page A-14 row `JRcc Address ... 1100 code xxxx xxxx`; cross-checked against SPVU004 assembler listing `JRGT L5 = 0xC70B` at bit-address 0x3B0 with label L5 at bit-address 0x470 (disp value `0x0B` × 16 = `0xB0`, target `0x3B0 + 0x10 + 0xB0 = 0x470` ✓).
- **Conclusion**: For JRcc short form `1100 cc dddd_dddd`, the new PC is `PC_after_fetch + sign_extend(disp8, 32) * 16`. Implementation: `branch_target = pc_value + $signed({disp8, 4'b0000})`, computed combinationally and applied via the PC module's `load_en`/`load_value` ports in `CORE_WRITEBACK`.
- **How to apply**: When future JRcc variants (conditional, long, absolute) land, reuse the same `branch_target_short` form for short and add separate paths for long (16-bit disp) and absolute (32-bit target). All conditional variants share the cc-decoding from Table 12-8 (SPVU001A §12).

---

## A0017 — JRcc condition codes (subset implemented)
- **Date**: 2026-05-12
- **Status**: SUPERSEDED by A0023 (Task 0030). The "EQ=0100, NE=0111" guesses recorded here turned out to be WRONG — those codes are actually LT and GT. A0023 captures the corrected table; this entry is preserved for historical context.
- **Source**: SPVU001A §12.7 + Table 12-8 "Condition Codes for JRcc and JAcc Instructions" (page 12-31).
- **Original conclusion (verified subset only)**:
  - `cc = 0000` → UC (unconditional, always)  [CORRECT — preserved in A0023]
  - `cc = 0100` → EQ / Z (Z = 1)              [**WRONG** — actually LT]
  - `cc = 0111` → NE / NZ (Z = 0)             [**WRONG** — actually GT]
  Task 0027 added LO=0001, LS=0010, HI=0011, HS=1001 — those four happened to be correct.
- **Note**: the prior PDF extraction (without `-layout`) collapsed Table 12-8 into unparseable columns, which led to the guess. A clean re-extraction with `pdftotext -layout` on the long-form JRcc page (12-96) yielded the unambiguous table now recorded in A0023.

---

## A0018 — ADDK / SUBK K-value treatment
- **Date**: 2026-05-12
- **Status**: active (encoding + literal-K behavior confirmed; K=0 → 32 hypothesis NOT implemented)
- **Source**: SPVU001A A-14 chart rows:
    `ADDK K,Rd  Add Constant (5 Bits)   0001 00KK KKKR DDDD   NCZV`
    `SUBK K,Rd  Subtract Constant (5)   0001 01KK KKKR DDDD   NCZV`
  Plus SPVU004 description "Add Constant (5 Bits) ... K + Rd → Rd" (no
  mention of K=0 special case).
- **Conclusion (implemented)**:
  - Encoding: bits[15:10] = `6'b000100` (ADDK) or `6'b000101` (SUBK);
    bits[9:5] = K (5-bit unsigned); bit[4] = R; bits[3:0] = Rd idx.
  - ADDK operation: zero_extend(K, 32) + Rd → Rd.
  - SUBK operation: Rd - zero_extend(K, 32) → Rd. Flags: standard
    N/C/Z/V from the result (C is borrow for SUBK).
- **K=0 hypothesis (NOT implemented)**: Some TI K-form ISAs special-
  case K=0 to mean K=32 (giving useful "add 32" / "subtract 32"
  efficiency, since adding/subtracting literal 0 would be a no-op).
  SPVU004's prose for ADDK/SUBK does not mention this; SPVU001A
  pages on these instructions specifically would need a careful
  visual read to confirm. The implementation treats K=0 literally
  (ADDK 0 = no-op, SUBK 0 = no-op).
- **How to apply**: If SPVU001A turns out to specify K=0 → K=32 for
  these instructions, change the decoder K-zero-extension or the
  alu_b mux entry to substitute 32'd32 for the K=0 case. `tb_addk_subk`
  deliberately avoids K=0 to keep behavior unambiguous; add a
  failing K=0 test case as a regression once the spec is confirmed.

---

## A0019 — Shift K-value treatment
- **Date**: 2026-05-12
- **Status**: active (encoding confirmed; literal-K behavior implemented; K=0 → 32 hypothesis deferred)
- **Source**: SPVU001A A-14 chart rows for SLA/SLL/SRA/SRL/RL K-form,
  plus SPVU001A §12.8 "Shift Instructions" prose ("the shift amount
  is specified by the value of a 5-bit constant"). Note the related
  prose for Rs-form shifts: "the SRA Rs, Rd and SRL Rs, Rd use the
  2s complement value of the 5 LSBs in Rs" (i.e., right-shift Rs-form
  has a sign-aware shift-count interpretation that doesn't apply to
  the K-form).
- **Conclusion (implemented)**: K is treated as a literal 5-bit
  unsigned shift count in the range 0..31. The shifter module's
  `amount=0` case is a passthrough — the value is unchanged and C=0.
- **K=0 hypothesis (NOT implemented)**: TI K-form shift instructions
  in some related families special-case K=0 to mean K=32, providing
  efficient "zero out the register" (SLL 32) / "broadcast sign bit"
  (SRA 32) operations. SPVU001A's chart row and the §12.8 prose do
  not explicitly state this for the '34010 K-form. Without an
  explicit chart-side note, the implementation follows the literal
  interpretation — same policy as ADDK/SUBK (A0018).
- **How to apply**: If a careful read of SPVU001A §12.8 + Appendix A
  individual instruction entries documents K=0 → K=32, change the
  shifter wrapper (or pass an amount of `decoded.k5 == 0 ? 5'd32 :
  decoded.k5` — note this requires widening `SHIFT_AMOUNT_WIDTH`
  past 5 to encode the value 32). `tb_shift_k` deliberately
  avoids K=0; add failing K=0 vectors as the regression once the
  spec is confirmed.

---

## A0020 — MOVE family encodings (and a corrected reg-to-reg opcode)
- **Date**: 2026-05-12; **CORRECTED 2026-05-30 (Task 0058)**.
- **Status**: reg-to-reg MOVE resolved/implemented at the correct opcode; field-size machinery for the *indirect/field* MOVE variants still deferred.
- **Source**: SPVU001A page 12-126 (MOVE Rs,Rd detail) + the Move-Instructions summary table, cross-checked against BOTH the 1986 first edition (`1986_SPVU001...`) and the 1988 User's Guide. Object-code example Figure 12-3: `MOVE A0,B1 = 0x4E01`.
- **CORRECTION**: the original A0020 misread the "A-14" chart. It took the row `1001 00FS SSSR DDDD` to be reg-to-reg MOVE; that row is actually **MOVE Rs,\*Rd+** (postincrement register-to-indirect, a memory *store*). Register-to-register MOVE is **`0100 11MS SSSR DDDD`** (base 0x4C00). The decoder and every stack testbench that set SP via "MOVE A0,A15" used the wrong 0x9000 opcode; they "passed" only because decoder + tests shared the same wrong encoding. Task 0058 relocates reg-to-reg MOVE to 0x4C00, adds the M-bit cross-file support, and fixes all affected testbenches.
- **Reg-to-reg MOVE (now implemented, Task 0058)**: `0100 11MS SSSR DDDD`. NOT a field move — full 32-bit copy, field size has no effect, so there is **no F bit**. M=bit[9]: 0 ⇒ same file, 1 ⇒ cross-file. R=bit[4]: file for both (M=0) or the *source* file (M=1; destination is the other file). This is the only MOVE that crosses register files. Status: N=data[31], Z=(data==0), V=0, C Unaffected. New struct field `rs_file` carries the (possibly different) source file; the core reads it for `rf_rs1_file` only on `INSTR_MOVE_RR`.
- **Indirect MOVE forms implemented (FS=32 only)**: register↔indirect (plain/postinc/predec, Tasks 0059/0060) and indirect↔indirect (plain Task 0061; postinc/predec Task 0062) are done for field-size 32, word-aligned. The F bit and runtime FS0/FS1 are ignored — at FS=32 the field fills the 32-bit word so FE is a no-op. **Rs==Rd corner (indirect-to-indirect inc/dec):** for postincrement the spec (12-138) defines it — data written to the incremented location, register steps once — and the implementation matches it. For *predecrement* with Rs==Rd the spec is silent; the implementation single-steps the register and the write address ends up doubly-decremented (a documented deviation, pathological case).
- **Still deferred**: arbitrary field sizes (1..31), unaligned pointers, fields straddling word boundaries, FE sign/zero extension, and the MOVE offset/absolute addressing modes. That hardware (field-extract/insert + a memory model beyond 16/32-bit aligned access) is the real "Phase 6" work; those opcodes fall through to ILLEGAL until built. See [[a0026-mmtm-mmfm-mask-mapping]] for the related multi-register moves (already done).
- **Field-machinery progress (Task 0076)**: the memory-model half of the deferred field machinery now exists — `sim_memory_model` reads/writes 1..32-bit fields at any bit address, straddling word boundaries, with read-modify-write preservation (tb_mem_field). This is sim-only; the core still issues only aligned 16/32-bit accesses. The remaining core-side work (issue mem_size=FS, FE-driven sign/zero extension on loads, FS-aware ±pointer step) is the next increment of the arc.
- **Field-machinery progress (Task 0077)**: the register↔indirect MOVE forms (FIELD_STORE/FIELD_LOAD: plain, postinc, predec) are now **field-size aware**. The core derives `mv_fs`/`mv_fe` from the F-selected ST pair (FS0/FE0 or FS1/FE1; FS=0 ⇒ 32), drives `mem_size = mv_fs`, sign/zero-extends loads (`mv_load_data`) per FE, and steps pointers by ±FS. Unaligned/straddling fields are handled by the Task 0076 memory model. **Consequence**: because MOVE now honors the actual FS, the existing FS=32 round-trip tests (tb_move_indirect, tb_move_indirect_incdec) had to issue `SETF FS0=0` first — the reset ST has FS0=16, so without it those moves would transfer 16 bits. **Still FS=32-only**: the M2M (indirect↔indirect), offset, and absolute MOVE forms — their field-awareness is a later task.
- **Field-machinery progress (Task 0078)**: the OFFSET (0xB000/0xB400) and ABSOLUTE (0x0580/0x05A0) MOVE forms are now field-size aware too — same `mv_fs`/`mv_load_data` machinery (no pointer step). tb_move_offset / tb_move_abs now SETF FS0=0 up front; new tb_move_offabs_field covers FS=8/16 and an FS=12 straddling absolute field.
- **Field machinery COMPLETE for MOVE (Task 0079)**: the M2M (indirect↔indirect) forms (0x8800/0x9800/0xA800) are now field-size aware — both steps of the 2-step CORE_MEMORY sequence use `mem_size = mv_fs` (read FS bits into move_data_q, write its low FS bits), and both pointers step by ±FS. No FE extension (mem→mem). tb_move_m2m / tb_move_m2m_incdec now SETF FS0=0; new tb_move_m2m_field covers FS=8 plain/postinc and an FS=12 copy with both src and dst fields straddling word boundaries. **All MOVE addressing forms now honor arbitrary FS 1..31 + FE, unaligned, and word-straddling fields.** The remaining field-related item is **MOVB** (byte move, FS fixed at 8 — a thin decode layer that forces FS=8 over this machinery, independent of ST).
- **MOVB implemented (Task 0080)**: a new `decoded.force_byte` flag forces FS=8 (`mv_fs`) and, for loads, FE=sign-extend (`mv_fe=1`) regardless of ST — MOVB loads are always right-justified and sign-extended with implicit compare-to-0 (SPVU001A 12-120). 7 of MOVB's 9 forms reuse the MOVE field/offset/absolute datapaths: Rs,*Rd (0x8C00) / *Rs,Rd (0x8E00) / *Rs,*Rd (0x9C00) / Rs,*Rd(off) (0xAC00) / *Rs(off),Rd (0xAE00) / Rs,@DAddr (0x05E0) / @SAddr,Rd (0x07E0). MOVB has no auto inc/dec. The store/load indirect forms differ in bit9 so they decode on top7; the absolute forms live in the 0000-01.. family at sub-op instr[7:5]=111 (store bit9=0 / load bit9=1). **Deferred** (need new multi-word datapaths, like the niche MOVE forms): MOVB *Rs(SOff),*Rd(DOff) (0xBC00, offset-to-offset) and MOVB @SAddr,@DAddr (0x0340, abs-to-abs) — both currently trap as illegal.

---

## A0021 — NOP encoding = 0x0300 (single fixed encoding)
- **Date**: 2026-05-12
- **Status**: resolved against SPVU001A §"NOP" page 12-170 and the instruction-summary table on the same page (mnemonic, full 16-bit encoding `0000 0011 0000 0000`).
- **Source**: `third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf` §"NOP" page 12-170. Description: "The program counter is incremented to point to the next instruction. The processor status is otherwise unaffected."
- **Conclusion**: NOP is a single fixed 16-bit opcode `0x0300`, not an alias of another instruction. ST is NOT updated; no register is written; the only architectural effect is PC advancing by one instruction word.
- **Why this matters**: The encoding superficially looks like it could be part of the unary family (`0000 0011 1xxx xxxx`, page A-14 — top9 = `9'b000000111`). It is NOT — NOP's top9 is `9'b000000110` (bit[7]=0). ABS A0 has the same alphanumeric "0x0300" mnemonic flavor but is actually `0x0380` (bit[7]=1 to enter the unary family). The decoder treats them as fully disjoint encodings.
- **How to apply**: Recognize `instr == 16'h0300` directly. Both writeback gates stay 0; PC advance is the only effect, and that happens for free via the FETCH-ack pulse.

---

## A0023 — JRcc / JAcc condition codes resolved against the spec table
- **Date**: 2026-05-12
- **Status**: resolved against SPVU001A Table 12-8, re-extracted with `pdftotext -layout` from the long-form JRcc page (page 12-96 of the 1988 User's Guide). The same table appears on the short-form JRcc page (12-95) with identical codes.
- **Source**: `third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf` Table 12-8 "Condition Codes for JRcc and JAcc Instructions".
- **Correction**: the prior A0017 guess of EQ=0100 / NE=0111 was wrong. The correct table is:

  | Code (binary) | Mnemonic | Aliases   | Status-bit condition          | Type     |
  |---------------|----------|-----------|--------------------------------|----------|
  | 0000          | UC       |           | (always)                       | uncond   |
  | 0001          | LO       | B         | C = 1                          | unsigned |
  | 0010          | LS       | YLE       | C \| Z = 1                     | unsigned |
  | 0011          | HI       | YGT       | ~C & ~Z = 1                    | unsigned |
  | 0100          | LT       | XLE       | (N ^ V) = 1                    | signed   |
  | 0101          | GE       | XGT, YZ   | (N ^ V) = 0                    | signed   |
  | 0110          | LE       |           | (N ^ V) \| Z = 1               | signed   |
  | 0111          | GT       |           | ~(N ^ V) & ~Z = 1              | signed   |
  | 1001          | HS       | NC        | C = 0                          | unsigned |
  | 1010          | EQ       | Z         | Z = 1                          | equality |
  | 1011          | NE       | NZ        | Z = 0                          | equality |

  Codes not listed (1000, 1100..1111) are V/NV/P/N and the JRYxx XY-compare codes, deferred for a later task.
- **Implementation**: the package `CC_*` parameters were re-pointed at the correct codes. The decoder accepts the 11 codes above; other JRcc-shape codes still fall through to ILLEGAL (defensive). The core's `branch_taken` evaluator gained four new arms for LT/LE/GT/GE.
- **Tests**: `tb_jrcc_signed.sv` exercises all four signed cc's both directions; `tb_jrcc_short.sv` and `tb_jrcc_unsigned.sv` continue to pass with the corrected EQ/NE constants (their encoding helpers compose the cc by name, so changing the constant value made the assembled instructions match the spec).
- **Lesson** (also captured in the `pdf-layout-for-charts` memory): always use `pdftotext -layout` for tabular spec material. The original extraction without `-layout` is the root cause of the bug fixed here.

---

## A0022 — ADDC / SUBB carry-in / borrow-in semantics resolved against SPVU001A
- **Date**: 2026-05-12
- **Status**: resolved against SPVU001A pages 12-37 (ADDC) and 12-248 (SUBB), plus the instruction-summary table.
- **Source**: `third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf` §"ADDC" page 12-37 and §"SUBB" page 12-248.
- **Conclusion**:
  - ADDC: `Rd = Rs + Rd + C`. Flags N, C, Z, V from the 33-bit sum.
  - SUBB: `Rd = Rd - Rs - C`. Flags N, C, Z, V; C is the borrow-out from the 33-bit subtractor `(a + ~b + (1 - cin))`.
  - C means: for SUB/SUBB, "1 if there is a borrow, 0 otherwise" (quoted from the SUBB page 12-248 prose). The ALU already implements this convention (page A0009 records it).
- **Test-vector source**: SPVU001A page 12-248 supplies 14 worked SUBB examples covering positive/negative operands, both cin values, and the signed-overflow corner case `0x7FFFFFFE - 0xFFFFFFFE` (row 7 in the spec table). `sim/tb/tb_addc_subb.sv` uses row 7 as its signed-overflow check.
- **How to apply**: The ALU already does the right thing for `ALU_OP_ADDC` and `ALU_OP_SUBB`; decoder selects them and core-side operand routing follows the existing SUB pattern (alu_a = Rd, alu_b = Rs) for SUBB. ADDC uses the default routing because the operation is commutative on its register operands.

---

## A0010 — RESOLVED: status-register bit positions
- **Date resolved**: 2026-05-14 (Task 0042)
- **Status**: **RESOLVED** against SPVU001A §5.2 Table 5-2 (page 5-18).
- **Original placeholder**: A0010 had N/C/Z/V at bits 31..28 as a guess.
- **Verified layout** (now baked into `rtl/tms34010_pkg.sv`):
  - bits[4:0]  = FS0  (5-bit field-size 0; encoding `00000` → size 32)
  - bit[5]     = FE0
  - bits[10:6] = FS1
  - bit[11]    = FE1
  - bits[12:20]= reserved
  - bit[21]    = IE  (interrupt enable; DINT clears, EINT sets)
  - bits[22:24]= reserved
  - bit[25]    = PBX (PixBlt Executing)
  - bits[26:27]= reserved
  - bit[28]    = V
  - bit[29]    = Z
  - bit[30]    = C
  - bit[31]    = N
- **Reset value**: ST resets to `0x0000_0010` per spec page 5-18 — i.e., FS0 = 16, all flags clear. `tms34010_status_reg.sv` now uses `ST_RESET_VALUE = 32'h0000_0010` from the package.
- **Lesson**: the N/C/Z/V placeholders happened to be right; FS/FE/IE/PBX are now anchored to authoritative bit positions for use by SETF, EXGF, SEXT, ZEXT, MOVE-field, DINT/EINT, and PIXBLT-related instructions.

---

## A0025 — REV constant and EXGPC bottom-nibble PC alignment
- **Date**: 2026-05-12
- **Status**: active (pending a careful spec re-read on a clean PDF)
- **Source**: SPVU001A page 12-233 (REV) and the corresponding EXGPC page.
- **REV constant**: The spec's bit-format chart for REV is largely "undefined", but the worked example on page 12-233 explicitly shows `REV A1 → 0x0000_0008`. The implementation emits the constant `32'h0000_0008` (chip revision 8). If a different revision is later required, change the `INSTR_REV` arm in `tms34010_core.sv`'s `rf_wr_data` mux.
- **EXGPC bottom-nibble mask**: TMS34010 PC values are word-aligned (the low 4 bits of an externally-loaded PC are forced to 0). JUMP Rs and JAcc both do this explicitly per their spec pages. EXGPC is in the same class — when PC is loaded from Rd, the low 4 bits are likewise masked. The implementation does `pc_load_value = {rf_rs2_data[31:4], 4'h0}`. The Rd-receives-PC half of the swap is NOT masked (Rd just holds the full pre-swap PC value).
- **How to apply**: If a future spec re-read finds a different revision number or a different alignment convention for EXGPC, adjust `tms34010_core.sv` accordingly and update the `tb_pc_ops.sv` checks. The current values are the most defensible read of the 1988 User's Guide.

---

## A0024 — ABS clears ST.C (spec says "Unaffected"); RESOLVED by Task 0037
- **Date**: 2026-05-12
- **Status**: **RESOLVED** in Task 0037 (commit hash recorded in tasks.md). A `wb_flag_mask : alu_flags_t` field was added to `decoded_instr_t`, and `tms34010_status_reg.sv` now gates each of N/C/Z/V independently with `flag_update_mask`. The decoder's ABS arm sets `wb_flag_mask = '{n:1, c:0, z:1, v:1}`, so ABS now correctly leaves C "Unaffected" per SPVU001A page 12-34. BTST (Task 0037) uses the same mask machinery with `'{n:0, c:0, z:1, v:0}` for its spec-mandated Z-only update; `tb_btst.sv` directly verifies that N, C, V are preserved across a BTST when set via a prior CMP.
- **Source**: SPVU001A page 12-34 ("Store Absolute Value") — "C Unaffected".
- **Original deviation**: the ALU arm was forced to assign `flags.c = 1'b0` because `wb_flags_en` was all-or-nothing. Now `flags.c` from the ALU is still 0 (defensive default), but the mask blocks the update so C retains its prior value.
- **How to apply going forward**: any new instruction whose spec lists a flag as "Unaffected" should override `wb_flag_mask` in its decoder arm. The default initialization in the decoder's always_comb sets the mask to all-ones, so arithmetic instructions continue to update all four flags without explicit `wb_flag_mask` lines.

## A0026 — MMTM / MMFM mask bit-to-register mapping
- **Date**: 2026-05-30 (Task 0055).
- **Status**: **confirmed** as of Task 0056 (2026-05-30). The
  graphical mask chart on SPVU001A page 12-110 / 12-112 still does
  not survive `pdftotext -layout` extraction, but the worked MMFM
  example on page 12-110 (text + published register results, which
  *did* extract) pins the mapping down absolutely: `MMFM B0, {B1,
  B2,B4,B8,B12,B13,B14,SP}` with mask 0xF116 produces exactly TI's
  listed results (SP=FFFFBFBF restored from the lowest address,
  B1=1111B1B1 from the highest), which is only consistent with
  **bit N = R(N)**, not the bit N = R(15-N) alternative. tb_mmfm
  subtest (1) checks this bit-for-bit, so the assumption is now
  test-locked, not just self-consistent.
- **Assumption**: **bit N of the mask = register R(N)**, identical
  for both MMTM and MMFM. Iteration direction differs by spec:
  MMTM iterates LSB → MSB (lowest-order register pushed first);
  MMFM iterates MSB → LSB (highest-order register restored first).
- **Justification**: this reading is self-consistent — an MMTM
  followed by an MMFM with the same mask losslessly round-trips
  the register list. The TMS34010 example on page 12-111
  (`MMTM A1, A0,A2,A4,A8,A12,A13,A14,SP`) doesn't show the
  encoded mask word, so it can't directly disprove the
  alternative mapping (bit N = R(15-N)).
- **How to apply going forward**: tb_mmtm and any future MMFM
  testbench should round-trip via MMTM→MMFM (catches internal
  inconsistency even if the bit-to-register mapping doesn't
  match TI's actual convention). If we later learn the TI
  convention differs, the fix is a single line: invert the
  index used to drive `rf_rs1_idx` in core.sv.
- **Spec source**: SPVU001A pages 12-109..12-112 (MMFM / MMTM).

## A0027 — SUBXY / CMPXY greater-than comparison is unsigned
- **Date**: 2026-05-31 (Task 0066).
- **Status**: provisional (pending MAME cross-check).
- **Source**: SPVU001A page 12-252 (SUBXY) Status Bits: "C: 1 if source
  Y field > destination Y field", "V: 1 if source X field > destination
  X field" — plus the worked example table on the same page.
- **Assumption**: the `>` comparisons are UNSIGNED. SUBXY computes
  Rd - Rs per 16-bit half; the spec's "(Rs > Rd)" for C/V is then exactly
  the unsigned borrow out of (Rd - Rs), i.e. `Rd < Rs` unsigned — which is
  how the core computes them (`xy_rd_x < xy_rs_x`, `xy_rd_y < xy_rs_y`).
  N/Z are equality (Xres==0 / Yres==0), which is signedness-independent.
- **Why uncertain**: TI's example table uses only small positive values
  (0..0x10) that don't distinguish signed vs unsigned `>`. XY screen
  coordinates are sometimes treated as signed for clipping.
- **How to apply**: if a MAME/silicon cross-check shows signed comparison,
  change the two `<` comparisons in the `subxy_flags` assign (core.sv) to
  signed (`$signed(...) <`). CMPXY (future task) shares this convention.

## A0028 — I/O register integration into the core memory path
- **Date**: 2026-05-31 (Task 0082).
- **Status**: implementation choice; faithful at the architectural level,
  with a deferred refinement noted.
- **Source**: SPVU001A §6 "I/O Registers", Figure 6-1; "An access of any
  address in the range C0000000h-C00001FFh is decoded as an access of an
  on-chip register" and "the accompanying memory cycle ... is altered so
  that RAS is output but CAS is inhibited".
- **Choice**: `tms34010_io_regs` is instantiated inside `tms34010_core`.
  An access whose address decodes as I/O space (`io_is_io`) is serviced
  on-chip: the external write is gated off (`mem_we = mem_we_int &&
  !io_is_io`) so an I/O write never reaches external RAM, and the read data
  is muxed from the register file. Because the I/O register is async-read
  (it follows `mem_addr`) while the external model holds `mem_rdata` stable
  into WRITEBACK, the I/O read is latched at the access ack (`io_rdata_q` /
  `io_is_io_q`) and the effective-read mux uses the combinational decode
  during an active transaction (`mem_req` high) and the latched value after
  it retires.
- **Deferred refinement**: the core still ISSUES an external bus cycle for
  I/O accesses (with write disabled), rather than fully suppressing it and
  generating an on-chip ack. This matches the spec's "RAS output, CAS
  inhibited" external cycle closely enough and lets the existing external
  memory model provide the ack. A dedicated memory-fabric module with an
  on-chip ack path is the eventual home for this. Also: I/O registers are
  16-bit and the core accesses them with 16-bit fields (the ISA uses 16-bit
  MOVE to I/O space); sub-16-bit field writes to I/O are not read-modify-
  write (they write the low 16 bits) and 32-bit accesses would span two
  registers — neither is exercised by the implemented instruction set.

## A0031 — Window checking: only W=3 (clip) implemented for FILL XY
- **Date**: 2026-06-07 (Task 0105).
- **Status**: partial implementation, explicitly scoped (NOT a silent stub).
- **Source**: 1988 UG §7.10 (Window Checking): W=0 off; W=1 hit detection
  (no draw, WV interrupt on a pixel inside); W=2 miss detection (abort + V-bit +
  WV interrupt on a pixel outside); W=3 window clipping (draw inside, skip
  outside). WSTART=B5/WEND=B6 are inclusive XY corners; WVP=INTPEND bit 11.
- **Implemented**:
  - **W=3 (clip)** for **FILL XY** (Task 0105) and **PIXBLT with an XY
    destination** (Task 0106). Each pixel's absolute XY = (DADDR.X + col,
    DADDR.Y + row); a pixel outside the inclusive [WSTART..WEND] rectangle is
    left unchanged (write-back of the read destination, the same skip path as
    transparency). PIXBLT preserves the raw XY DADDR (pblt_dst_xy_raw_q). Per
    §7.10.3, FILL/PIXBLT in W=3 set NO V-bit and raise no interrupt — matched.
  - **W=2 (miss detection)** for **FILL XY** (Task 0107) and **PIXBLT XY**
    (Task 0108). All-or-nothing rectangle containment (the array's corners vs
    [WSTART..WEND], evaluated at CORE_FILL_SETUP_WIN / CORE_PBLT_SETUP_WIN): if
    the whole array fits → drawn, V=0; else → NOT drawn (CORE_FILL_WIN_MISS /
    CORE_PBLT_WIN_MISS), V=1, and INTPEND.WV set (a one-cycle wvp_set side
    channel into tms34010_io_regs). The V write reuses the status-register
    flag-update port via the shared fill_win_flag_wb override.
  - **W=1 (hit detection)** for **FILL XY** (Task 0109) and **PIXBLT XY**
    (Task 0110). No pixels are ever drawn; the array's overlap with the window
    is tested (from the latched WSTART/WEND in CORE_FILL_WIN_HIT /
    CORE_PBLT_WIN_HIT). Overlap → V=0 and INTPEND.WV set (the "pick" found an
    object); entirely outside → V=1, no interrupt. Same shared V-write /
    wvp_set mechanism.
- **NOT implemented (deferred)**:
  - Window handling for LINE and PIXT (PIXT is per-pixel like DRAV; LINE aborts
    on a violation). DRAV and LINE are fully windowed: DRAV W=1/2/3 (0111/0112),
    LINE W=0 (0114) + W=3 clip (0115) + W=1/W=2 abort (0116, abort stops the
    loop + sets INTPEND.WV; the WVP interrupt is serviced by the maskable
    interrupt subsystem, whose pushed PC already points past the LINE). PIXT XY
    is now also windowed (Task 0117 — CORE_PIXT_SETUP_WIN reads WSTART/WEND,
    gated by pixt_xy_win so the shared MOVE path is otherwise untouched). **All
    drawing instructions now support window checking.**
  These behave as W=0 (no window) for the not-yet-covered instructions.
  **Recorded here, not silently stubbed; see docs/instruction_coverage.md.**

**Window checking is COMPLETE for both array engines**: FILL XY and PIXBLT XY
each implement all four CONTROL.W modes (W=0 off / W=1 hit / W=2 miss / W=3
clip), with the V-bit and WV-interrupt (INTPEND bit 11) semantics per §7.10.
- **How to apply / extend**: the clip predicate (fill_in_window / fill_clip_out)
  and the WSTART/WEND read (CORE_FILL_SETUP_WIN) in tms34010_core.sv are the
  template. W=2 adds "any pixel outside ⇒ V=1 + WVP"; W=1 adds "any pixel inside
  ⇒ WVP, draw nothing"; both tie into the now-complete interrupt subsystem
  (INTPEND bit 11 = INT_WV_BIT). Replicate the XY tracking for the PIXBLT engine
  (pblt_* already tracks its own col/row).

## A0030 — Maskable-interrupt entry clears only ST.IE (preserves other ST bits)
- **Date**: 2026-06-04 (Task 0100).
- **Status**: assumption (spec describes the push/vector sequence; the exact
  post-entry ST contents for a hardware interrupt are not quoted verbatim).
- **Source**: 1988 UG §8 (interrupt processing): "the PC and the ST are pushed
  onto the stack" on interrupt; RETI "restores the ST and PC"; "Assuming the IE
  bit in the restored ST is a 1, interrupts are again enabled."
- **Assumption**: the maskable-interrupt entry sequence pushes PC then ST,
  reads the trap vector into PC, and clears **only** ST.IE (masking nested
  maskable interrupts until RETI). The other ST bits (flags, FE/FS field-size
  pairs, PBX, etc.) are left unchanged — the full pre-interrupt ST is saved on
  the stack and restored by RETI, so the in-flight ST need not be reset.
- **Contrast with TRAP** (A0-none): TRAP replaces ST with ST_RESET_VALUE
  (0x10). A hardware interrupt is modeled here as preserving ST except IE,
  because (unlike a software TRAP that begins a fresh context) an interrupt
  transparently borrows the current thread and RETI must restore it exactly.
- **Why uncertain**: the User's Guide does not give a worked before/after ST
  for a hardware interrupt entry. If a cross-check shows the device also resets
  FE/FS on interrupt entry, change the CORE_INT_DONE st_write_data to
  ST_RESET_VALUE | (preserved bits).
- **How to apply**: the clear is at CORE_INT_DONE in `tms34010_core.sv`
  (`st_write_data = st_value & ~(1<<ST_IE_BIT)`).

## A0029 — FILL XY updates DADDR to a linear address
- **Date**: 2026-06-01 (Task 0088).
- **Status**: assumption (the spec's DADDR-update wording is shared between
  FILL L and FILL XY and is described in linear terms).
- **Source**: SPVU001A pages 12-80/12-82 (FILL L / FILL XY): "When the array
  transfer is complete, DADDR points to the linear address of the pixel
  following the last pixel written."
- **Assumption**: FILL XY converts the XY DADDR to a linear start address and
  then operates entirely in linear space; on completion the engine writes the
  **linear** address following the last pixel back to DADDR (B2), the same as
  FILL L. The spec describes the post-FILL DADDR as a linear address for both
  forms, so writing the linear value (not re-encoding it back to XY) matches
  the quoted text.
- **Why uncertain**: a strict reading might expect FILL XY to leave DADDR in
  XY format. No worked FILL XY before/after example was available to confirm.
- **How to apply**: if a cross-check shows DADDR should remain XY, add a
  reverse (linear→XY) conversion in CORE_FILL_WB for INSTR_FILL_XY.

## TODO / spec-uncertain (waiting on detailed read)

- Exact register file layout: how A15/B15 alias to SP, and how the B-file
  graphics control registers map (B0–B14 contents) — needs the User's
  Guide chapter on registers to be cited per-register.
- Exact status-register bit layout and flag semantics for arithmetic vs.
  logical ops — needed before Phase 2 ALU.
- Reset vector and reset-time register initialization values.
- Interrupt vector table layout and trap-entry sequence (Phase 8).
- Field-size 0 semantics (some TI parts treat it as 32, others as illegal).
- Bus cycle phasing for unaligned field accesses crossing a 16-bit external
  bus boundary (Phase 6).
