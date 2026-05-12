// -----------------------------------------------------------------------------
// tms34010_decode.sv
//
// Combinational instruction decoder.
//
// Currently recognized:
//   MOVI IW K, Rd  — `0x09C0 | (R<<4) | N`     +16-bit sign-extended imm
//   MOVI IL K, Rd  — `0x09E0 | (R<<4) | N`     +32-bit imm (LO,HI)
//   MOVK K, Rd     — `0x1800 | (K<<5) | (R<<4) | N`  (no flag update)
//   ADD Rs, Rd     — `0100 000S SSSR DDDD`     (7-bit prefix 0x40)
//                    Rs at bits[8:5], R at bit[4], Rd at bits[3:0].
//                    Rs and Rd share the same file (architectural
//                    constraint of TMS34010 reg-reg ops). Operation:
//                    Rs + Rd → Rd; flags N/C/Z/V from the sum.
//
// Flag policy and encodings cite SPVU001A Appendix A (Instruction Set
// summary chart, page A-14) and corresponding `docs/assumptions.md`
// entries (A0011-A0014).
//
// Spec sources cited:
//   third_party/TMS34010_Info/tools/assembler/
//     TMS34010_Assembly_Language_Tools_Users_Guide_SPVU004.pdf
//     (the assembler manual; the assembled listings on pages ~1356, 3823,
//      3898 show the bit-level encoding for MOVI IW. Cross-referenced
//      against `MOVI pbuf_sz, A4 → 0x09C4 0005` and
//      `MOVI array_size, A2 → 0x09C2 0x0640`.)
//   third_party/TMS34010_Info/bibliography/hdl-reimplementation/
//     02-instruction-set.md  §"Encoding shape" + §"Move and load/store".
//
// Encoding layout (MOVI IW / IL share the top-10 prefix):
//   bits[15:6] = 10'b00_0010_0111   (= 0x027)
//   bit[5]     = 0 (MOVI IW, 16-bit imm) or 1 (MOVI IL, 32-bit imm)
//   bit[4]     = R    (file bit: 0 = A file, 1 = B file)
//   bits[3:0]  = N    (register index 0..15; idx 15 = SP alias)
//
// Synthesis notes:
//   - One `always_comb` block.
//   - Safe defaults at the top: illegal output if no arm matches.
//   - No `/`, no `%`, no loops, no `initial`.
// -----------------------------------------------------------------------------

module tms34010_decode
  import tms34010_pkg::*;
