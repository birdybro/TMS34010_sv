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
- **Date**: 2026-05-12; refined 2026-07-28 (Tasks 0148 and 0155).
- **Status**: active
- **Source**: project convention (not in spec).
- **Assumption**: The integrated functional core hierarchy runs on one core
  clock. Task 0147 adds an original-pin engine clocked at eight times the
  local-clock rate, and Task 0148 connects it through the A0040 coherent CDC
  bridge. Task 0155 adds a separate video clock and the A0045 coherent
  core/VCLK boundary. No other implicit derived or fabric-gated clock is
  permitted.

## A0005 — Bit-addressed memory exposed at the interface boundary
- **Date**: 2026-05-12; **resolved 2026-07-28 (Task 0136)**.
- **Status**: **RESOLVED** against the primary memory-organization and
  arbitration text.
- **Source**: 1988 TI TMS34010 User's Guide §3.1, pages 3-2 through 3-3;
  §4.1, pages 4-2 through 4-5; and §11.3, page 11-4.
- **Resolution**: The core retains its 32-bit bit-address plus 1–32-bit field
  boundary. `tms34010_field_sequencer` translates each request into ascending
  aligned 16-bit physical-word cycles. The field's least-significant bit is
  at the requested bit address. Reads use one, two, or three word reads and
  return a masked, right-justified field. Writes directly replace every
  fully covered word and use read/modify/write only for partial first or last
  words, giving the guide's exact seven alignment cases A–G.
- **Atomicity**: Each partial-word read/modify/write pair exposes one
  indivisible `word_rmw_lock_o` interval. The lock may drop between different
  words of a multiword field, as §11.3 permits arbitration there. Task 0145
  implements the documented HOLD exception: a HOLD accepted after the read
  but before the write restarts the complete pair.
- **Regression evidence**: `tb_field_sequencer` verifies all A–G write
  sequences, one/two/three-word reads, arbitrary word-side stalls, stable
  request payload, and reset recovery. `tb_mem_field` verifies the retained
  core-side abstraction through the same sequencer. The complete Task 0136
  regression passes 121/121 benches.
- **Boundary**: This resolution covers architectural field alignment and
  physical-word sequencing. Arbitration and the standalone
  RAS/CAS/LCLK/LRDY/reset phase engine have since landed; their coherent CDC
  and system connection remain integration work, not an unresolved
  field-semantics assumption.

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

## A0008 — Reset PC and level-0 vector fetch
- **Date**: 2026-05-12; **resolved 2026-07-28 (Task 0121)**.
- **Status**: **RESOLVED** against the primary specification.
- **Source**: 1988 TI TMS34010 User's Guide §8.8, pages 8-10 through 8-13.
  Both self-bootstrap and host-present descriptions identify the level-0
  vector location as `0xFFFF_FFE0`; the initial-state description says PC
  contains the 32-bit value fetched there. Reset and TRAP 0 share this vector
  and neither saves the old PC or ST.
- **Implementation**: the PC flop still resets to `RESET_PC = 0` so its state
  is defined while synchronous `rst` is active. Once reset releases,
  `CORE_RESET` holds a normal 32-bit read at `RESET_VECTOR_ADDR` until
  `mem_ack`; the acknowledged data loads PC and the FSM enters `CORE_FETCH`.
  No PC advance, stack write, or SP update occurs. The bounded simulation
  memory provides a dedicated `level0_vector` word (default zero) so the high
  architectural address does not alias an ordinary low-memory program word.
- **Task 0142 refinement**: HCS-selected host-present behavior is now
  integrated. HSTCTLH.HLT samples HCS during reset, `CORE_RESET_HALT` issues
  no vector request while it remains one, and clearing HLT returns to
  `CORE_RESET` for the ordinary vector fetch. The eight prerequisite
  RAS-only cycles are implemented by the Task 0147 controller. Task 0148's
  integrated wrapper proves they complete before the core's pending vector
  request appears on the physical bus.

---

## A0009 — ALU flag-update convention before per-instruction read

- **Date**: 2026-05-12; **resolved 2026-07-28 (Task 0135)**.
- **Status**: **RESOLVED** against every implemented instruction family's
  individual `Status Bits` table.
- **Source**: 1988 TI TMS34010 User's Guide chapter 12. The complete review
  matrix, primary-page groups, Undefined-versus-Unaffected distinction, and
  test mapping are retained in `docs/status_audit.md`.
- **Resolution**:
  - Ordinary arithmetic uses the ALU's standard N/C/Z/V values, including the
    guide's borrow convention for subtract-family C.
  - Every partial writer uses a decoder `wb_flag_mask`; runtime-qualified
    MOD and graphics cases narrow or replace that mask in the core.
  - Undefined or indeterminate flags are deliberately preserved for
    deterministic FPGA behavior. This is not described as an
    original-silicon preservation guarantee.
  - Full-status operations (PUTST, POPST, RETI, TRAP, and interrupt entry)
    continue through the explicit full-ST write path rather than an ALU mask.
- **Corrections found by the final sweep**: MODS N/Z/writeback and DIVS N
  overflow behavior; odd-Rd MPYS/MPYU N/Z source width; W=3 V reporting for
  FILL/PIXBLT; and XY-to-XY PIXT window/V handling.
- **Regression evidence**: `tb_status_decode` exhaustively checks all 65,536
  opcode words against the static family matrix. `tb_div_flags`,
  `tb_mpy_flags`, `tb_fill_window`, `tb_pixblt_window`, and `tb_pixt_win`
  exercise the newly corrected runtime distinctions; the complete regression
  retains all prior per-family tests.

---

## A0010 — Status-register bit layout placeholder
- **Date**: 2026-05-12
- **Status**: historical placeholder; **RESOLVED** by the later A0010 entry
  from Task 0042.
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
- **Date**: 2026-05-12; **resolved 2026-07-28 (Task 0131)**.
- **Status**: **RESOLVED** against both individual MOVI pages.
- **Source**: 1988 TMS34010 User's Guide pages 12-159 (16-bit form) and
  12-160 (32-bit form).
- **Conclusion**: both forms set N from the moved value's sign, set Z when
  the moved value is zero, preserve C, and force V to zero. The IW form first
  sign-extends its 16-bit value; the IL form uses the complete 32-bit value.
- **Correction**: the former all-flags write mask fed PASS_B's zero carry
  into ST and therefore cleared C. Task 0131 changes both forms to an N/Z/V
  mask so the ALU's V=0 is written while C is retained.
- **Tests**: `tb_movi_flags` restores NCZV=1111 before positive, negative,
  and zero IW/IL operations, snapshots the complete ST word, and separately
  verifies IW sign extension and IL results. The original `tb_movi` and
  `tb_movi_il` result suites remain in the regression.

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
- **Date**: 2026-05-12; **resolved 2026-07-28 (Task 0129)**.
- **Status**: **RESOLVED** against the individual MOVK instruction page.
- **Source**: 1988 TMS34010 User's Guide page 12-161. The assembler
  listings `MOVK 1,A12 → 0x182C` and `MOVK 8,B1 → 0x1911` remain encoding
  cross-checks.
- **Conclusion**: `MOVK K, Rd` encodes as:
    bits[15:10] = 6'b000110  (= 0x06)
    bits[9:5]   = K          (1..31 directly; value 32 encoded as zero)
    bit[4]      = R          (file: 0 = A, 1 = B)
    bits[3:0]   = N          (register index 0..15)
  The selected constant is zero-extended to 32 bits and written to Rd; ST is
  unchanged. Opcode-field zero means 32, not literal zero, so MOVK cannot
  clear a register. The documented CLR alias is used for that purpose.
