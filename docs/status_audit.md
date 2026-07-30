# Instruction status audit

Task 0135 reconciled every implemented TMS34010 instruction family against
the individual `Status Bits` tables in the 1988 TI TMS34010 User's Guide.
This document is the compact review matrix behind the per-instruction
`Flags` column in `instruction_coverage.md`.

The primary source is
`third_party/TMS34010_Info/docs/ti-official/1988_TI_TMS34010_Users_Guide.pdf`,
chapter 12. The instruction-summary chart was used only as an index; each
policy below was checked against the instruction's primary page.

## Notation and implementation policy

- `N`, `C`, `Z`, and `V` mean that the instruction writes that flag.
- `U` means the guide says **Unaffected**; the RTL must retain the old bit.
- `X` means **Undefined** or **Indeterminate**. The RTL deliberately retains
  the old bit. Preservation is a deterministic FPGA choice, not a claim that
  original silicon guaranteed preservation.
- A full ST operation such as PUTST, POPST, RETI, TRAP, or interrupt entry is
  listed separately from ordinary per-flag write masks.
- Runtime rules that cannot be expressed by the decoder's static mask are
  applied by `effective_flag_mask` or the graphics window sideband in
  `tms34010_core.sv`.

## Static instruction-family matrix

| Family / instructions | N | C | Z | V | Primary pages and notes |
|---|---:|---:|---:|---:|---|
| ADD, ADDC, ADDI IW/IL, ADDK | N | C | Z | V | 12-35 through 12-41 |
| SUB, SUBB, SUBI IW/IL, SUBK, CMP, CMPI IW/IL, NEG, NEGB | N | C | Z | V | 12-54, 12-168, 12-247 through 12-251; subtract-family C is borrow |
| ABS | N | U | Z | V | 12-34; V on minimum negative |
| AND, ANDN, ANDI/ANDNI, OR, ORI, XOR, XORI, NOT; CLR alias | U | U | Z | U | 12-42 through 12-45, 12-51, 12-171 through 12-173, 12-255/256 |
| MOVI IW/IL | N | U | Z | V=0 | 12-159/160; IW status follows the sign-extended value |
| MOVE register-to-register and every field/MOVB load | N | U | Z | V=0 | 12-118 through 12-160 as applicable; status follows the extended loaded value |
| MOVE/MOVB stores and memory-to-memory forms; MOVK, MOVX, MOVY, CVXYL | U | U | U | U | Corresponding move pages 12-118 through 12-163 and CVXYL 12-59 |
| SLA constant/register | N | C | Z | V | 12-239/240 |
| SRA constant/register | N | C | Z | U | 12-243/244 |
| SLL, SRL, RL constant/register | U | C | Z | U | 12-234/235, 12-241/242, 12-245/246 |
| BTST constant/register, LMO, ZEXT | U | U | Z | U | 12-46/47, 12-108, 12-257 |
| SEXT | N | U | Z | U | 12-237 |
| MPYS | N | U | Z | U | 12-164/165; even Rd uses the 64-bit result, odd Rd the stored low 32 bits |
| MPYU | U | U | Z | U | 12-166/167; even/odd Z follows the architecturally stored result width |
| DIVU | U | U | Z | V | 12-65/66; Z=0 on overflow |
| DIVS | N | U | Z | V | 12-63/64; N includes the documented `0x80000000` result case and negative quotients |
| MODU, MODS | U | U | Z | V | 12-112 through 12-114; Z is left untouched only for divisor zero; MODS may still write a valid remainder on signed quotient overflow |
| ADDXY, CMPXY | N | C | Z | V | 12-41 and 12-55; graphics-specific per-half meanings |
| SUBXY | N | C | Z | V | 12-252; equality plus signed XY greater-than tests |
| CPW | U | U | U | V | 12-57; V reports point outside the window |
| MMTM | N | U | U | U | 12-111; N is the guide's special `0 - Rp` result |
| CLRC, SETC | U | C | U | U | 12-50 and 12-236 |
| All branches, calls, RETS, DSJ forms, NOP, GETPC/EXGPC/REV, GETST, SETF, EXGF, DINT/EINT, PUSHST, and MMFM | U | U | U | U | Individual pages; these instructions have no ordinary NCZV update |