(
  input  instr_word_t    instr,
  output decoded_instr_t decoded
);

  // Fixed-width views of the top opcode bits.
  logic [9:0] top10;
  logic [6:0] top7;
  logic [5:0] top6;
  assign top10 = instr[INSTR_WORD_WIDTH-1:6];
  assign top7  = instr[INSTR_WORD_WIDTH-1:9];
  assign top6  = instr[INSTR_WORD_WIDTH-1:10];

  // Opcode prefixes (each cited from SPVU001A Appendix A page A-14).
  localparam logic [9:0] MOVI_TOP10   = 10'b00_0010_0111;
  localparam logic [5:0] MOVK_TOP6    = 6'b00_0110;
  // K-family arithmetic shares the top-4 prefix 4'b0001; bits[11:10]
  // select the operation (00=ADDK, 01=SUBK, 10=MOVK, 11=BTST K).
  localparam logic [5:0] ADDK_TOP6    = 6'b00_0100;  // chart: 0001 00KK KKKR DDDD
  localparam logic [5:0] SUBK_TOP6    = 6'b00_0101;  // chart: 0001 01KK KKKR DDDD
  // Single-register unary family: bits[15:7] = 9'b000000111 (= 0x007);
  // bits[6:5] picks sub-op: 00=ABS, 01=NEG, 10=NEGB, 11=NOT.
  localparam logic [8:0] UNARY_TOP9    = 9'b0000_0011_1;
  // 16-bit-immediate arithmetic family. All share bits[15:5] (11-bit
  // prefix), bottom 5 bits are {R, Rd[3:0]}. The immediate value
  // follows in the next 16-bit word, sign-extended to 32 bits.
  localparam logic [10:0] ADDI_IW_TOP11 = 11'b0000_1011_000;  // ADDI IW
  localparam logic [10:0] SUBI_IW_TOP11 = 11'b0000_1011_111;  // SUBI IW
  localparam logic [10:0] CMPI_IW_TOP11 = 11'b0000_1011_010;  // CMPI IW

  // K-form shift family. Each is a top-6 prefix; bits[9:5] = K (5-bit
  // shift amount); bit[4] = R; bits[3:0] = Rd.
  localparam logic [5:0] SLA_K_TOP6  = 6'b001000;  // 0010 00KK KKKR DDDD
  localparam logic [5:0] SLL_K_TOP6  = 6'b001001;  // 0010 01KK KKKR DDDD
  localparam logic [5:0] SRA_K_TOP6  = 6'b001010;  // 0010 10KK KKKR DDDD
  localparam logic [5:0] SRL_K_TOP6  = 6'b001011;  // 0010 11KK KKKR DDDD
  localparam logic [5:0] RL_K_TOP6   = 6'b001100;  // 0011 00KK KKKR DDDD
  localparam logic [6:0] ADD_RR_TOP7  = 7'b0100_000;  // chart: 0100 000S SSSR DDDD
  localparam logic [6:0] SUB_RR_TOP7  = 7'b0100_010;  // chart: 0100 010S SSSR DDDD
  localparam logic [6:0] AND_RR_TOP7  = 7'b0101_000;  // chart: 0101 000S SSSR DDDD
  localparam logic [6:0] ANDN_RR_TOP7 = 7'b0101_001;  // chart: 0101 001S SSSR DDDD
  localparam logic [6:0] OR_RR_TOP7   = 7'b0101_010;  // chart: 0101 010S SSSR DDDD
  localparam logic [6:0] XOR_RR_TOP7  = 7'b0101_011;  // chart: 0101 011S SSSR DDDD
  localparam logic [6:0] CMP_RR_TOP7  = 7'b0100_100;  // chart: 0100 100S SSSR DDDD

  // JRcc short form: chart row "1100 code xxxx xxxx" with any cc.
  // bits[15:12] = 4'b1100; bits[11:8] = cc (4 bits); bits[7:0] = signed
  // 8-bit displacement. The two low-byte values 0x00 and 0x80 are reserved
  // (long-relative and absolute-form markers respectively).
  localparam logic [3:0] JRCC_TOP4 = 4'b1100;

  // Reg-reg ops use bits[8:5] for Rs index.
  reg_idx_t rs_idx_from_instr;
  assign rs_idx_from_instr = instr[8:5];

  // Top-11 view of the encoding (for ADDI/SUBI/CMPI IW which share an
  // 11-bit prefix).
  logic [10:0] top11;
  assign top11 = instr[INSTR_WORD_WIDTH-1:5];

  // Reg-field decoders (5 bits = file + 4-bit index).
  reg_file_t reg_file_from_instr;
  reg_idx_t  reg_idx_from_instr;
  assign reg_file_from_instr = reg_file_t'(instr[4]);
  assign reg_idx_from_instr  = instr[3:0];

  always_comb begin
    // -----------------------------------------------------------------------
    // Safe defaults: report ILLEGAL with all execution metadata cleared.
    // -----------------------------------------------------------------------
    decoded.illegal         = 1'b1;
    decoded.iclass          = INSTR_ILLEGAL;
    decoded.rd_file         = REG_FILE_A;
    decoded.rd_idx          = '0;
    decoded.rs_idx          = '0;
    decoded.needs_imm16     = 1'b0;
    decoded.needs_imm32     = 1'b0;
    decoded.imm_sign_extend = 1'b0;
    decoded.alu_op          = ALU_OP_PASS_A;
    decoded.shift_op        = SHIFT_OP_SLL;
    decoded.use_shifter     = 1'b0;
    decoded.k5              = '0;
    decoded.branch_cc       = '0;
    decoded.wb_reg_en       = 1'b0;
    decoded.wb_flags_en     = 1'b0;

    // -----------------------------------------------------------------------
    // MOVI IW K, Rd
    // -----------------------------------------------------------------------
    if (top10 == MOVI_TOP10 && instr[5] == 1'b0) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_MOVI_IW;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.needs_imm16     = 1'b1;
      decoded.needs_imm32     = 1'b0;
      decoded.imm_sign_extend = 1'b1;
      decoded.alu_op          = ALU_OP_PASS_B;   // pass the immediate through
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    // -----------------------------------------------------------------------
    // MOVI IL K, Rd
    // -----------------------------------------------------------------------
    if (top10 == MOVI_TOP10 && instr[5] == 1'b1) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_MOVI_IL;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.needs_imm16     = 1'b0;
      decoded.needs_imm32     = 1'b1;
      decoded.imm_sign_extend = 1'b0;   // 32-bit immediate is already full-width
      decoded.alu_op          = ALU_OP_PASS_B;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    // -----------------------------------------------------------------------
    // MOVK K, Rd
    // -----------------------------------------------------------------------
    if (top6 == MOVK_TOP6) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_MOVK;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.k5              = instr[9:5];
      decoded.needs_imm16     = 1'b0;
      decoded.needs_imm32     = 1'b0;
      decoded.imm_sign_extend = 1'b0;
      decoded.alu_op          = ALU_OP_PASS_B;   // routed through ALU like MOVI
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b0;            // MOVK doesn't touch ST
    end

    // -----------------------------------------------------------------------
    // ADDK K, Rd  (K + Rd → Rd; K is 5-bit zero-extended per A0018)
    // -----------------------------------------------------------------------
    if (top6 == ADDK_TOP6) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_ADDK;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.k5              = instr[9:5];
      decoded.alu_op          = ALU_OP_ADD;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    // -----------------------------------------------------------------------
    // SUBK K, Rd  (Rd - K → Rd; K is 5-bit zero-extended per A0018)
    // -----------------------------------------------------------------------
    if (top6 == SUBK_TOP6) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_SUBK;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.k5              = instr[9:5];
      decoded.alu_op          = ALU_OP_SUB;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    // -----------------------------------------------------------------------
    // IW-form immediate arithmetic (ADDI, SUBI, CMPI)
    //
    // All three share the encoding shape:
    //   bits[15:5] = 11-bit prefix selecting the op
    //   bit[4]     = R   (file)
    //   bits[3:0]  = Rd index
    //   next word  = 16-bit immediate (sign-extended to 32 bits)
    //
    // CMPI does not write Rd (wb_reg_en = 0), matching the same
    // contract as CMP Rs, Rd.
    // -----------------------------------------------------------------------
    if (top11 == ADDI_IW_TOP11) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_ADDI_IW;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.needs_imm16     = 1'b1;
      decoded.imm_sign_extend = 1'b1;
      decoded.alu_op          = ALU_OP_ADD;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    if (top11 == SUBI_IW_TOP11) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_SUBI_IW;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.needs_imm16     = 1'b1;
      decoded.imm_sign_extend = 1'b1;
      decoded.alu_op          = ALU_OP_SUB;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    if (top11 == CMPI_IW_TOP11) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_CMPI_IW;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.needs_imm16     = 1'b1;
      decoded.imm_sign_extend = 1'b1;
      decoded.alu_op          = ALU_OP_CMP;
      decoded.wb_reg_en       = 1'b0;
      decoded.wb_flags_en     = 1'b1;
    end

    // -----------------------------------------------------------------------
    // K-form shift instructions
    //
    // All five share the encoding shape:
    //   bits[15:10] = 6-bit shift-op prefix (table below)
    //   bits[9:5]   = K (5-bit shift amount; per A0019 treated literally —
    //                    K=0 means no shift, not 32 as some TI ISAs use)
    //   bit[4]      = R (file)
    //   bits[3:0]   = Rd index
    //
    //   SLA K, Rd  →  6'b001000   (shift left arithmetic)
    //   SLL K, Rd  →  6'b001001   (shift left logical)
    //   SRA K, Rd  →  6'b001010   (shift right arithmetic / sign-extend)
    //   SRL K, Rd  →  6'b001011   (shift right logical)
    //   RL  K, Rd  →  6'b001100   (rotate left)
    // -----------------------------------------------------------------------
    if (top6 == SLA_K_TOP6) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_SLA_K;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.k5          = instr[9:5];
      decoded.shift_op    = SHIFT_OP_SLA;
      decoded.use_shifter = 1'b1;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top6 == SLL_K_TOP6) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_SLL_K;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.k5          = instr[9:5];
      decoded.shift_op    = SHIFT_OP_SLL;
      decoded.use_shifter = 1'b1;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top6 == SRA_K_TOP6) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_SRA_K;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.k5          = instr[9:5];
      decoded.shift_op    = SHIFT_OP_SRA;
      decoded.use_shifter = 1'b1;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top6 == SRL_K_TOP6) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_SRL_K;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.k5          = instr[9:5];
      decoded.shift_op    = SHIFT_OP_SRL;
      decoded.use_shifter = 1'b1;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top6 == RL_K_TOP6) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_RL_K;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.k5          = instr[9:5];
      decoded.shift_op    = SHIFT_OP_RL;
      decoded.use_shifter = 1'b1;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end

    // -----------------------------------------------------------------------
    // Single-register unary family
    //   ABS  Rd   bits[6:5] = 00  (deferred — V-on-MIN_INT spec subtlety)
    //   NEG  Rd   bits[6:5] = 01  (implemented; ALU_OP_NEG)
    //   NEGB Rd   bits[6:5] = 10  (deferred — needs C-input handling)
    //   NOT  Rd   bits[6:5] = 11  (implemented; ALU_OP_NOT)
    // -----------------------------------------------------------------------
    if (instr[15:7] == UNARY_TOP9) begin
      case (instr[6:5])
        2'b01: begin   // NEG
          decoded.illegal         = 1'b0;
          decoded.iclass          = INSTR_NEG;
          decoded.rd_file         = reg_file_from_instr;
          decoded.rd_idx          = reg_idx_from_instr;
          decoded.alu_op          = ALU_OP_NEG;
          decoded.wb_reg_en       = 1'b1;
          decoded.wb_flags_en     = 1'b1;
        end
        2'b11: begin   // NOT
          decoded.illegal         = 1'b0;
          decoded.iclass          = INSTR_NOT;
          decoded.rd_file         = reg_file_from_instr;
          decoded.rd_idx          = reg_idx_from_instr;
          decoded.alu_op          = ALU_OP_NOT;
          decoded.wb_reg_en       = 1'b1;
          decoded.wb_flags_en     = 1'b1;
        end
        default: ;   // ABS / NEGB → ILLEGAL until landed
      endcase
    end

    // -----------------------------------------------------------------------
    // ADD Rs, Rd  (reg-reg add; Rs and Rd in the same file)
    // -----------------------------------------------------------------------
    if (top7 == ADD_RR_TOP7) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_ADD_RR;
      decoded.rd_file         = reg_file_from_instr;   // single R bit governs both
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.rs_idx          = rs_idx_from_instr;
      decoded.alu_op          = ALU_OP_ADD;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    // -----------------------------------------------------------------------
    // SUB Rs, Rd  (Rd - Rs → Rd; same-file constraint)
    // -----------------------------------------------------------------------
    if (top7 == SUB_RR_TOP7) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_SUB_RR;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.rs_idx          = rs_idx_from_instr;
      // Operand routing: alu_a = Rd, alu_b = Rs so that SUB computes
      // (a - b) = (Rd - Rs) → Rd, matching the spec "Rd - Rs → Rd".
      // See the alu_b mux in tms34010_core.sv for the swap.
      decoded.alu_op          = ALU_OP_SUB;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    // -----------------------------------------------------------------------
    // Reg-reg logical ops (AND, ANDN, OR, XOR).
    // All share the same encoding shape with a different 7-bit prefix.
    // Operand routing: alu_a = Rs (default), alu_b = Rd. Operations are
    // commutative (or via ANDN's complement-of-b form) so no swap is
    // needed.
    // -----------------------------------------------------------------------
    if (top7 == AND_RR_TOP7) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_AND_RR;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.rs_idx          = rs_idx_from_instr;
      decoded.alu_op          = ALU_OP_AND;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    if (top7 == ANDN_RR_TOP7) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_ANDN_RR;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.rs_idx          = rs_idx_from_instr;
      // ANDN per spec: Rd = Rd & ~Rs. ALU_OP_ANDN computes a & ~b, so
      // we need alu_a = Rd, alu_b = Rs. Operand swap handled in core.
      decoded.alu_op          = ALU_OP_ANDN;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    if (top7 == OR_RR_TOP7) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_OR_RR;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.rs_idx          = rs_idx_from_instr;
      decoded.alu_op          = ALU_OP_OR;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    if (top7 == XOR_RR_TOP7) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_XOR_RR;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.rs_idx          = rs_idx_from_instr;
      decoded.alu_op          = ALU_OP_XOR;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end

    // -----------------------------------------------------------------------
    // CMP Rs, Rd  (flags from Rd - Rs; Rd unchanged — first wb_reg_en=0)
    // -----------------------------------------------------------------------
    if (top7 == CMP_RR_TOP7) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_CMP_RR;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.rs_idx          = rs_idx_from_instr;
      decoded.alu_op          = ALU_OP_CMP;        // same arithmetic as SUB
      decoded.wb_reg_en       = 1'b0;              // *** key difference ***
      decoded.wb_flags_en     = 1'b1;
    end

    // -----------------------------------------------------------------------
    // JRcc short (Jump Relative Conditional, 8-bit signed displacement)
    //
    // Encoding: bits[15:12] = 1100, bits[11:8] = cc, bits[7:0] = disp.
    // Low-byte values 0x00 and 0x80 are reserved (long-relative and
    // absolute form markers); only short-form disps land here.
    //
    // Per A0017, only condition codes verified against SPVU001A Table
    // 12-8 are decoded:
    //   cc = 0000 → UC (unconditional)
    //   cc = 0100 → EQ (Z = 1)
    //   cc = 0111 → NE (Z = 0)
    // Other cc values fall through to ILLEGAL until the table is read
    // more carefully — better to trap on an unverified condition than
    // silently mis-branch.
    // -----------------------------------------------------------------------
    if (instr[15:12] == JRCC_TOP4 &&
        instr[7:0] != 8'h00 && instr[7:0] != 8'h80 &&
        (instr[11:8] == CC_UC ||
         instr[11:8] == CC_EQ ||
         instr[11:8] == CC_NE)) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_JRCC_SHORT;
      decoded.branch_cc   = instr[11:8];
      decoded.wb_reg_en   = 1'b0;
      decoded.wb_flags_en = 1'b0;
    end
  end

endmodule : tms34010_decode