- **Implementation/test**: the shared K-constant mux substitutes the named
  `K_ZERO_VALUE` only for MOVK/ADDK/SUBK with an encoded zero field.
  `tb_movk` executes word `0x1801` and requires A1=`0x00000020`.

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
- **Date**: 2026-05-12; **resolved 2026-07-28 (Task 0129)**.
- **Status**: **RESOLVED** against the individual instruction pages.
- **Source**: 1988 TMS34010 User's Guide pages 12-40 (ADDK) and 12-251
  (SUBK), plus the Appendix A chart rows:
    `ADDK K,Rd  Add Constant (5 Bits)   0001 00KK KKKR DDDD   NCZV`
    `SUBK K,Rd  Subtract Constant (5)   0001 01KK KKKR DDDD   NCZV`
- **Conclusion**:
  - Encoding: bits[15:10] = `6'b000100` (ADDK) or `6'b000101` (SUBK);
    bits[9:5] encode values 1..31 directly and value 32 as zero; bit[4] = R;
    bits[3:0] = Rd idx. Literal arithmetic constant zero is not encodable.
  - ADDK operation: unsigned constant + Rd → Rd.
  - SUBK operation: Rd - unsigned constant → Rd. Flags: standard
    N/C/Z/V from the result (C is borrow for SUBK).
- **Implementation/test**: the core substitutes 32 for encoded zero only in
  the three constant instructions. `tb_addk_subk` checks the exact zero-field
  opcodes, both arithmetic results, and the final SUBK borrow/status result.

---

## A0019 — Shift count, encoding, overflow, and status treatment
- **Date**: 2026-05-12; **resolved 2026-07-28 (Task 0130)**.
- **Status**: **RESOLVED** against every individual shift instruction page.
- **Source**: 1988 TMS34010 User's Guide pages 12-234/12-235 (RL
  constant/register) and 12-239 through 12-246 (SLA/SLL/SRA/SRL
  constant/register).
- **Count range**: every architectural count is 0..31. Count zero is an
  identity operation and clears C; it never means 32 for a shift.
- **Encoding/operand convention**:
  - SLA/SLL/RL constant forms store the count directly in bits 9:5.
  - SRA/SRL constant forms store the five-bit two's complement of the
    architectural right-shift count in bits 9:5.
  - SLA/SLL/RL register forms use Rs[4:0] directly.
  - SRA/SRL register forms use the five-bit two's complement of Rs[4:0].
- **Status**: SLA updates N/C/Z/V and sets V if its new sign or any shifted-
  out bit differs from the original sign. SRA updates N/C/Z and preserves V.
  SLL, SRL, and RL update C/Z while preserving N/V. These rules are identical
  between the constant and register forms.
- **Correction**: the earlier implementation decoded right-shift constant
  fields directly, omitted SLA overflow, and used broad N/C/Z/V updates for
  several instructions. Task 0130 corrects the decoder, shifter, and
  per-instruction masks.
- **Tests**: `tb_shift_k` locks exact constant encodings and zero shifts;
  `tb_shift_rr` locks the register-count convention; `tb_shifter` checks the
  combinational overflow rule; `tb_shift_flags` snapshots full ST after all
  ten architectural forms.

---

## A0020 — MOVE family encodings (and a corrected reg-to-reg opcode)
- **Date**: 2026-05-12; **CORRECTED 2026-05-30 (Task 0058)**.
- **Status**: MOVE field machinery and all nine documented MOVB forms are
  implemented.
- **Source**: SPVU001A page 12-126 (MOVE Rs,Rd detail) + the Move-Instructions summary table, cross-checked against BOTH the 1986 first edition (`1986_SPVU001...`) and the 1988 User's Guide. Object-code example Figure 12-3: `MOVE A0,B1 = 0x4E01`.
- **CORRECTION**: the original A0020 misread the "A-14" chart. It took the row `1001 00FS SSSR DDDD` to be reg-to-reg MOVE; that row is actually **MOVE Rs,\*Rd+** (postincrement register-to-indirect, a memory *store*). Register-to-register MOVE is **`0100 11MS SSSR DDDD`** (base 0x4C00). The decoder and every stack testbench that set SP via "MOVE A0,A15" used the wrong 0x9000 opcode; they "passed" only because decoder + tests shared the same wrong encoding. Task 0058 relocates reg-to-reg MOVE to 0x4C00, adds the M-bit cross-file support, and fixes all affected testbenches.
- **Reg-to-reg MOVE (now implemented, Task 0058)**: `0100 11MS SSSR DDDD`. NOT a field move — full 32-bit copy, field size has no effect, so there is **no F bit**. M=bit[9]: 0 ⇒ same file, 1 ⇒ cross-file. R=bit[4]: file for both (M=0) or the *source* file (M=1; destination is the other file). This is the only MOVE that crosses register files. Status: N=data[31], Z=(data==0), V=0, C Unaffected. New struct field `rs_file` carries the (possibly different) source file; the core reads it for `rf_rs1_file` only on `INSTR_MOVE_RR`.
- **Historical state after Task 0062 — indirect MOVE forms, FS=32 only**: register↔indirect (plain/postinc/predec, Tasks 0059/0060) and indirect↔indirect (plain Task 0061; postinc/predec Task 0062) were initially implemented for field-size 32, word-aligned. **Rs==Rd corner (indirect-to-indirect inc/dec):** for postincrement the spec (12-138) defines it — data written to the incremented location, register steps once — and the implementation matches it. For *predecrement* with Rs==Rd the spec is silent; the implementation single-steps the register and the write address ends up doubly-decremented (a documented deviation, pathological case).
- **Historical backlog after Task 0064 (resolved by Tasks 0076–0079)**: arbitrary field sizes (1..31), unaligned pointers, fields straddling word boundaries, FE sign/zero extension, and the MOVE offset/absolute addressing modes were deferred at this point.
- **Task 0076 checkpoint**: the memory-model half of the field machinery landed — `sim_memory_model` reads/writes 1..32-bit fields at any bit address, straddling word boundaries, with read-modify-write preservation (`tb_mem_field`). Tasks 0077–0079 then connected this machinery to every MOVE addressing form.
- **Field-machinery progress (Task 0077)**: the register↔indirect MOVE forms (FIELD_STORE/FIELD_LOAD: plain, postinc, predec) are now **field-size aware**. The core derives `mv_fs`/`mv_fe` from the F-selected ST pair (FS0/FE0 or FS1/FE1; FS=0 ⇒ 32), drives `mem_size = mv_fs`, sign/zero-extends loads (`mv_load_data`) per FE, and steps pointers by ±FS. Unaligned/straddling fields are handled by the Task 0076 memory model. **Consequence**: because MOVE now honors the actual FS, the existing FS=32 round-trip tests (tb_move_indirect, tb_move_indirect_incdec) had to issue `SETF FS0=0` first — the reset ST has FS0=16, so without it those moves would transfer 16 bits. **Still FS=32-only**: the M2M (indirect↔indirect), offset, and absolute MOVE forms — their field-awareness is a later task.
- **Field-machinery progress (Task 0078)**: the OFFSET (0xB000/0xB400) and ABSOLUTE (0x0580/0x05A0) MOVE forms are now field-size aware too — same `mv_fs`/`mv_load_data` machinery (no pointer step). tb_move_offset / tb_move_abs now SETF FS0=0 up front; new tb_move_offabs_field covers FS=8/16 and an FS=12 straddling absolute field.
- **Field machinery COMPLETE for MOVE (Task 0079)**: the M2M (indirect↔indirect) forms (0x8800/0x9800/0xA800) are now field-size aware — both steps of the 2-step CORE_MEMORY sequence use `mem_size = mv_fs` (read FS bits into move_data_q, write its low FS bits), and both pointers step by ±FS. No FE extension (mem→mem). tb_move_m2m / tb_move_m2m_incdec now SETF FS0=0; new tb_move_m2m_field covers FS=8 plain/postinc and an FS=12 copy with both src and dst fields straddling word boundaries. **All MOVE addressing forms now honor arbitrary FS 1..31 + FE, unaligned, and word-straddling fields.** The remaining field-related item is **MOVB** (byte move, FS fixed at 8 — a thin decode layer that forces FS=8 over this machinery, independent of ST).
- **MOVB implementation (Tasks 0080 and 0120)**: `decoded.force_byte`
  forces FS=8 (`mv_fs`) and, for loads, FE=sign-extend (`mv_fe=1`)
  regardless of ST. Task 0080 mapped seven forms onto the existing MOVE
  field/offset/absolute datapaths: Rs,*Rd (0x8C00), *Rs,Rd (0x8E00),
  *Rs,*Rd (0x9C00), Rs,*Rd(off) (0xAC00), *Rs(off),Rd (0xAE00),
  Rs,@DAddr (0x05E0), and @SAddr,Rd (0x07E0). Task 0120 completed the
  remaining memory-to-memory forms: *Rs(SOff),*Rd(DOff) (0xBC00) fetches two
  independent signed 16-bit offsets, while @SAddr,@DAddr (0x0340) fetches
  two low-word-first 32-bit bit addresses. Both reuse the two-step M2M engine,
  transfer exactly eight bits, preserve the base registers, and leave all
  flags unaffected. MOVB has no auto increment/decrement forms.

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
- **Task 0101 update**: the five remaining arithmetic codes were implemented:
  C/B=`1000`, V=`1100`, NV=`1101`, N=`1110`, and NN=`1111`. JRcc and JAcc now
  recognize all 16 codes, with `tb_jrcc_arith` covering take/skip behavior.
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
- **Date**: 2026-05-12; **resolved 2026-07-28 (Task 0132)**.
- **Status**: **RESOLVED** against the primary guide.
- **Sources**:
  - 1988 TI TMS34010 User's Guide page 12-233, "Store Revision Number".
  - 1988 TI TMS34010 User's Guide page 12-79, "Exchange Program Counter".
