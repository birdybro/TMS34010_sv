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
| SUB Rs,Rd | `0100 010S SSSR DDDD` (= `0x4400 \| (S<<5) \| (R<<4) \| D`) | SPVU001A A-14 | implemented | tb_sub_rr | N, C, Z, V | none | TBD | Rd - Rs → Rd. ALU operand swap (alu_a=Rd, alu_b=Rs) handled in the core. C is borrow output. |
| AND Rs,Rd  | `0101 000S SSSR DDDD` | SPVU001A A-14 | implemented | tb_logical_rr | N, Z (C, V cleared per A0009) | none | TBD | Rd & Rs → Rd. Commutative; default operand routing. |
| ANDN Rs,Rd | `0101 001S SSSR DDDD` | SPVU001A A-14 | implemented | tb_logical_rr | N, Z (C, V cleared) | none | TBD | Rd & ~Rs → Rd. Non-commutative — uses the same alu_a/b swap as SUB. |
| OR Rs,Rd   | `0101 010S SSSR DDDD` | SPVU001A A-14 | implemented | tb_logical_rr | N, Z (C, V cleared) | none | TBD | Rd \| Rs → Rd. Commutative. |
| XOR Rs,Rd  | `0101 011S SSSR DDDD` | SPVU001A A-14 | implemented | tb_logical_rr | N, Z (C, V cleared) | none | TBD | Rd ^ Rs → Rd. Encoding cross-checked against `XOR A0,A0 = 0x5600` in SPVU004 listing. |
| CMP Rs,Rd  | `0100 100S SSSR DDDD` | SPVU001A A-14 | implemented | tb_cmp_rr | N, C, Z, V | none | TBD | Flags from (Rd - Rs); **Rd unchanged** (nondestructive). First instruction in the project with `wb_reg_en = 0`. |
| JRcc short | `1100 cccc dddd dddd` | SPVU001A A-14, Table 12-8 | partial: UC/EQ/NE only (A0017) | tb_jruc_short, tb_jrcc_short | none | none | TBD | Conditional/unconditional 8-bit-signed-disp relative jump. cc ∈ {0000 UC, 0100 EQ, 0111 NE} verified and decoded; other cc values trap as ILLEGAL until Table 12-8 is re-read. Target = PC_post_fetch + sign_extend(disp) × 16. disp ∈ {0x00, 0x80} reserved. |
| ADDK K,Rd | `0001 00KK KKKR DDDD` | SPVU001A A-14 (A0018) | implemented | tb_addk_subk | N, C, Z, V | none | TBD | K + Rd → Rd. K is 5-bit zero-extended. K=0 → literal 0 (per A0018; K=0 → 32 hypothesis NOT implemented). |
| SUBK K,Rd | `0001 01KK KKKR DDDD` | SPVU001A A-14 (A0018) | implemented | tb_addk_subk | N, C, Z, V | none | TBD | Rd - K → Rd. K is 5-bit zero-extended. C = borrow. |
| NEG Rd    | `0000 0011 101R DDDD` (bits[6:5]=01 in the unary family) | SPVU001A A-14 | implemented | tb_neg_not | N, C, Z, V | none | TBD | 0 - Rd → Rd. V=1 only when Rd was 0x8000_0000. |
| NOT Rd    | `0000 0011 111R DDDD` (bits[6:5]=11 in the unary family) | SPVU001A A-14 | implemented | tb_neg_not | N, Z (C, V cleared) | none | TBD | ~Rd → Rd. |
| ADDI IW K,Rd | `0000 1011 000R DDDD` + 16-bit imm | SPVU001A A-14 | implemented | tb_immi_iw | N, C, Z, V | none | TBD | Rd + sign_extend(K16, 32) → Rd. Reuses MOVI IW IMM_LO fetch. |
| SUBI IW K,Rd | `0000 1011 111R DDDD` + 16-bit imm | SPVU001A A-14 | implemented | tb_immi_iw | N, C, Z, V | none | TBD | Rd - sign_extend(K16, 32) → Rd. C is borrow. |
| CMPI IW K,Rd | `0000 1011 010R DDDD` + 16-bit imm | SPVU001A A-14 | implemented | tb_immi_iw | N, C, Z, V | none | TBD | Flags from Rd - sign_extend(K16); Rd unchanged. `wb_reg_en = 0`. |
| ABS Rd    | `0000 0011 100R DDDD` (bits[6:5]=00) | SPVU001A A-14 | **not started** | none | N, C, Z, V (with V on MIN_INT) | none | TBD | Deferred — ALU does not currently have an ABS op; would need a conditional NEG plus the V-on-MIN_INT subtlety. |
| NEGB Rd   | `0000 0011 110R DDDD` (bits[6:5]=10) | SPVU001A A-14 | **not started** | none | N, C, Z, V | none | TBD | Deferred — needs C-input handling (`Rd = -Rd - C`). |

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
