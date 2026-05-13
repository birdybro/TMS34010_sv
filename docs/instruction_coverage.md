# Instruction coverage

> Status: **empty**. No instructions have been implemented. Decode is a
> Phase 3 deliverable.

## How this table is maintained

When an instruction is added (decode + execute), one row is added here.
**Never silently stub.** If decode recognizes the opcode but execute is
unimplemented, the instruction is added with `Status = decoded, traps as illegal`.

Required columns:

- **Mnemonic** — assembler form.
- **Encoding** — opcode bit pattern, with operand-bit placeholders.
- **Source** — page/section in the 1988 User's Guide (or other doc in
  `third_party/TMS34010_Info`).
- **Status** — `not started` | `decoded` | `implemented` | `verified`.
- **Test** — name of the test (or `none` if not yet covered).
- **Flags** — flags written (N/V/C/Z, plus any '34010-specific bits).
- **Memory** — `none`, `read`, `write`, `rw`, `pixblt`, `linedraw`, etc.
- **Cycles** — cycle count if known from the spec; `unknown` otherwise.
- **Notes** — known limitations, deferred operand modes, etc.

## Table

| Mnemonic | Encoding | Source | Status      | Test | Flags | Memory | Cycles  | Notes |
|----------|----------|--------|-------------|------|-------|--------|---------|-------|
| MOVI IW  | `0x09C0 \| (R<<4) \| N`, +16-bit imm | SPVU004 assembler listings (A0012); SPVU001A §"Move Immediate" | implemented | tb_movi | N, Z (per A0011) | none | TBD | 16-bit immediate sign-extended to 32 bits → Rd. C, V cleared per A0011 / A0009. |
| MOVI IL  | `0x09E0 \| (R<<4) \| N`, +32-bit imm (LO,HI) | SPVU004 listings (A0012); SPVU001A §"Move Immediate" | implemented | tb_movi_il | N, Z (per A0011) | none | TBD | 32-bit immediate stored as two 16-bit words (low first, high second) → Rd. C, V cleared per A0011. |
| MOVK     | `0x1800 \| (K<<5) \| (R<<4) \| N`, single word | SPVU004 (A0013); SPVU001A §"Move Constant" | implemented | tb_movk | **none** (spec: "does not affect the status register") | none | TBD | 5-bit zero-extended K → Rd. Confirmed against `MOVK 1,A12 → 0x182C` and `MOVK 8,B1 → 0x1911`. K=0 hypothesis logged in A0013. |
| ADD Rs,Rd | `0100 000S SSSR DDDD` (= `0x4000 \| (S<<5) \| (R<<4) \| D`) | SPVU001A A-14 (A0014, A0015) | implemented | tb_add_rr | N, C, Z, V | none | TBD | Rs + Rd → Rd. First reg-reg arithmetic. Rs and Rd share file (single R bit). |
| ADDC Rs,Rd | `0100 001S SSSR DDDD` (= `0x4200 \| (S<<5) \| (R<<4) \| D`) | SPVU001A page 12-37 + summary table | implemented | tb_addc_subb | N, C, Z, V | none | TBD | Rs + Rd + C → Rd (carry-in from ST.C). Used for extended-precision chains with ADD/ADDI/ADDK. Default operand routing (alu_a=Rs, alu_b=Rd); commutative so no swap. |
| SUB Rs,Rd | `0100 010S SSSR DDDD` (= `0x4400 \| (S<<5) \| (R<<4) \| D`) | SPVU001A A-14 | implemented | tb_sub_rr | N, C, Z, V | none | TBD | Rd - Rs → Rd. ALU operand swap (alu_a=Rd, alu_b=Rs) handled in the core. C is borrow output. |
| SUBB Rs,Rd | `0100 011S SSSR DDDD` (= `0x4600 \| (S<<5) \| (R<<4) \| D`) | SPVU001A page 12-248 + summary table | implemented | tb_addc_subb | N, C, Z, V | none | TBD | Rd - Rs - C → Rd (borrow-in from ST.C). Same operand-swap as SUB. Spec page 12-248 supplies 14 authoritative test vectors; tb_addc_subb uses row 7 (`0x7FFFFFFE - 0xFFFFFFFE` with C=0 → `0x80000000`, NCZV=1101) as a signed-overflow corner-case check. |
| AND Rs,Rd  | `0101 000S SSSR DDDD` | SPVU001A A-14 | implemented | tb_logical_rr | N, Z (C, V cleared per A0009) | none | TBD | Rd & Rs → Rd. Commutative; default operand routing. |
| ANDN Rs,Rd | `0101 001S SSSR DDDD` | SPVU001A A-14 | implemented | tb_logical_rr | N, Z (C, V cleared) | none | TBD | Rd & ~Rs → Rd. Non-commutative — uses the same alu_a/b swap as SUB. |
| OR Rs,Rd   | `0101 010S SSSR DDDD` | SPVU001A A-14 | implemented | tb_logical_rr | N, Z (C, V cleared) | none | TBD | Rd \| Rs → Rd. Commutative. |
| XOR Rs,Rd  | `0101 011S SSSR DDDD` | SPVU001A A-14 | implemented | tb_logical_rr | N, Z (C, V cleared) | none | TBD | Rd ^ Rs → Rd. Encoding cross-checked against `XOR A0,A0 = 0x5600` in SPVU004 listing. |
| CMP Rs,Rd  | `0100 100S SSSR DDDD` | SPVU001A A-14 | implemented | tb_cmp_rr | N, C, Z, V | none | TBD | Flags from (Rd - Rs); **Rd unchanged** (nondestructive). First instruction in the project with `wb_reg_en = 0`. |
| JRcc short | `1100 cccc dddd dddd` | SPVU001A A-14, Table 12-8 (A0023) | implemented (11 of 16 cc codes) | tb_jruc_short, tb_jrcc_short, tb_jrcc_unsigned, tb_jrcc_signed | none | none | TBD | Conditional/unconditional 8-bit-signed-disp relative jump. Recognized cc values: 0000 UC; 0001 LO; 0010 LS; 0011 HI; 0100 LT; 0101 GE; 0110 LE; 0111 GT; 1001 HS; 1010 EQ; 1011 NE. Remaining codes (P/N, V/NV, JRYxx XY-compares) still deferred. Other cc values trap as ILLEGAL. Target = PC_post_fetch + sign_extend(disp) × 16. disp ∈ {0x00, 0x80} reserved (long-form / absolute-form markers). |
| JRcc long  | `1100 cccc 0000 0000` + 16-bit signed disp | SPVU001A page 12-96 (Table 12-8 cc subset; A0023) | implemented (same 11 cc codes as short form) | tb_jrcc_long | none | none | TBD | ±32K-word conditional relative jump. Opcode word's low byte = `0x00` unlocks the long form; next 16-bit word is the signed displacement. Target = PC_after_both_fetches + sign_extend(disp16) × 16 (matches the spec's PC' definition). Absolute form (low byte = `0x80`) still deferred. |
| JUMP Rs    | `0000 0001 011R DDDD` (= `0x0160 \| (R<<4) \| Rs`) | SPVU001A page 12-98 + summary table | implemented | tb_jump_rs | **none** ("Unaffected" on all four per page 12-98) | none | TBD | Register-indirect jump: Rs → PC, with bottom 4 bits forced to 0 (word alignment). Single-word instruction. No status update. |
| DSJ Rd, Address | `0000 1101 100R DDDD` (= `0x0D80 \| (R<<4) \| Rd`) + 16-bit signed offset | SPVU001A page 12-70 | implemented | tb_dsj | **none** ("Unaffected" per page 12-70) | none | TBD | Decrement Rd; if `Rd != 0` after decrement, jump (PC' + offset×16); else fall through. Two-word instruction. |
| DSJEQ Rd, Address | `0000 1101 101R DDDD` (= `0x0DA0 \| (R<<4) \| Rd`) + 16-bit signed offset | SPVU001A page 12-72 | implemented | tb_dsj | **none** | none | TBD | If `Z=1`: DSJ semantics. If `Z=0`: no decrement, no jump, fall through. |
| DSJNE Rd, Address | `0000 1101 110R DDDD` (= `0x0DC0 \| (R<<4) \| Rd`) + 16-bit signed offset | SPVU001A page 12-73 | implemented | tb_dsj | **none** | none | TBD | If `Z=0`: DSJ semantics. If `Z=1`: no decrement, no jump, fall through. DSJS (single-word short form with 5-bit offset + direction bit) remains deferred. |
| JAcc Address | `1100 cccc 1000 0000` + 32-bit absolute address (LO, HI) | SPVU001A page 12-91 + summary table | implemented (same 11 cc codes as JRcc) | tb_jacc | **none** ("Unaffected" per page 12-91) | none | TBD | Absolute conditional jump. Opcode low byte = `0x80` unlocks the absolute form. PC ← Address with bottom 4 bits forced to 0 (word alignment). Three-word instruction. Reuses needs_imm32 fetch path. |
| DSJS Rd, Address | `0011 1Dxx xxxR DDDD` (= `0x3800 \| (D<<10) \| (off<<5) \| (R<<4) \| Rd`) | SPVU001A page 12-74 + summary table | implemented | tb_dsjs | **none** ("Unaffected" per page 12-74) | none | TBD | Decrement-and-skip-jump SHORT form: single-word, 5-bit unsigned offset, 1-bit direction (D=0 forward, D=1 backward). Target = PC' ± offset×16. Decrements Rd unconditionally; jumps iff post-decrement Rd != 0. |
| ADDK K,Rd | `0001 00KK KKKR DDDD` | SPVU001A A-14 (A0018) | implemented | tb_addk_subk | N, C, Z, V | none | TBD | K + Rd → Rd. K is 5-bit zero-extended. K=0 → literal 0 (per A0018; K=0 → 32 hypothesis NOT implemented). |
| SUBK K,Rd | `0001 01KK KKKR DDDD` | SPVU001A A-14 (A0018) | implemented | tb_addk_subk | N, C, Z, V | none | TBD | Rd - K → Rd. K is 5-bit zero-extended. C = borrow. |
| NEG Rd    | `0000 0011 101R DDDD` (bits[6:5]=01 in the unary family) | SPVU001A A-14 | implemented | tb_neg_not | N, C, Z, V | none | TBD | 0 - Rd → Rd. V=1 only when Rd was 0x8000_0000. |
| NOT Rd    | `0000 0011 111R DDDD` (bits[6:5]=11 in the unary family) | SPVU001A A-14 | implemented | tb_neg_not | N, Z (C, V cleared) | none | TBD | ~Rd → Rd. |
| ADDI IW K,Rd | `0000 1011 000R DDDD` + 16-bit imm | SPVU001A A-14 | implemented | tb_immi_iw | N, C, Z, V | none | TBD | Rd + sign_extend(K16, 32) → Rd. Reuses MOVI IW IMM_LO fetch. |
| SUBI IW K,Rd | `0000 1011 111R DDDD` + 16-bit imm | SPVU001A A-14 | implemented | tb_immi_iw | N, C, Z, V | none | TBD | Rd - sign_extend(K16, 32) → Rd. C is borrow. |
| CMPI IW K,Rd | `0000 1011 010R DDDD` + 16-bit imm | SPVU001A A-14 | implemented | tb_immi_iw | N, C, Z, V | none | TBD | Flags from Rd - sign_extend(K16); Rd unchanged. `wb_reg_en = 0`. |
| SLA K,Rd | `0010 00KK KKKR DDDD` | SPVU001A A-14 (A0019) | implemented | tb_shift_k | N, C, Z | none | TBD | Rd << K (arithmetic). K=0 → no shift (literal per A0019). |
| SLL K,Rd | `0010 01KK KKKR DDDD` | SPVU001A A-14 (A0019) | implemented | tb_shift_k | N, C, Z | none | TBD | Rd << K (logical). |
| SRA K,Rd | `0010 10KK KKKR DDDD` | SPVU001A A-14 (A0019) | implemented | tb_shift_k | N, C, Z | none | TBD | Rd >>> K (sign-extending arithmetic right shift). |
| SRL K,Rd | `0010 11KK KKKR DDDD` | SPVU001A A-14 (A0019) | implemented | tb_shift_k | N, C, Z | none | TBD | Rd >> K (logical right shift; MSB ← 0). |
| RL  K,Rd | `0011 00KK KKKR DDDD` | SPVU001A A-14 (A0019) | implemented | tb_shift_k | N, C, Z | none | TBD | Rd ROL K (rotate left). |
| SLA Rs,Rd | `0110 000S SSSR DDDD` (= `0x6000 \| (Rs<<5) \| (R<<4) \| Rd`) | SPVU001A A-15 (A0019 ext.) | implemented | tb_shift_rr | N, C, Z, V | none | TBD | Rd << Rs[4:0] (arithmetic; shift amount from Rs's low 5 bits). |
| SLL Rs,Rd | `0110 001S SSSR DDDD` | SPVU001A A-15 | implemented | tb_shift_rr | N, C, Z | none | TBD | Rd << Rs[4:0] (logical). |
| SRA Rs,Rd | `0110 010S SSSR DDDD` | SPVU001A A-15 (A0019 ext.) | implemented | tb_shift_rr | N, C, Z | none | TBD | Rd >>> magnitude(Rs[4:0]) — per spec, the HW uses the **2's complement** of Rs[4:0] as the magnitude (assembler emits `-amount` mod 32). Core's shifter-amount mux applies the negation. |
| SRL Rs,Rd | `0110 011S SSSR DDDD` | SPVU001A A-15 | implemented | tb_shift_rr | C, Z | none | TBD | Rd >> magnitude(Rs[4:0]) (logical; same 2sCmp convention as SRA). |
| RL  Rs,Rd | `0110 100S SSSR DDDD` | SPVU001A A-15 | implemented | tb_shift_rr | C, Z | none | TBD | Rd ROL Rs[4:0]. |
| ADDI IL K,Rd | `0000 1011 001R DDDD` + 32-bit imm | SPVU001A A-14 | implemented | tb_immi_il | N, C, Z, V | none | TBD | Rd + K32 → Rd. |
| SUBI IL K,Rd | `0000 1101 000R DDDD` + 32-bit imm | SPVU001A A-14 | implemented | tb_immi_il | N, C, Z, V | none | TBD | Rd - K32 → Rd. **Different base prefix from the rest of the IL family.** |
| CMPI IL K,Rd | `0000 1011 011R DDDD` + 32-bit imm | SPVU001A A-14 | implemented | tb_immi_il | N, C, Z, V | none | TBD | Flags from Rd - K32; Rd unchanged. |
| ANDI IL K,Rd | `0000 1011 100R DDDD` + 32-bit imm | SPVU001A A-14 | implemented | tb_immi_il | N, Z | none | TBD | Rd & K32 → Rd. |
| ORI  IL K,Rd | `0000 1011 101R DDDD` + 32-bit imm | SPVU001A A-14 | implemented | tb_immi_il | N, Z | none | TBD | Rd \| K32 → Rd. |
| XORI IL K,Rd | `0000 1011 110R DDDD` + 32-bit imm | SPVU001A A-14 | implemented | tb_immi_il | N, Z | none | TBD | Rd ^ K32 → Rd. |
| MOVE Rs, Rd  | `1001 00FS SSSR DDDD` | SPVU001A A-14 (A0020) | implemented (F ignored) | tb_move_rr | N, Z | none | TBD | Rs → Rd. Field-size selector F currently ignored; full 32-bit copy. MOVE *Rs/Rd indirect variants still ILLEGAL pending Phase 5 field-size machinery. |
| NOP          | `0000 0011 0000 0000` (= `0x0300`) | SPVU001A §"NOP" page 12-170 (A0021) | implemented | tb_nop | **none** ("processor status is otherwise unaffected") | none | TBD | No operation — PC advances to the next instruction, ST and registers untouched. Distinct from the unary family at `0000 0011 1xxx xxxx`; ABS A0 = `0x0380`, not `0x0300`. |
| ABS Rd    | `0000 0011 100R DDDD` (= `0x0380 \| (R<<4) \| Rd`) | SPVU001A page 12-34 | implemented (spec-correct after A0024 RESOLVED in Task 0037) | tb_abs_negb, tb_btst | N, Z, V (C truly **Unaffected** via wb_flag_mask) | none | TBD | `Rd ← \|Rd\|` via ALU_OP_ABS (conditional select between `a` and `0-a` based on the sign of `0-a`). V=1 when Rd was 0x80000000 (MIN_INT — `\|Rd\|` can't be represented; spec returns Rd unchanged). N reflects the sign of `0-Rd`, NOT the sign of the result. |
| NEGB Rd   | `0000 0011 110R DDDD` (= `0x03C0 \| (R<<4) \| Rd`) | SPVU001A page 12-168 | implemented | tb_abs_negb | N, C, Z, V | none | TBD | `Rd ← -Rd - C` via ALU_OP_SUBB with alu_a=0, alu_b=Rd. Used in sequence with NEG/SUB/SUBB/SUBI for multi-register negation. Spec page 12-168 provides 12 worked example vectors; tb_abs_negb uses four of them. |
| BTST K, Rd  | `0001 11KK KKKR DDDD` (= `0x1C00 \| (K<<5) \| (R<<4) \| Rd`) | SPVU001A page 12-46 + summary table | implemented | tb_btst | **Z only** (N/C/V truly Unaffected via wb_flag_mask) | none | TBD | Test bit K of Rd (K in 0..31). Z = 1 if bit K of Rd is 0, else Z = 0. Rd not written. Uses ALU_OP_AND with alu_b = `32'd1 << K`. |
| BTST Rs, Rd | `0100 101S SSSR DDDD` (= `0x4A00 \| (Rs<<5) \| (R<<4) \| Rd`) | SPVU001A page 12-47 + summary table | implemented | tb_btst | **Z only** (N/C/V Unaffected) | none | TBD | Same as BTST K but bit index comes from Rs[4:0]. Uses ALU_OP_AND with alu_b = `32'd1 << rf_rs1_data[4:0]`. |
| CLRC | `0x0320` (single fixed encoding) | SPVU001A summary table page A-14 | implemented | tb_st_ops | **C only** (cleared; N, Z, V Unaffected via wb_flag_mask) | none | TBD | Clear ST.C to 0. Uses constant-flags mux + wb_flag_mask = c-only. |
| SETC | `0x0DE0` (single fixed encoding) | SPVU001A summary table | implemented | tb_st_ops | **C only** (set; N, Z, V Unaffected) | none | TBD | Set ST.C to 1. Symmetric to CLRC. |
| GETST Rd | `0000 0001 100R DDDD` (= `0x0180 \| (R<<4) \| Rd`) | SPVU001A summary table | implemented | tb_st_ops | none (status unaffected) | none | TBD | Rd ← ST (32-bit copy of the status register). regfile-write-data mux routes `st_value` for this iclass. |
| PUTST Rs | `0000 0001 101R DDDD` (= `0x01A0 \| (R<<4) \| Rs`) | SPVU001A summary table | implemented | tb_st_ops | N, C, Z, V (whatever the source register contains at those bit positions) | none | TBD | ST ← Rs (full 32-bit write). Uses the existing `st_write_en` + `st_write_data` path on the status register; the in-Rs N/C/Z/V bits become the new ST flags. |
| GETPC Rd | `0000 0001 010R DDDD` (= `0x0140 \| (R<<4) \| Rd`) | SPVU001A summary table | implemented | tb_pc_ops | none | none | TBD | Rd ← current PC (bit-addressed, captured at CORE_WRITEBACK). |
| EXGPC Rd | `0000 0001 001R DDDD` (= `0x0120 \| (R<<4) \| Rd`) | SPVU001A summary table | implemented (A0025) | tb_pc_ops | none | none | TBD | Atomic swap PC ↔ Rd. PC ← `(old Rd & ~0xF)` (low 4 bits forced to 0 for word alignment per A0025); Rd ← old PC. Uses the regfile's async-read property to read the old Rd while writing the new value in the same WRITEBACK cycle. |
| REV Rd   | `0000 0000 001R DDDD` (= `0x0020 \| (R<<4) \| Rd`) | SPVU001A page 12-233 (A0025) | implemented | tb_pc_ops | none | none | TBD | Rd ← chip-revision constant. Per the spec's worked example, value = `0x0000_0008`. |

## Categories to populate (placeholder roadmap)

Filled in as Phase 3 progresses. Approximate groupings from the 1988
User's Guide ISA chapter:

- Move / load / store (MOVE, MOVB, MOVI, MOVK, etc.)
- Arithmetic (ADD, ADDC, ADDI, ADDK, SUB, SUBI, SUBK, NEG, ABS, CMP, ...)
- Logical (AND, ANDI, OR, ORI, XOR, XORI, NOT, ...)
- Shift / rotate (SLA, SLL, SRA, SRL, RL, ...)
- Field operations (MOVE field, EXGF, ...)
- Branches and jumps (JR, JRcc, JUMP, CALL, RETS, ...)
- Stack (PUSH, PUSHST, POP, POPST, ...)
- Graphics (PIXT, PIXBLT, FILL, LINE, DRAV, ...)
- Control (NOP, EMU, EINT, DINT, RETI, TRAP, ...)