- **Resolution**:
  - REV stores the TMS34010 revision format in Rd; the worked example gives
    the exact observable result `REV A1: 0xFFFFFFFF -> 0x00000008`.
    `REV_VALUE = 32'h0000_0008` is therefore retained.
  - EXGPC exchanges Rd with the *next* PC. Its instruction page explicitly
    states that the processor sets the PC's four LSBs to zero. The existing
    `pc_load_value = {rf_rs2_data[31:4], 4'h0}` is exact; Rd receives the
    already word-aligned next-PC value without additional modification.
  - Both pages specify N, C, Z, and V as Unaffected.
- **Regression evidence**: `tb_pc_ops` executes REV after NCZV=1111, snapshots
  the unchanged ST, loads EXGPC's Rd with unaligned target `0x0000064F`, and
  proves execution lands at `0x00000640`. It also checks the dynamically
  calculated next PC returned in Rd and another unchanged full-ST snapshot.

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

## A0027 — SUBXY greater-than comparison signedness
- **Date**: 2026-05-31; **resolved 2026-07-28 (Task 0134)**.
- **Status**: **RESOLVED; the original unsigned assumption was incorrect.**
- **Sources**:
  - 1988 TI TMS34010 User's Guide §4.3 page 4-11 defines both halves of an
    XY address as 16-bit signed integers with range -32768 through +32767.
  - Page 12-252 defines SUBXY C/V as source-Y/source-X greater than the
    corresponding destination field.
- **Resolution**: Because SUBXY operates on XY fields, its `>` relations use
  signed 16-bit coordinate ordering. The core now computes
  `$signed(RsY) > $signed(RdY)` for C and the analogous X comparison for V.
  N/Z remain field equality, and the subtraction result remains two
  independent wrapping 16-bit differences. CMPXY retains its separately
  specified result-sign rules.
- **Regression evidence**: `tb_addxy_subxy` adds Rd=(X=+1,Y=-1) and
  Rs=(X=-1,Y=+1). Signed comparison requires C=1/V=0, while unsigned
  comparison would produce C=0/V=1; the test checks NCZV=`0100` and result
  `0xFFFE0002`.

## A0028 — I/O register integration into the core memory path
- **Date**: 2026-05-31; refined 2026-07-28 (Tasks 0149–0150).
- **Status**: resolved for processor and host-indirect physical I/O paths.
- **Source**: SPVU001A §6 "I/O Registers", Figure 6-1; "An access of any
  address in the range C0000000h-C00001FFh is decoded as an access of an
  on-chip register" and "the accompanying memory cycle ... is altered so
  that RAS is output but CAS is inhibited"; 1988 User's Guide §6.1,
  §10.3.3.4, and §11.4.8.
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
- **Field-size boundary**: I/O registers are 16-bit and the core accesses
  them with 16-bit fields (the ISA uses 16-bit MOVE to I/O space);
  sub-16-bit field writes to I/O are not read-modify-write (they write the
  low 16 bits) and 32-bit accesses would span two registers — neither is
  exercised by the implemented instruction set.
- **Task 0137 checkpoint**: INTPEND is no longer provisional plain storage.
  Pages 6-36 through 6-42 now directly determine INTENB masking,
  HSTCTLL.INTIN/HIP, synchronized read-only X1P/X2P, and hardware-set,
  write-zero-to-clear DIP/WVP behavior.
- **Task 0142 checkpoint**: the provisional host INTIN set sideband is gone.
  A synchronous direct HSTCTL transaction now implements host-side MSGIN,
  INTIN, and INTOUT behavior plus HINT and shared high-byte fields. Physical
  pin timing and CDC remain isolated from this on-chip I/O-cycle choice.
- **Task 0143 checkpoint**: `tms34010_host_if` now implements the
  HSTADR/HSTDATA register and indirect-cycle semantics behind a synchronous
  request/ack boundary. Its I/O-block and memory-fabric connections remain
  the next integration task.
- **Task 0144 checkpoint**: the engine is now instantiated in the I/O block.
  One generalized core request/ack port selects all four host registers,
  processor accesses share its HSTADR/HSTDATA state, and its held aligned-word
  client is exposed. Task 0145 lands the standalone arbiter contract; wiring
  this client through it remains memory-fabric integration work.
- **Task 0149 processor resolution**: §11.4.8 specifies a distinct,
  always-two-clock cycle for either processor or host-indirect I/O access.
  The core now exports full-address I/O decode, original direction, and the
  internal read word. `tms34010_memory_fabric` registers/classifies the
  architectural request, bypasses field sequencing, and selects
  `LOCAL_CYCLE_IO_READ/WRITE`; the command bridge carries internal read data
  and the phase engine ignores LRDY. The I/O owner sees only
  `mem_req && mem_ack`, so a write/load commits exactly once after physical
  completion. `tb_pin_system` locks the zero address/status, inactive IAQ,
  RAS/LAL-only controls, write-data drive, read-phase LAD release, and PMASK
  round trip.
