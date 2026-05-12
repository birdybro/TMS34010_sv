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

  // ---------------------------------------------------------------------------
  // Register file types
  //
  // Spec: bibliography/hdl-reimplementation/03-registers.md
  //   - Two 15-entry general-purpose register banks (A and B).
  //   - One shared stack pointer accessible from both banks as A15/B15.
  //   - All 32 bits.
  // ---------------------------------------------------------------------------
  typedef enum logic {
    REG_FILE_A = 1'b0,
    REG_FILE_B = 1'b1
  } reg_file_t;

  // 4-bit register index inside a file. Index 4'hF is the shared SP alias.
  typedef logic [3:0] reg_idx_t;

  parameter reg_idx_t REG_SP_IDX = 4'hF;

  // ---------------------------------------------------------------------------
  // ALU operation enum
  //
  // Spec sources:
  //   - bibliography/hdl-reimplementation/02-instruction-set.md
  //     §"Arithmetic / Logical": "N, C, Z, V plus the field-size mode bits
  //     ... all live in the ST register".
  //   - bibliography/hdl-reimplementation/03-registers.md §"Status register".
  //
  // Concrete per-instruction flag semantics (TI's exact carry-vs-borrow
  // convention, V on NEG / ABS minimum-negative, etc.) are captured in
  // docs/assumptions.md as A0009 until SPVU001A Appendix A is read in
  // detail. The ALU implements the "obvious" two's-complement /
  // carry-out-of-MSB convention and matches the standard:
  //   C = unsigned overflow (carry from MSB on ADD; "borrow" output on SUB,
  //       which here equals NOT carry-out-of-(a + ~b + 1)).
  //   V = signed overflow.
  //   N = result[31].
  //   Z = result == 0.
  // ---------------------------------------------------------------------------
  typedef enum logic [3:0] {
    ALU_OP_ADD    = 4'd0,
    ALU_OP_ADDC   = 4'd1,
    ALU_OP_SUB    = 4'd2,
    ALU_OP_SUBB   = 4'd3,
    ALU_OP_CMP    = 4'd4,
    ALU_OP_AND    = 4'd5,
    ALU_OP_ANDN   = 4'd6,
    ALU_OP_OR     = 4'd7,
    ALU_OP_XOR    = 4'd8,
    ALU_OP_NOT    = 4'd9,
    ALU_OP_NEG    = 4'd10,
    ALU_OP_PASS_A = 4'd11,
    ALU_OP_PASS_B = 4'd12
  } alu_op_t;

  typedef struct packed {
    logic n;
    logic c;
    logic z;
    logic v;
  } alu_flags_t;

  // ---------------------------------------------------------------------------
  // Shifter operation enum
  //
  // Spec source: bibliography/hdl-reimplementation/01-architecture.md
  //   §"Top-level blocks" — "32-bit barrel shifter; the shifter is critical
  //   for field operations and pixel shifts"; 02-instruction-set.md lists
  //   SLA, SLL, SRA, SRL, RL as the shift/rotate primitives.
  //
  // SLA vs SLL is per-spec: same shifted output, may differ on V flag (V on
  // sign-change during left shift). Tracked in docs/assumptions.md A0009;
  // both treated identically here until SPVU001A Appendix A is read.
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    SHIFT_OP_SLL = 3'd0,  // shift left, logical (fill 0)
    SHIFT_OP_SLA = 3'd1,  // shift left, arithmetic (alias of SLL; V flag TBD)
    SHIFT_OP_SRL = 3'd2,  // shift right, logical (fill 0)
    SHIFT_OP_SRA = 3'd3,  // shift right, arithmetic (sign-extend)
    SHIFT_OP_RL  = 3'd4,  // rotate left
    SHIFT_OP_RR  = 3'd5   // rotate right
  } shift_op_t;

  parameter int unsigned SHIFT_AMOUNT_WIDTH = 5;  // 32-bit shifter, 0..31

  // ---------------------------------------------------------------------------
  // Status register bit positions
  //
  // Spec: bibliography/hdl-reimplementation/03-registers.md §"Status register"
  //   ("Read SPVU001A Chapter 2 for the exact bit layout").
  //
  // The N/C/Z/V flag positions below are PLACEHOLDERS pending detailed
  // SPVU001A read. See docs/assumptions.md A0010. Consumers reference the
  // ST module's named flag outputs (`n_o`, `c_o`, `z_o`, `v_o`) rather than
  // bit positions directly; the bit positions matter only to PUSHST /
  // POPST / MMTM ST / MMFM ST. When the layout is confirmed, only these
  // parameters change.
  // ---------------------------------------------------------------------------
  parameter int unsigned ST_N_BIT = 31;
  parameter int unsigned ST_C_BIT = 30;
  parameter int unsigned ST_Z_BIT = 29;
  parameter int unsigned ST_V_BIT = 28;

endpackage : tms34010_pkg
