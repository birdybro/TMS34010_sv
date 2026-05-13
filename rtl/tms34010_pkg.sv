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
  // Added in Phase 3:
  //   CORE_FETCH_IMM_LO/HI — fetch the 16- or 32-bit immediate that follows
  //   long-immediate-form instructions (MOVI IW/IL, ADDI IW/IL, CMPI, etc.).
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    CORE_RESET        = 3'd0,
    CORE_FETCH        = 3'd1,
    CORE_DECODE       = 3'd2,
    CORE_FETCH_IMM_LO = 3'd3,
    CORE_FETCH_IMM_HI = 3'd4,
    CORE_EXECUTE      = 3'd5,
    CORE_MEMORY       = 3'd6,
    CORE_WRITEBACK    = 3'd7
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

  // ---------------------------------------------------------------------------
  // Instruction word + decoded-instruction skeleton
  //
  // Spec: bibliography/hdl-reimplementation/02-instruction-set.md
  //   §"Encoding shape": "16-bit-aligned half-words ... The decode space is
  //   dense — there is no easy 'top-bits-give-class' partition. Use the
  //   SPVU004 opcode chart ... rather than hand-rolling the decoder."
  //
  // Phase 3 skeleton: the only field populated by decode is `illegal`. The
  // rest of `decoded_instr_t` is intentionally absent until specific
  // instructions are added in Task 0011 onwards (one per task, each citing
  // the SPVU004 opcode-chart row that defines its encoding).
  // ---------------------------------------------------------------------------
  parameter int unsigned INSTR_WORD_WIDTH = 16;
  typedef logic [INSTR_WORD_WIDTH-1:0] instr_word_t;

  // Instruction class — used by the core control FSM to pick the
  // decode/execute/memory/writeback path. Widened to 6 bits in Task
  // 0029 when ADDC/SUBB pushed the count past 32.
  typedef enum logic [5:0] {
    INSTR_ILLEGAL    = 6'd0,
    INSTR_MOVI_IW    = 6'd1,  // MOVI IW K, Rd    — 16-bit sign-extended immediate
    INSTR_MOVI_IL    = 6'd2,  // MOVI IL K, Rd    — 32-bit immediate
    INSTR_MOVK       = 6'd3,  // MOVK K, Rd       — 5-bit zero-extended constant
    INSTR_ADD_RR     = 6'd4,  // ADD Rs, Rd       — Rs + Rd → Rd; both same file
    INSTR_SUB_RR     = 6'd5,  // SUB Rs, Rd       — Rd - Rs → Rd; both same file
    INSTR_AND_RR     = 6'd6,  // AND Rs, Rd       — Rd & Rs  → Rd
    INSTR_ANDN_RR    = 6'd7,  // ANDN Rs, Rd      — Rd & ~Rs → Rd
    INSTR_OR_RR      = 6'd8,  // OR Rs, Rd        — Rd | Rs  → Rd
    INSTR_XOR_RR     = 6'd9,  // XOR Rs, Rd       — Rd ^ Rs  → Rd
    INSTR_CMP_RR     = 6'd10, // CMP Rs, Rd       — flags from (Rd - Rs); Rd unchanged
    INSTR_JRCC_SHORT = 6'd11, // JRcc short       — conditional relative jump
                              //                    (cc=0 = UC = unconditional)
    INSTR_ADDK       = 6'd12, // ADDK K, Rd       — K + Rd → Rd  (K = 5-bit, zext)
    INSTR_SUBK       = 6'd13, // SUBK K, Rd       — Rd - K → Rd  (K = 5-bit, zext)
    INSTR_NEG        = 6'd14, // NEG Rd           — 0 - Rd → Rd
    INSTR_NOT        = 6'd15, // NOT Rd           — ~Rd → Rd     (C, V cleared)
    INSTR_ADDI_IW    = 6'd16, // ADDI IW K, Rd    — Rd + sext(K16) → Rd
    INSTR_SUBI_IW    = 6'd17, // SUBI IW K, Rd    — Rd - sext(K16) → Rd
    INSTR_CMPI_IW    = 6'd18, // CMPI IW K, Rd    — flags from Rd - sext(K16); Rd unchanged
    INSTR_SLA_K      = 6'd19, // SLA K, Rd        — Rd << K (arithmetic, may set V)
    INSTR_SLL_K      = 6'd20, // SLL K, Rd        — Rd << K (logical)
    INSTR_SRA_K      = 6'd21, // SRA K, Rd        — Rd >>> K (arithmetic / sign-extend)
    INSTR_SRL_K      = 6'd22, // SRL K, Rd        — Rd >> K  (logical, MSB ← 0)
    INSTR_RL_K       = 6'd23, // RL K, Rd         — Rd ROL K (rotate left)
    INSTR_ADDI_IL    = 6'd24, // ADDI IL K, Rd    — Rd + K32 → Rd
    INSTR_SUBI_IL    = 6'd25, // SUBI IL K, Rd    — Rd - K32 → Rd
    INSTR_CMPI_IL    = 6'd26, // CMPI IL K, Rd    — flags from Rd - K32; Rd unchanged
    INSTR_ANDI_IL    = 6'd27, // ANDI IL K, Rd    — Rd & K32 → Rd
    INSTR_ORI_IL     = 6'd28, // ORI  IL K, Rd    — Rd | K32 → Rd
    INSTR_XORI_IL    = 6'd29, // XORI IL K, Rd    — Rd ^ K32 → Rd
    INSTR_MOVE_RR    = 6'd30, // MOVE Rs, Rd      — Rs → Rd (same-file reg-reg)
    INSTR_NOP        = 6'd31, // NOP              — no operation, PC advances only
    INSTR_ADDC_RR    = 6'd32, // ADDC Rs, Rd      — Rs + Rd + C → Rd (carry-in)
    INSTR_SUBB_RR    = 6'd33, // SUBB Rs, Rd      — Rd - Rs - C → Rd (borrow-in)
    INSTR_JRCC_LONG  = 6'd34, // JRcc Address     — long form: 16-bit signed disp
                              //                    in the following word; target =
                              //                    PC_after_both_fetches + disp*16
    INSTR_JUMP_RS    = 6'd35, // JUMP Rs          — Rs → PC (bottom 4 bits cleared)
    INSTR_DSJ        = 6'd36, // DSJ Rd, Address  — Rd-1→Rd; if Rd!=0 branch (long form)
    INSTR_DSJEQ      = 6'd37, // DSJEQ Rd, Address — if Z=1: DSJ semantics; else skip
    INSTR_DSJNE      = 6'd38, // DSJNE Rd, Address — if Z=0: DSJ semantics; else skip
    INSTR_JACC       = 6'd39, // JAcc Address      — absolute-form conditional jump
                              //                     (low byte = 0x80; 32-bit abs addr follows)
    INSTR_DSJS       = 6'd40  // DSJS Rd, Address  — short form: 5-bit offset + 1-bit
                              //                     direction; single-word instruction
  } instr_class_t;

  // Condition codes used by JRcc / JAcc (and other conditional ops).
  // Source: SPVU001A Table 12-8 ("Condition Codes for JRcc and JAcc
  // Instructions"), as re-extracted cleanly with `pdftotext -layout`
  // from the long-form JRcc page (12-96). The earlier (A0017) hand-
  // guess of EQ=0100 and NE=0111 was WRONG — those codes are actually
  // LT and GT, respectively. Corrected in Task 0030; see A0023.
  parameter logic [3:0] CC_UC = 4'b0000;  // unconditional
  parameter logic [3:0] CC_LO = 4'b0001;  // lower-than       (unsigned; C = 1; alias "B")
  parameter logic [3:0] CC_LS = 4'b0010;  // lower-or-same    (unsigned; C | Z = 1)
  parameter logic [3:0] CC_HI = 4'b0011;  // higher-than      (unsigned; ~C & ~Z = 1)
  parameter logic [3:0] CC_LT = 4'b0100;  // less-than        (signed;   N ^ V = 1)
  parameter logic [3:0] CC_GE = 4'b0101;  // greater-or-equal (signed;   N ^ V = 0; alias "JRZ" in spec when comparing-to-zero? — see A0023)
  parameter logic [3:0] CC_LE = 4'b0110;  // less-or-equal    (signed;   (N ^ V) | Z = 1)
  parameter logic [3:0] CC_GT = 4'b0111;  // greater-than     (signed;   !(N ^ V) & !Z = 1)
  parameter logic [3:0] CC_HS = 4'b1001;  // higher-or-same   (unsigned; C = 0; alias "NC")
  parameter logic [3:0] CC_EQ = 4'b1010;  // equal            (Z = 1; alias "JRZ")
  parameter logic [3:0] CC_NE = 4'b1011;  // not-equal        (Z = 0; alias "JRNZ")

  // What the control FSM needs from decode in order to execute. Fields are
  // populated only when the instruction class uses them; the rest hold safe
  // defaults (REG_FILE_A, idx 0, ALU_OP_PASS_A, etc.) so an undriven path
  // never mis-writes the register file.
  typedef struct packed {
    logic          illegal;     // 1 if the encoding is not recognized
    instr_class_t  iclass;      // dispatch class for the control FSM
    reg_file_t     rd_file;     // destination register file (A or B); also
                                // governs Rs file for reg-reg ops because
                                // TMS34010 reg-reg ops constrain Rs and Rd
                                // to the same file (single R bit in encoding).
    reg_idx_t      rd_idx;      // destination register index
    reg_idx_t      rs_idx;      // source register index (reg-reg ops)
    logic          needs_imm16; // fetch one extra 16-bit word for immediate
    logic          needs_imm32; // fetch two extra 16-bit words; LO first then HI
    logic          imm_sign_extend; // if 1, sign-extend imm16 to 32 bits
    alu_op_t       alu_op;      // ALU op to use in CORE_EXECUTE
    shift_op_t     shift_op;    // shifter op (used when result_source = SHIFTER)
    logic          use_shifter; // 1 ⇒ writeback from shifter, else from ALU
    logic [4:0]    k5;          // K-form 5-bit constant (MOVK, ADDK, SUBK, ...)
    logic [3:0]    branch_cc;   // condition code for JRcc / JAcc / DSJcc
    logic          wb_reg_en;   // 1 ⇒ regfile write in CORE_WRITEBACK
    logic          wb_flags_en; // 1 ⇒ ST flag update in CORE_WRITEBACK
  } decoded_instr_t;

endpackage : tms34010_pkg