- **Task 0150 host resolution**: the held host address is independently
  decoded and reads the same register owner. The arbiter snapshots live
  internal read data when the host wins and selects
  `LOCAL_CYCLE_IO_READ/WRITE`; completion returns through the existing MCP
  path to HSTDATA. Host-indirect writes commit only with that returned
  acknowledge. HSTCTLL applies host-side field ownership, while a second
  HSTADR/HSTDATA selector preserves the documented shared state without
  coupling processor and host read addresses. `tb_host_integration`,
  `tb_system_fabric`, and `tb_pin_system` lock classification, ownership,
  returned data, pin phases, and exact-once writes.

## A0045 — Dedicated VCLK ownership and coherent CDC contract
- **Date**: 2026-07-28 (Task 0155).
- **Status**: specification-derived clock ownership with isolated FPGA CDC,
  stopped-clock, reset, and active-edge representation choices. Quartus
  recognition/constraints remain part of gate 6.
- **Sources**: 1988 TI TMS34010 User's Guide §2.4, page 2-9; §§9.2–9.6,
  pages 9-3 through 9-12; §9.10.1, pages 9-18 through 9-25; and the project
  CDC rules in `docs/hdl-coding-guidelines/23-cdc-single-bit.md` and
  `24-cdc-multi-bit.md`.
- **Clock ownership**: `vclk_i` exclusively clocks HCOUNT/VCOUNT, timing
  compares and outputs, DPYADR, and automatic screen scheduling. Core I/O
  storage and the memory fabric remain on `clk`. The clocks may have any
  phase or frequency relationship.
- **Configuration crossing**: HESYNC/HEBLNK/HSBLNK/HTOTAL,
  VESYNC/VEBLNK/VSBLNK/VTOTAL, DPYINT, DPYSTRT, DPYCTL, and DPYTAP cross as
  one packed MCP snapshot. The source payload register remains stable through
  the request/acknowledge round trip. Writes made while one snapshot is in
  flight coalesce into a later atomic latest-value snapshot.
- **Live-write crossing**: completion-qualified HCOUNT, VCOUNT, and DPYADR
  writes use a second packed mailbox. A pending bit and latest data are kept
  independently for each owner, so writes to different owners cannot erase
  one another; repeated writes to one owner while busy deterministically
  coalesce to the latest value. VCLK applies all flags in one destination
  pulse, with the pre-existing load-over-automatic-update priority.
- **Processor/host read view**: a continuously re-armed MCP returns one
  coherent `{HCOUNT,VCOUNT,DPYADR}` snapshot. The core view is several
  asynchronous handshake cycles stale but can never be bit-torn or combine
  different source epochs. This is the FPGA replacement for independently
  sampling changing binary registers, which is forbidden.
- **Stopped-VCLK choice**: the original guide recommends holding VCLK high
  while HCOUNT/VCOUNT are accessed. This synchronous FPGA boundary instead
  requires VCLK edges to complete commands and refresh snapshots. If VCLK is
  stopped, reads retain the last coherent snapshot and writes remain queued
  until VCLK resumes. A0003 already excludes original electrical pin
  compatibility; the final FPGA top must keep its internal video clock
  running or explicitly document this software-visible difference.
- **Event/transaction crossings**: the one-bit DIP condition is held until a
  toggle mailbox accepts it; multiple occurrences while INTPEND.DIP is
  already pending are intentionally equivalent. A screen request captures
  SRFADR/DPYTAP/ORG, crosses once, remains asserted through arbitrary
  core-memory waits, and returns exactly one VCLK completion only after the
  physical memory-to-register cycle acknowledges.
- **Active-edge/reset representation**: every synthesizable block remains
  positive-edge clocked. The active edge of the internal FPGA `vclk_i`
  represents the original falling-VCLK state-update edge; final PLL/pin phase
  mapping belongs to the FPGA top. The project-wide synchronous `rst` must be
  sampled asserted by both clocks so all mailbox toggle phases reset to zero.
- **Regression evidence**: `tb_video_cdc` uses a non-integer clock ratio and
  covers atomic/coalesced configuration, coalesced distinct live commands,
  coherent status, one-cycle DIP delivery, stalled bundled screen payload,
  and returned completion. `tb_io_video`, `tb_io_display`, and
  `tb_pin_system` exercise the integrated hierarchy.

## A0044 — Reserved I/O fields and register locations
- **Date**: 2026-07-28 (Task 0154).
- **Status**: specification-derived write masking plus a deterministic
  read-zero choice for otherwise unspecified reserved locations.
- **Sources**: 1988 TI TMS34010 User's Guide §6.1 Figure 6-1, pages 6-2/6-3;
  CONTROL pages 6-10 through 6-14; DPYCTL pages 6-18 through 6-22; DPYTAP
  pages 6-24/6-25; and PMASK pages 6-43/6-44.
- **Stored reserved fields**: CONTROL bits 1:0, DPYCTL bit 1, and DPYTAP bits
  15:14 are identified as reserved/not used and remain zero after either a
  processor or completion-qualified host-indirect write. Their defined fields
  retain full read/write storage.
- **Reserved locations**: Figure 6-1 reserves indices 17h through 1Ah. The
  PMASK description specifically says a compatibility write to `C0000170h`
  has no effect. This implementation treats all four uniformly as
  non-storage and returns deterministic zero to both read views. The read
  value for otherwise reserved 18h–1Ah is not architecturally relied upon.
- **REFCNT exception**: A0033 already isolates the guide's unspecified
  software-write behavior for REFCNT bits 1:0 and regression-locks their
  retention. Task 0154 deliberately does not rewrite that prior choice.
- **Consumer boundary**: defined DPYCTL SRT/HSD/DXV/NIL functions remain
  stored but belong to the video/display completion gate. CONTROL.CD and
  HSTCTL.CF remain stored in the cacheless configuration. These are missing
  consumers or cycle-accuracy features, not missing register masks.
- **Regression evidence**: `tb_io_regs` writes all ones to each masked
  register and writes all four reserved locations. `tb_host_integration`
  proves the same CONTROL mask and reserved-location behavior through the
  acknowledged host-indirect I/O path.

## A0043 — Asynchronous physical host bus CDC and re-arm contract
- **Date**: 2026-07-28 (Task 0153).
- **Status**: specification-derived host protocol with an isolated
  functional-first CDC/strobe-width realization; final FPGA timing and
  original-cycle latency proof remain open.
- **Sources**: 1988 TI TMS34010 User's Guide §2.2, Table 2-2, pages 2-5
  through 2-6; §10.3.2, pages 10-4 through 10-10; and A0006.
- **Access qualification**: a physical access exists only while HCS is low,
  exactly one of HREAD/HWRITE is low, and at least one of HLDS/HUDS is low.
  The last active control starts it and the first inactive control ends it.
  Both directions low is invalid and launches no internal request.
- **Bundled-data crossing**: the combined access level passes through an
  attributed 2FF synchronizer. HRDY falls directly from the raw active pins
  while that crossing completes, so HFS, direction, byte selection, and HD
  are a stable MCP payload. The core captures them only after the synchronized
  level arrives, holds one request through acknowledge, and registers read
  data before allowing completion. Individual payload bits are not
  synchronized independently.
- **External hold/re-arm requirement**: the host must retain the active access
  and payload until HRDY is high. After ending it, the combined access must
  remain inactive long enough for both synchronizer stages and the one-access
  latch to clear before another access begins. This minimum inactive width is
  an FPGA interface requirement not stated as such for original silicon; the
  final datasheet/board timing audit must prove it or replace the bridge with
  a faster asynchronous-front-end handshake.
