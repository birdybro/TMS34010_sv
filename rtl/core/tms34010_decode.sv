// -----------------------------------------------------------------------------
// tms34010_decode.sv
//
// Combinational instruction decoder.
//
// Currently recognized:
//   MOVI IW K, Rd  — encoding 0x09C0 | (R<<4) | N
//                    (R = file bit, N = 4-bit register index)
//                    Operation: sign_extend(K, 32) → Rd
//                    Next 16-bit word holds the immediate K.
//                    Flag effects: N and Z set from result; C, V cleared.
//                    (Flag policy is per A0009/A0011 until SPVU001A Appendix A
//                    is read in detail.)
//
// Reserved encoding (decoded but routed to ILLEGAL until Task 0013 lands):
//   MOVI IL K, Rd  — encoding 0x09E0 | (R<<4) | N. The 32-bit immediate
//                    follows in two more 16-bit words (LO first, then HI).
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
// Encoding layout (MOVI IW):
//   bits[15:6] = 10'b00_0010_0111   (= 0x027)
//   bit[5]     = 0    (IW form; 1 = IL form)
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

  // Fixed-width view of the top 10 bits of the encoding.
  logic [9:0] top10;
  assign top10 = instr[INSTR_WORD_WIDTH-1:6];

  // MOVI top-10 opcode prefix.
  localparam logic [9:0] MOVI_TOP10 = 10'b00_0010_0111;

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
    decoded.needs_imm16     = 1'b0;
    decoded.needs_imm32     = 1'b0;
    decoded.imm_sign_extend = 1'b0;
    decoded.alu_op          = ALU_OP_PASS_A;
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
    // MOVI IL K, Rd  — decoded but not yet executable (Task 0013).
    // Routed to ILLEGAL so the core's illegal trap path catches it.
    // -----------------------------------------------------------------------
    // (Intentionally left to fall through to the ILLEGAL default for now.)
  end

endmodule : tms34010_decode