PUTST and POPST replace the full ST word from their register or memory source;
RETI restores the saved full ST word. TRAP and hardware-interrupt entry
install `ST_RESET_VALUE` after saving the old context where applicable. These
are explicit architectural ST transitions, not ALU flag updates, so they do
not use `wb_flag_mask`.

The exhaustive `tb_status_decode` sweep applies this matrix to all 65,536
opcode words. It checks every implemented decoding, including operand-field
variants, and rejects either a missing writer or any extra per-flag writer.
Runtime-qualified operations remain covered by the core-level benches below.

## Graphics and undefined-status matrix

| Operation | N/C/Z | V | Deterministic RTL behavior |
|---|---|---|---|
| FILL linear | U/U/U | U | Preserves all four flags |
| FILL XY, W=0 | U/U/U | U | Preserves all four flags |
| FILL XY, W=1 | U/U/U | 0 on overlap, 1 if wholly outside | V-only write |
| FILL XY, W=2 | U/U/U | 0 if wholly inside, 1 otherwise | V-only write; miss also requests WV |
| FILL XY, W=3 | U/U/U | 1 if any preclipping is required, 0 otherwise | V-only write after the array |
| PIXBLT binary-to-linear, linear-to-linear, or XY-to-linear | X/X/X | X | Preserves all four undefined bits |
| PIXBLT binary-to-XY or linear-to-XY | X/X/X | Window result; X at W=0 | Preserves undefined N/C/Z and W=0 V |
| PIXBLT XY-to-XY | U/U/U | Window result; U at W=0 | Preserves N/C/Z and W=0 V |
| PIXT register-to-linear and indirect-to-indirect linear | U/U/U | U | Preserves all four flags |
| PIXT indirect-to-register, linear or XY | X/X/X | 1 for nonzero pixel, 0 for zero | Preserves undefined N/C/Z; writes V |
| PIXT with an XY destination | U/U/U | 1 outside, 0 inside for W=1/2/3; U at W=0 | Applies to register-to-XY and XY-to-XY |
| DRAV | U/U/U | Window result; U at W=0 | V-only write for W=1/2/3 |
| LINE | X/X/X | Defined by the selected window operation | Preserves undefined N/C/Z; writes V only when window checking is active |
| EMU | X/X/X | X | Preserves complete ST as the documented deterministic FPGA choice in A0032 |

For array operations, “window result” follows §7.10 and the individual
instruction page: W=1 reports whether the array was completely outside,
W=2 reports lack of full containment, and W=3 reports whether any
preclipping was necessary. Single-pixel operations report whether their
destination point lies outside the inclusive WSTART/WEND rectangle.

## Corrections and regression evidence

The audit found and corrected these observable mismatches:

- MODS had incorrectly written N from the remainder and suppressed every
  overflow write. It now preserves N/C, preserves Z only for divisor zero,
  writes a valid remainder for nonzero-divisor signed quotient overflow, and
  sets V from quotient overflow. DIVS N now follows its primary-page
  exceptions.
- Odd-destination MPYS/MPYU flags had been derived from the discarded
  64-bit product. They now use the stored low 32-bit result.
- FILL XY and PIXBLT with an XY destination clipped correctly in W=3 but did
  not report preclipping in V. Task 0135 added the completion-time V write;
  Task 0165 additionally made the operation true up-front array preclipping,
  without changing that V-only result.
- XY-to-XY PIXT did not enter the destination-window path. It now applies the
  same W=1/2/3 draw/skip, V, and WV rules as other XY-destination PIXT writes.

Focused evidence is in `tb_div_flags`, `tb_mpy_flags`, `tb_fill_window`,
`tb_pixblt_window`, `tb_window_preclip`, and `tb_pixt_win`. Existing
arithmetic, logical, move, shift, field, control, and graphics benches remain
part of the complete regression.