- **HRDY policy**: every legal access may receive an extra wait for CDC. A
  registered response wins over a newly started indirect busy condition so
  the current access can end; that busy condition then waits the following
  access. HCS with stable HSTCTL selection lowers HRDY before direction/byte
  strobes and holds a deterministic two-core-count interval after
  synchronized recognition. This functionally preserves the mandatory
  HSTCTL delay but does not yet claim the guide's exact one-to-two-local-clock
  latency without the final PLL/TimeQuest relationship.
- **HD direction**: read data remains registered until access re-arm and only
  captured selected byte lanes receive output-enable intent. Writes, waits,
  illegal direction combinations, and inactive HCS never enable HD outputs.
  The FPGA top must map `hd_i`, `hd_o`, and `hd_oe_o` to bidirectional I/O
  cells.
- **Regression evidence**: `tb_host_bus` offsets host edges from the core
  clock and covers access starts, stable capture, byte lanes, illegal
  direction, HSTCTL HCS-only delay, busy carryover/current-ready priority, and
  re-arm. `tb_pin_system` routes the full host-indirect PMASK sequence through
  physical pins while retaining local-bus, HOLD, and EMU checks.

## A0042 — Physical RUN/EMU event bridge and shared output
- **Date**: 2026-07-28 (Task 0152).
- **Status**: specification-derived physical RUN/EMU synchronization and
  HLDA/EMUA phasing; Quartus synchronizer recognition and output timing remain
  part of the FPGA sign-off gate.
- **Sources**: 1988 TI TMS34010 User's Guide §2.5, Table 2-5, page 2-10;
  §11.4.11, page 11-20; and the EMU instruction on page 12-77.
- **Physical input**: RUN/EMU passes through a dedicated 2FF synchronizer into
  the core clock domain. Both stages reset to one, the inactive RUN level, so
  reset release cannot spuriously request emulator mode. The FPGA top still
  owns the documented electrical pull-up choice.
- **Execute event**: a registered source request stretches the core's
  one-clock EMU execute indication. The 8× domain waits for Q4B-to-Q1A,
  drives EMUA low for exactly Q1/Q2, and registers its acknowledge only at
  Q2B-to-Q3A after that complete pulse. The source then drops the request,
  completing a four-phase one-outstanding handshake.
- **One-outstanding bound**: in the current cacheless system, another EMU
  cannot execute until its opcode fetch crosses and completes on the same
  physical bus. That fetch takes longer than the destination pulse and
  handshake return, so two execute events cannot coalesce. A future
  instruction cache must either retain that bound or add explicit event
  backpressure/queueing.
- **Halt level**: the core halt state is registered before its own 2FF
  crossing. The destination latches it only at Q4B-to-Q1A, so assertion or
  release cannot truncate a Q1/Q2 window. While halted, every Q1/Q2 half is
  active; Q3/Q4 remain available to HLDA.
- **Shared mux**: LCLK1 high selects active-low EMUA; LCLK1 low selects the
  Task 0151 active-low HLDA component. Simultaneous halt and HOLD may keep the
  physical pin continuously low, but each half remains attributable to its
  specified function.
- **Regression evidence**: `tb_emu_bridge` uses asynchronous clocks and locks
  two independent events, handshake re-arm, halt entry/release, and HOLD
  overlap. `tb_pin_system` executes a real RUN-mode EMU, enters physical
  emulator halt, overlaps HOLD, and resumes while checking every phase.

## A0041 — Physical HOLD/HOLDA CDC and output-enable boundary
- **Date**: 2026-07-28 (Task 0151).
- **Status**: specification-derived physical release sequencing with an
  explicit FPGA I/O-enable boundary; Task 0152 completes the shared
  HLDA/EMUA mux, while TimeQuest proof remains open.
- **Sources**: 1988 TI TMS34010 User's Guide §2.5, Table 2-5, pages 2-10
  through 2-11; §11.3, page 11-4; and §11.4.11, Figures 11-15/11-16,
  pages 11-18 through 11-21.
- **Sampling and CDC**: `tms34010_local_bus` samples active-low HOLD at each
  Q1B-to-Q2A transition, the end-Q1/LCLK2 rising boundary. Only that held
  level crosses into the core through `tms34010_sync_bit`. The existing
  arbiter returns its active-high acknowledge only after the current owner
  completes; a second synchronizer carries that level back to the 8× domain.
  No changing command payload participates in this handshake.
- **Release sequence**: once the synchronized grant is visible at a sampled
  active HOLD boundary, HOLDA first becomes active-low during Q3/Q4. At the
  following Q2, LAD and RAS/LAL/CAS/W/TR/QE output enables become inactive;
  DEN/DDOUT follow at Q3. All remain inactive while HOLD is granted, and
  queued bus commands cannot start.
- **Resume sequence**: release is likewise sampled at end Q1. HOLDA becomes
  inactive in the next Q3/Q4 indication window; the majority output enables
  return at Q2 and DEN/DDOUT at Q3. Synchronizer latency is deliberately
  allowed to add complete local clocks without changing these specified
  within-clock relationships.
- **Tri-state boundary**: synthesizable internal RTL exports explicit
  per-group output enables instead of assigning `Z` inside the controller.
  The FPGA top must map them to device I/O buffers and constrain those enable
  paths. Task 0152 combines Q3/Q4 HOLDA with Q1/Q2 EMUA on the original
  shared pin inside the integrated pin system.
- **Regression evidence**: `tb_local_bus_hold` locks end-Q1 sampling, early
  acknowledge, exact Q2/Q3 release/resume, held-command suppression, and
  active-cycle completion. `tb_pin_system` proves the synchronized path
  quiesces and resumes a running processor without losing physical cycles.

## A0040 — Core-to-8× MCP bridge and common reset
- **Date**: 2026-07-28 (Task 0148).
- **Status**: verified functional CDC architecture; Quartus constraint and
  metastability-report sign-off remain part of the FPGA project gate.
- **Sources**: `docs/hdl-coding-guidelines/23-cdc-single-bit.md` and
  `24-cdc-multi-bit.md`; 1988 TI TMS34010 User's Guide §11.5, pages 11-23
  through 11-24 (IAQ); and §9.10.1.2, pages 9-20 through 9-23 (screen ORG).
- **Command crossing**: the core domain registers all of
  `local_cycle_cmd_t`, toggles one request bit, and does not alter the command
  until the returned acknowledge completes. Only that toggle passes through
  a dedicated attributed 2FF synchronizer. The 8× domain captures the
  unsynchronized but multi-cycle-stable payload into its own registers and
  holds the controller request until completion.
- **Response crossing**: the 8× domain registers the returned read word before
  updating its acknowledge toggle. That word remains stable for the toggle's
  two-stage return latency; the core domain then captures it and emits one
  completion pulse. One transaction may be outstanding, matching the existing
  held arbiter contract; an explicit source re-arm after request deassertion
  prevents a duplicate acceptance around the completion edge.
- **Reset contract**: both domains receive the same active-high project reset
  and reset both toggle phases to zero. They may sample synchronous
  deassertion on different edges; a request remains held long enough for the
  later domain to observe it. Independent run-time reset of only one bridge
  side is unsupported because it could destroy toggle phase or an outstanding
  transaction.
- **IAQ and ORG**: the current cacheless core asserts IAQ only for
  `CORE_FETCH`; immediate extension words and data/vector transactions are
  low. Screen ORG is captured with SRFADR/DPYTAP when the held refresh request
  begins, so later DPYCTL changes do not alter an in-flight physical command.
- **Timing boundary**: the source/destination clocks are treated as
  asynchronous by the RTL. The future Quartus SDC must identify both clocks,
  constrain the toggle synchronizers, cut/waive the protocol-protected MCP
  payload paths, and preserve/recognize both 2FF chains. Simulation does not
  constitute metastability or TimeQuest evidence.
