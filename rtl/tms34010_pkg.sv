// -----------------------------------------------------------------------------
// tms34010_pkg.sv
//
// Architectural constants, widths, and shared typedefs for the TMS34010 core.
//
// This file is the single source of truth for project-wide widths and enum
// types. Other RTL files must not introduce parallel "magic number" widths.
// As more of the spec is implemented, this package grows with concrete
// register-bit layouts and instruction-class typedefs.
//
// Spec source: third_party/TMS34010_Info/docs/ti-official/
//              1988_TI_TMS34010_Users_Guide.pdf
//
// Phase 0: skeleton — only the typedefs/widths needed by the core FSM
// scaffold are defined here. Concrete architectural details (status register
// layout, register file indices, instruction word fields) land in Phase 1+.
// -----------------------------------------------------------------------------

package tms34010_pkg;

  // ---------------------------------------------------------------------------
  // Architectural widths
  // ---------------------------------------------------------------------------

  // TMS34010 is a 32-bit architecture with a bit-addressed memory model.
  // The external bus on the original device is 16 bits, but the RTL exposes
  // an internal-style request/valid interface at full architectural width;
  // an external glue module (Phase 6) handles the bus multiplexing.
  parameter int unsigned ADDR_WIDTH       = 32;
  parameter int unsigned DATA_WIDTH       = 32;

  // Field-size operands are 1..32 bits, encoded in 6 bits.
  // Spec: 1988 User's Guide, field-move/field-addressing chapter.
  parameter int unsigned FIELD_SIZE_WIDTH = 6;

  // ---------------------------------------------------------------------------
  // Instruction-stream constants
  //
  // Spec: bibliography/hdl-reimplementation/01-architecture.md
  // ("Instructions are 16-bit-aligned half-words in memory. PC is a
  //   bit-address but increments by 16 per fetch.")
  // ---------------------------------------------------------------------------
  parameter logic [FIELD_SIZE_WIDTH-1:0] INSTR_WORD_BITS = 6'd16;

  // Width of the PC's per-advance amount (in bits). 8 bits covers 1- to
  // 15-word instructions with headroom; the longest documented form is
  // 3 words (48 bits) for instructions with a 32-bit immediate.
  parameter int unsigned PC_ADVANCE_WIDTH = 8;

  // Reset PC value. Placeholder — the architectural reset sequence fetches
  // PC from the trap table near the top of address space (see
  // docs/assumptions.md entry A0008). Until Phase 8 implements the
  // reset-fetch sequence, the core boots at this constant.
  parameter logic [ADDR_WIDTH-1:0] RESET_PC = '0;

  // ---------------------------------------------------------------------------
  // Core top-level FSM states
  //
  // High-level state machine for the per-instruction execution pipeline.
  // The Phase 0 skeleton implements only CORE_RESET → CORE_FETCH; the rest
  // are declared so downstream code can refer to them and so the FSM's
  // `unique case` already covers them safely.
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    CORE_RESET     = 3'd0,
    CORE_FETCH     = 3'd1,
    CORE_DECODE    = 3'd2,
    CORE_EXECUTE   = 3'd3,
    CORE_MEMORY    = 3'd4,
    CORE_WRITEBACK = 3'd5
  } core_state_t;

endpackage : tms34010_pkg
