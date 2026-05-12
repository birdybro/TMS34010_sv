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
| MOVI IL  | `0x09E0 \| (R<<4) \| N`, +32-bit imm | SPVU004 listings | not started | none | TBD | none | TBD | Decoded space reserved; routes to ILLEGAL until Task 0013 wires the IMM_HI path. |

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