- **Regression evidence**: `tb_local_bus_bridge` uses a non-integer clock
  ratio, variable destination waits, all payload fields, returned data, and
  consecutive toggle phases. `tb_pin_system` proves that eight reset RAS
  cycles precede the physical two-word vector and opcode traffic.

## A0039 — 8× original-pin phase engine boundary
- **Date**: 2026-07-28 (Task 0147).
- **Status**: specification-derived pin sequencing with explicit FPGA clock,
  reset, undefined-value, and CDC boundaries.
- **Source**: 1988 TI TMS34010 User's Guide §11.4, Figures 11-3 through
  11-17, pages 11-7 through 11-22; §11.5, Figures 11-18/11-19, pages 11-23
  through 11-27; and §9.10.1.2, Figures 9-13/9-14, pages 9-20 through 9-23.
- **Specification-derived behavior**: two local clocks form each ordinary
  word, screen-transfer, refresh, or I/O cycle. Row, column, and status bits
  use the documented multiplexing; screen addresses combine SRFADR/DPYTAP
  and ORG; LRDY is sampled at the end of Q1 and repeats the access period;
  I/O cycles ignore LRDY; reads sample LAD in mid-Q4; and reset is followed
  by eight extendable zero-row RAS-only cycles.
- **8× representation**: two timing ticks represent each Q phase. This
  resolves the diagrams' mid-quarter strobe transitions and middle-Q4 read
  sample without driving internal flops from LCLK1 or LCLK2. The future FPGA
  top must source `clk8x_i` from a PLL/clock network and constrain the output
  pins; the current repository has no synthesis or timing evidence.
- **Synchronous reset boundary**: A0003 resets the subphase counter to Q1A,
  holding the two LCLK outputs at their Q1 levels while reset remains active.
  Original silicon keeps its local clocks running and asynchronously samples
  RESET. The eight required memory-initialization cycles begin immediately
  after synchronous release, but exact active-reset clock/pin compatibility
  is deliberately not claimed.
- **Undefined LAD choice**: phases the guide labels Undefined are driven as
  deterministic zero while the controller owns LAD; read data phases are
  explicitly high impedance through `lad_oe_o`. This avoids synthesizable X
  values and does not assign architectural meaning to the zero.
- **CDC/integration checkpoint**: command and response signals remain
  synchronous to `clk8x_i`. Task 0148 connects them to the core-clock system
  only through the A0040 MCP bridge and propagates IAQ plus screen ORG.
  Tasks 0149–0150 now generate processor and host-indirect I/O cycle
  kinds/data upstream. Task 0151 adds sampled physical HOLD, phased HOLDA,
  and explicit output-enable release; Task 0152 completes the shared
  HLDA/EMUA output; Task 0153 replaces the integrated wrapper's synchronous
  host boundary with the original physical controls and split HD direction.
- **Regression evidence**: `tb_local_bus` verifies both LCLK waveforms, all
  seven cycle kinds, exact word/screen/refresh/I/O address/status values,
  write/read/control ordering, mid-Q4 read data, ordinary and
  screen-transfer waits, I/O LRDY bypass, and exactly eight reset cycles.

## A0038 — Local-cycle arbitration and refresh-event retention
- **Date**: 2026-07-28 (Task 0145).
- **Status**: specification-derived priority/atomicity with an isolated
  one-entry FPGA event-retention bound.
- **Source**: 1988 TI TMS34010 User's Guide §11.3, page 11-4.
- **Specification-derived behavior**: local-memory ownership descends from
  external HOLD to screen refresh, DRAM refresh, host indirect, and finally
  CPU/graphics. A physical cycle already in progress always completes before
  a new owner begins. CPU partial-word read/modify/write is indivisible among
  ordinary clients, but higher-priority work may run between different words
  of a multiword field. HOLD is the sole exception: if accepted between the
  partial read and its write, the complete RMW pair restarts after release.
- **FPGA transaction boundary**: `tms34010_bus_arbiter` registers the active
  owner and holds one abstract cycle kind plus client payload until controller
  acknowledge. Selection and the return to idle may add internal bubble
  clocks; no original LCLK/LAD/RAS/CAS phase or cycle-count claim is made.
- **Refresh retention bound**: REFCNT produces a one-clock event every 32 or
  64 local clocks. The arbiter captures one pending row/mode. A new event can
  replace a just-retired event on the same edge, but an additional event while
  one is already pending is not queued. Task 0147 proves the standalone
  controller consumes two local clocks plus any LRDY waits, but the final CDC
  and external HOLD path must still guarantee service before the next
  interval. An overlong HOLD already violates the guide's
  refresh-availability constraint.
- **Regression evidence**: `tb_bus_arbiter` locks the full priority order,
  active-owner/payload retention, response routing, and pulsed-refresh capture.
  `tb_bus_arbiter_rmw` integrates the real field sequencer and locks the
  ordinary RMW reservation, legal inter-word preemption, and HOLD restart.
- **Task 0146 integration**: `tms34010_memory_fabric` composes the sequencer
  and arbiter, while `tms34010_system` connects all four core clients. No new
  scheduling policy or buffering is introduced. `tb_system_fabric` boots real
  instructions and directly observes CPU, host, screen, DRAM-refresh, and
  HOLD behavior at the shared controller boundary.

## A0037 — Synchronous host-indirect boundary and invalid-access collisions
- **Date**: 2026-07-28 (Task 0143).
- **Status**: specification-derived host-register behavior with isolated
  deterministic choices for pre-pin flow control and invalid collisions.
- **Source**: 1988 TMS34010 User's Guide §10.2 and §10.3.2 through §10.3.5,
  pages 10-2 through 10-21.
- **Specification-derived behavior**: HSTADRL/HSTADRH form one 32-bit pointer
  whose low nibble is forced to zero. Completing the address in the
  LBL-selected byte order prefetches HSTDATA without increment. A last-byte
  HSTDATA read returns the buffered value, optionally increments HSTADR
  before launching the next read, and later replaces HSTDATA on acknowledge.
  A last-byte write launches the merged HSTDATA value at the current address
  and optionally increments only after write completion. Pointer addition
  wraps at 32 bits. Processor-side HSTADR/HSTDATA accesses never cause these
  local-memory side effects.
- **Synchronous boundary**: one host request and its register/byte/data
  payload remain stable until a registered acknowledge. A side-effecting
  transaction can acknowledge the register transfer while its captured
  local-word request continues; later host requests are backpressured until
  that request is acknowledged. This preserves the functional role of HRDY
  at the synchronous engine boundary. Task 0153 now supplies the physical CDC
  and §10.3 strobe behavior under A0043; this inner module still makes no pin
  timing claim.
- **Collision choices**: §10.3.3.4 requires software to avoid simultaneous
  processor/host HSTADR/HSTDATA accesses and says invalid data may result.
  The isolated FPGA boundary chooses an accepted host access over a
  same-edge processor access. An explicit processor access wins over an
  automatic returning-read or INCW update; an accepted host access would win
  over both. Captured local payload never changes after any later collision.
- **Integration boundary**: Task 0144 instantiates the engine in the I/O/core
  hierarchy and exposes its local-word client; Tasks 0146/0150 arbitrate and
  service it; Task 0153 provides HRDY, pin strobes, and CDC around the
  retained synchronous contract.
- **Regression evidence**: `tb_host_if` covers reset, processor no-side-effect
  access, HSTCTL forwarding, both LBL orders, prefetch, INCR/INCW timing,
  partial-byte merging, request stability, backpressure, wraparound, and the
  deterministic invalid-collision rule. `tb_host_integration` covers the
  shared core/I/O state and complete exported local-word path.

