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

  // Opcode prefixes.
  localparam logic [9:0] MOVI_TOP10   = 10'b00_0010_0111;
  localparam logic [5:0] MOVK_TOP6    = 6'b00_0110;
  localparam logic [6:0] ADD_RR_TOP7  = 7'b0100_000;     // 0x40 from SPVU001A A-14

  // Reg-reg ops use bits[8:5] for Rs index.
  reg_idx_t rs_idx_from_instr;
  assign rs_idx_from_instr = instr[8:5];

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
    decoded.k5              = '0;
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
    // ADD Rs, Rd  (reg-reg add; Rs and Rd in the same file)
    // -----------------------------------------------------------------------
    if (top7 == ADD_RR_TOP7) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_ADD_RR;
      decoded.rd_file         = reg_file_from_instr;   // single R bit governs both
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.rs_idx          = rs_idx_from_instr;
      decoded.needs_imm16     = 1'b0;
      decoded.needs_imm32     = 1'b0;
      decoded.imm_sign_extend = 1'b0;
      decoded.alu_op          = ALU_OP_ADD;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b1;
    end
  end

endmodule : tms34010_decode
