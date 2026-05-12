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