## A0036 — Synchronous direct-host boundary and collision precedence
- **Date**: 2026-07-28 (Task 0142).
- **Status**: specification-derived register/halt behavior with isolated
  deterministic choices for the FPGA transaction boundary.
- **Source**: 1988 TMS34010 User's Guide pages 6-31 through 6-37, §8.8 pages
  8-10 through 8-13, and §§10.3.3.5/10.3.4 pages 10-18 through 10-20.
- **Specification-derived behavior**: host writes own MSGIN, set INTIN with
  one, and clear INTOUT with zero; processor writes own MSGOUT, clear INTIN
  with zero, and set INTOUT with one. INTOUT drives active-low HINT. Both
  sides read/write the seven defined HSTCTLH fields. HCS high resets HLT to
  one and defers the level-0 vector fetch. Run-time HLT takes effect at an
  instruction boundary, blocks every interrupt while already halted, and
  leaves refresh/video functions running. A new simultaneous NMI+HLT
  completes NMI entry and halts before the first handler instruction.
- **FPGA boundary**: the inner `host_req_i` transaction carries a register
  selector, direction, byte enables, and write data in the core clock domain;
  registered acknowledge, read data, busy, and HINT complete the synchronous
  abstraction. Task 0153 wraps it with physical strobes, HRDY, and coherent
  asynchronous capture under A0043. This inner boundary does not itself claim
  original-pin timing.
- **Collision choices**: the guide declares conflicting simultaneous
  host/processor HSTCTLH writes unpredictable; this boundary chooses host
  priority. HSTCTLL remains hazard-free, with producer events winning
  coincident consumer clears (host INTIN set over processor clear; processor
  INTOUT set over host clear). A host or processor high-byte write wins a
  coincident automatic NMI clear.
- **Deferred field consumers**: Task 0144 connects INCW, INCR, and LBL to the
  integrated host-indirect engine and exported local-word cycles. CF still
  has no instruction-cache consumer.
- **Regression evidence**: `tb_host_control` covers the direct register
  contract and collisions; `tb_host_halt` covers reset/run-time halt,
  quiescence, refresh/video continuation, pending NMI, and NMI+HLT ordering.

## A0035 — Deterministic screen-refresh handshake and DPYADR collisions
- **Date**: 2026-07-28 (Task 0141).
- **Status**: specification-derived ordinary scheduling with isolated
  deterministic choices for undefined/colliding control cases.
- **Source**: 1988 TMS34010 User's Guide pages 6-17 through 6-24 and
  §9.10.1 pages 9-18 through 9-25.
- **Specification-derived behavior**: SRFADR reloads from DPYSTRT at the
  beginning of vertical blanking; LNCNT reloads before the first active line
  and after each completed screen-refresh cycle. SRE requests the first
  active-line transfer and subsequent transfers every LCSTRT+1 lines. A
  completed cycle advances/decrements SRFADR by DUDATE according to ORG.
  Screen requests outrank lower-priority memory clients and remain pending
  when an external hold prevents immediate service.
- **Handshake boundary**: `screen_refresh_req_o` is a held level, not a pulse.
  Its 14-bit SRFADR and 16-bit DPYTAP payloads are captured when scheduled and
  remain stable until `screen_refresh_ack_i` reports completion of the future
  physical VRAM memory-to-register cycle. DPYADR updates on acknowledge, not
  request. This preserves the specified pending behavior without prematurely
  inventing local-bus phases.
- **Processor collision choice**: a same-edge full DPYADR processor load wins
  over frame reload, LNCNT decrement, or acknowledge-time update; a valid
  acknowledge still retires its held request. The guide gives split-screen
  ordering guarantees but does not define an exact simultaneous internal
  collision.
- **SRE/pending choice**: clearing SRE prevents newly scheduled requests at
  the next HBLANK but does not cancel a request already presented to the
  memory controller. Re-enabling SRE forces the next eligible HBLANK. This
  keeps the client protocol monotonic through stalls.
- **Undefined DUDATE choice**: the guide requires zero or one set bit and
  says multiple set bits produce an undefined increment. The RTL
  deterministically treats the complete eight-bit field as an unsigned
  add/subtract value. Conforming one-hot/zero programs exactly match the
  specified 0/1/2/4/.../128 steps.
- **Control during a stall**: request address/tap payloads are captured, while
  the completion update uses the live DUDATE/ORG value. Software should not
  rewrite display control around an outstanding transfer; the physical
  controller task may tighten this boundary if primary bus timing requires.
- **Regression evidence**: `tb_display_addr` covers the direct state machine
  and all deterministic choices above. `tb_io_display` locks register
  integration, generated timing events, held payload, and completion updates.

## A0034 — Internal/noninterlaced video timing
- **Date**: 2026-07-28 (Task 0139); **resolved/refined 2026-07-28
  (Task 0155)**.
- **Status**: **RESOLVED** for the dedicated clock/CDC boundary. External
  synchronization and interlaced timing remain separate missing modes, not
  an implicit same-clock assumption.
- **Source**: 1988 TMS34010 User's Guide pages 6-18 through 6-25, 6-31,
  6-47, and §9.7 define the register behavior and video events. Project
  conventions A0004/A0006 allowed the Task 0139 functional-first checkpoint;
  A0045 now defines the independent VCLK behavior.
- **Specification-derived behavior**: HCOUNT increments through HTOTAL and
  wraps while advancing VCOUNT through VTOTAL; sync and blank intervals use
  the H*/V* timing compares. Task 0140 verified the specified one-VCLK output
  delay: sync and leading blank remain active through their end-value
  equality, while trailing blank begins on the count after HSBLNK/VSBLNK.
  DPYCTL.ENV=0 forces BLANK active and inhibits setting DIP. When enabled,
  DIP is requested on the DPYINT-selected line at the HSBLNK equality event,
  not at HCOUNT zero.
- **Resolved clock boundary**: Task 0155 moves timing and display-address
  state to explicit `vclk_i`. A0045 defines the packed MCP configuration,
  command/status, DIP, and completed-screen-transaction crossings. The active
  FPGA edge represents the original falling-VCLK update edge; final physical
  phase mapping and SDC proof remain FPGA-realization work.
- **Mode scope**: the integrated timing path is internal and noninterlaced.
  DXV/external-sync correction and NIL=0 interlaced half-line behavior remain
  unimplemented rather than being represented by misleading pseudo-support.
- **Deterministic counter-write choice**: a delivered VCLK command retains the
  original load priority: HCOUNT load suppresses that edge's wrap/VCOUNT step,
  and an independent VCOUNT load wins for VCOUNT. A0045 records coalescing and
  the stopped-VCLK access difference; this collision precedence remains an
  FPGA-model choice rather than an original-silicon guarantee.
- **Regression evidence**: `tb_video` covers counter loads/wraps, timing
  windows, ENV, and the corrected interrupt point. `tb_video_cdc` covers the
  dedicated domain and every crossing. `tb_io_video` covers the live register
  snapshots, combined blank, timing outputs, and integrated
  hardware-set/write-zero-clear DIP behavior.

## A0033 — REFCNT reserved mode and deterministic write collision
- **Date**: 2026-07-28 (Task 0138).
- **Status**: deliberate behavior only where the primary guide is undefined;
  all ordinary RR=00/01/11 behavior is specification-derived.
