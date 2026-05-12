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