- **Source**: 1988 TMS34010 User's Guide pages 6-10/6-11 and 6-45/6-46.
  The guide defines RR=00 as subtracting two from RINTVL per local clock,
  RR=01 as subtracting one, RR=11 as disabled, and bits 2-15 as a continuous
  counter whose borrow decrements ROWADR and requests refresh. REFCNT resets
  to zero and may be read or written, though software should disable refresh
  before writing.
- **Direct implementation**: reset zero plus active RR=00 produces a borrow
  on the first local clock after reset, then every 32 clocks. RR=01 similarly
  borrows first and then every 64 clocks. The request is registered for one
  core clock while the output row reflects the newly decremented ROWADR.
- **Reserved RR=10 choice**: the guide reserves this encoding without
  specifying an operation. The FPGA implementation treats it as disabled,
  holding REFCNT and issuing no request; RR=11 has the same hold behavior.
- **Write-collision choice**: a processor REFCNT load takes priority over an
  automatic decrement and suppresses a same-edge request. This makes the
  guide's otherwise-unreliable write-while-refresh-enabled case
  deterministic without changing conforming software, which disables
  refresh before the load.
- **Regression evidence**: `tb_refresh` locks ordinary count/borrow periods,
  descending rows, wrap, both non-counting encodings, load precedence, and
  reserved-bit retention. `tb_io_refresh` locks live processor reads/writes
  and the exported row/request/mode boundary.

## A0032 — Abstract RUN/EMU handshake and deterministic status
- **Date**: 2026-07-28 (Task 0128).
- **Status**: deliberate deterministic core-boundary choice, physically
  integrated by Task 0152.
- **Source**: 1988 TMS34010 User's Guide page 12-77 (“Initiate Emulation”)
  and page 2-10 (RUN/EMU and HLDA/EMUA pin descriptions).
- **Architectural behavior**: opcode `0x0100` asserts active-low EMUA while
  sampling RUN/EMU. RUN makes the instruction act as a NOP; EMU halts the
  processor for emulator control. Returning RUN resumes execution at the
  instruction following EMU.
- **FPGA core boundary**: `run_emu_n_i` is sampled during `CORE_EXECUTE`.
  `emua_n_o` is low for that execute cycle. When EMU is sampled low, the core
  enters `CORE_EMU_HALT`, holds EMUA low, and issues no memory request until
  RUN returns high. PC already contains the following instruction address.
- **Deterministic status choice**: the instruction page marks N/C/Z/V
  indeterminate. This RTL preserves the complete ST word in both sampled
  modes, providing deterministic FPGA behavior without software-visible flag
  writes.
- **Physical resolution**: Task 0152 synchronizes physical RUN/EMU, converts
  the core pulse through the A0042 held-event bridge, phase-latches the halt
  level, and combines Q1/Q2 EMUA with Q3/Q4 HLDA. This implementation does
  not claim an external emulator's private state-access protocol; it
  implements only the documented instruction handshake, halt, resume, and
  shared-pin indication.
- **Test**: `tb_emu` verifies the RUN pulse, EMU halt acknowledgement,
  memory/PC/register/ST quiescence, legal decode, and resume point.

## A0031 — Window-checking scope and implementation
- **Date**: 2026-06-07 through 2026-06-15 (Tasks 0105–0117), audited
  2026-07-28 (Task 0135).
- **Status**: implemented for every drawing instruction currently present.
- **Source**: 1988 UG §7.10 (Window Checking): W=0 off; W=1 hit detection;
  W=2 miss detection; W=3 clipping. WSTART=B5 and WEND=B6 are inclusive XY
  corners; the window-violation pending bit is INTPEND.WV (bit 11).
- **Array engines**: FILL XY and every PIXBLT with an XY destination implement
  all four modes. W=1 performs no drawing and reports overlap; W=2 requires
  full rectangle containment; W=3 clips per pixel and reports V=1 when any
  preclipping was required.
- **Incremental engines**: DRAV implements its per-pixel W=1/2/3 rules and
  always performs the XY advance. LINE clips in W=3 and aborts on the first
  hit/miss condition in W=1/W=2. PIXT operations with an XY destination
  perform a per-pixel test before register-to-XY or XY-to-XY writes.
- **Status/interrupt behavior**: the shared V update and `wvp_set` side channel
  implement the specified V/INTPEND.WV outcomes. The maskable-interrupt path
  can service WV after the drawing instruction reaches its boundary.
- **Non-XY forms**: window checking is tied to XY-addressed drawing forms, as
  represented in the instruction table. Do not extend it to ordinary field
  MOVE traffic sharing the same memory states.
- **Tests**: `tb_fill_window`, `tb_fill_w1`, `tb_fill_w2`,
  `tb_pixblt_window`, `tb_pixblt_w1`, `tb_pixblt_w2`, `tb_drav_win`,
  `tb_line_win`, `tb_line_abort`, and `tb_pixt_win`. Task 0135 strengthened
  W=3 V coverage and added XY-to-XY PIXT draw/skip/status cases.

## A0030 — RESOLVED: every interrupt initializes the live ST service context
- **Date**: 2026-06-04 (Task 0100); **resolved 2026-07-28 (Task 0123)**.
- **Status**: **RESOLVED** against the 1988 User's Guide §8.5 page 8-6.
- **Original assumption**: maskable/NMI entry cleared only ST.IE and preserved
  the remaining live status bits.
- **Primary evidence**: step 3's status-register diagram explicitly shows
  every bit cleared except `FS0=16`, yielding `0x0000_0010`. The text below
  confirms that interrupts are disabled, field 0 is 16-bit zero-extended, and
  field 1 is 32-bit zero-extended.
- **Conclusion**: every completed interrupt entry writes
  `ST_RESET_VALUE`. When context is saved, the exact pre-entry ST is pushed
  first and RETI restores it. HSTCTLH.NMIM changes only whether NMI pushes
  PC/ST and decrements SP; NMIM=1 still initializes the live service-context
  ST after fetching the vector.
- **Implementation/tests**: `CORE_INT_DONE` always writes
  `ST_RESET_VALUE`; its SP write remains gated by `int_push_q`.
  `tb_int_entry` distinguishes stacked old ST from live initialized ST, and
  `tb_nmi_nopush` verifies initialization without either push state.

## A0029 — FILL XY updates DADDR to a linear address
- **Date**: 2026-06-01; **resolved 2026-07-28 (Task 0133)**.
- **Status**: **RESOLVED** against the primary FILL XY instruction text.
- **Source**: 1988 TI TMS34010 User's Guide pages 12-84 through 12-86,
  especially the "Destination Array" section on page 12-85.
- **Resolution**: The guide separately states that DADDR initially contains
  the XY address used with OFFSET and CONVDP to calculate the linear start,
  that DADDR points to the next pixel during execution, and that it contains
  the *linear* address following the last pixel when complete. It further
  identifies that final position as the next X pixel on the final row. The
  existing writeback
  `linear_start + (DY - 1) * DPTCH + DX * PSIZE` is therefore exact; no
  reverse linear-to-XY conversion belongs in `CORE_FILL_WB`.
- **Status rule**: Page 12-86 says N/C/Z are Unaffected and V is Unaffected
  when window checking is disabled.
- **Regression evidence**: `tb_fill_xy` converts XY `0x00010020` to linear
  `0x00000910`, verifies both pitched rows, checks exact final DADDR
  `0x000009A0`, and snapshots the complete seeded ST unchanged for W=0.

## TODO / spec-uncertain (waiting on detailed read)

Task 0124 consolidates the assumptions that still affect observable
compatibility and all system-level work into `completion_audit.md`. Task 0154
closed the unscoped I/O-register-state item; remaining uncertainty is assigned
to the explicit video, cache/cycle-accuracy, CDC, and FPGA-realization gates.
