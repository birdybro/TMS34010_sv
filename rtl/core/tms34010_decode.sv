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

  // IL-form immediate family. 11-bit prefix; bottom 5 bits = {R, Rd}.
  // 32-bit immediate follows in two 16-bit words (LO, HI).
  localparam logic [10:0] ADDI_IL_TOP11 = 11'b0000_1011_001;  // ADDI IL
  localparam logic [10:0] CMPI_IL_TOP11 = 11'b0000_1011_011;  // CMPI IL
  localparam logic [10:0] ANDI_IL_TOP11 = 11'b0000_1011_100;  // ANDI IL
  localparam logic [10:0] ORI_IL_TOP11  = 11'b0000_1011_101;  // ORI  IL
  localparam logic [10:0] XORI_IL_TOP11 = 11'b0000_1011_110;  // XORI IL
  localparam logic [10:0] SUBI_IL_TOP11 = 11'b0000_1101_000;  // SUBI IL (different base!)

  // MOVE Rs, Rd (register-to-register, same file). The F bit at position
  // [9] selects the field-size mode (FE0/FE1 in ST). Phase 4 ignores F
  // and treats it as a full 32-bit register copy (A0020).
  localparam logic [5:0] MOVE_RR_TOP6 = 6'b100100;  // 1001 00FS SSSR DDDD
  localparam logic [6:0] ADD_RR_TOP7  = 7'b0100_000;  // chart: 0100 000S SSSR DDDD
  localparam logic [6:0] ADDC_RR_TOP7 = 7'b0100_001;  // chart: 0100 001S SSSR DDDD
  localparam logic [6:0] SUB_RR_TOP7  = 7'b0100_010;  // chart: 0100 010S SSSR DDDD
  localparam logic [6:0] SUBB_RR_TOP7 = 7'b0100_011;  // chart: 0100 011S SSSR DDDD
  localparam logic [6:0] AND_RR_TOP7  = 7'b0101_000;  // chart: 0101 000S SSSR DDDD
  localparam logic [6:0] ANDN_RR_TOP7 = 7'b0101_001;  // chart: 0101 001S SSSR DDDD
  localparam logic [6:0] OR_RR_TOP7   = 7'b0101_010;  // chart: 0101 010S SSSR DDDD
  localparam logic [6:0] XOR_RR_TOP7  = 7'b0101_011;  // chart: 0101 011S SSSR DDDD
  localparam logic [6:0] CMP_RR_TOP7  = 7'b0100_100;  // chart: 0100 100S SSSR DDDD

  // PUSHST — push status register onto stack. Per SPVU001A summary
  // table page A-16: single fixed encoding 0x01E0
  // (`0000 0001 1110 0000`). Sets SP -= 32 then writes ST as a
  // 32-bit word to mem[new_SP]. Status bits unaffected.
  localparam instr_word_t PUSHST_OPCODE = 16'h01E0;
  // POPST — pop status register from stack. Per SPVU001A summary
  // table page A-16: single fixed encoding 0x01C0
  // (`0000 0001 1100 0000`). Reads 32-bit ST from mem[SP], then
  // increments SP by 32. Status bits all written by the loaded value.
  localparam instr_word_t POPST_OPCODE  = 16'h01C0;

  // CALL Rs — Call Subroutine Indirect. Per SPVU001A page 12-47 +
  // summary table line 27018. Encoding `0000 1001 001R DDDD`:
  //   top11 = 11'b00001001_001 = 0x049
  //   bit[4] = R (file of Rs)
  //   bits[3:0] = Rs index
  // Semantics:
  //   SP -= 32
  //   mem[new SP] = PC'   (where PC' = address of next instruction)
  //   PC = Rs              (with bottom 4 bits forced to 0 for word align)
  // Status bits all "Unaffected".
  localparam logic [10:0] CALL_RS_TOP11 = 11'b0000_1001_001;

  // DINT / EINT — single-fixed-encoding interrupt-enable control.
  // Per SPVU001A summary table (page A-14):
  //   DINT = 0x0360  (0000 0011 0110 0000) — clear ST.IE (bit 21)
  //   EINT = 0x0D60  (0000 1101 0110 0000) — set ST.IE
  // Status flag bits (N, C, Z, V) all unaffected. Implemented via
  // a full ST-write that reads current ST, modifies bit 21, writes back.
  localparam instr_word_t DINT_OPCODE = 16'h0360;
  localparam instr_word_t EINT_OPCODE = 16'h0D60;

  // EXGF Rd, F — Exchange Field Definition. Per SPVU001A page 12-77 +
  // summary table line 26954. Encoding `1101 01F1 000R DDDD`:
  //   bits[15:10] = 6'b110101  (= 0x35)
  //   bit[9]      = F  (selector: 0 = FS0/FE0; 1 = FS1/FE1)
  //   bit[8]      = 1  (constant)
  //   bits[7:5]   = 000 (sub-op)
  //   bit[4]      = R  (file)
  //   bits[3:0]   = Rd index
  // The instruction atomically swaps Rd's low 6 bits with the F-selected
  // FE:FS pair (1 + 5 bits) in ST. Rd's upper 26 bits are cleared.
  // All four status bits (N, C, Z, V) "Unaffected" per spec.
  localparam logic [5:0] EXGF_TOP6  = 6'b110101;

  // SETF FS, FE, F — Set Field Parameters. Per SPVU001A page 12-237 +
  // summary table line 26978. Encoding `0000 01F1 01FE FFFF`:
  //   bits[15:10] = 6'b000001  (top6 of the field-size-config family)
  //   bit[9]      = F  (selector: 0 = update FS0/FE0; 1 = update FS1/FE1)
  //   bit[8]      = 1  (constant — distinguishes from JUMP/family at bits[15:8]=0x01)
  //   bits[7:6]   = 2'b01 (SETF sub-op marker; SEXT/ZEXT use 00x here)
  //   bit[5]      = FE (new FE value)
  //   bits[4:0]   = FS (new FS value; 5'b00000 → field-size 32)
  // Status bits all "Unaffected" per spec.
  localparam logic [5:0] SETF_TOP6  = 6'b000001;

  // LMO Rs, Rd (Leftmost-One priority encoder). Per SPVU001A page 12-108
  // + summary table line 26955: encoding `0110 101S SSSR DDDD`
  // (top7 = 7'b0110_101 = 0x35). Rs and Rd same file; result =
  // 31 - bit_pos(leftmost-1 in Rs) in bottom 5 bits; Z = (Rs == 0).
  // N, C, V Unaffected — uses the wb_flag_mask added in Task 0037.
  localparam logic [6:0] LMO_RR_TOP7  = 7'b0110_101;

  // Shift Rs-form family. Per SPVU001A summary table page A-15:
  //   SLA Rs, Rd : 0110 000S SSSR DDDD   (top7 = 7'b0110_000)
  //   SLL Rs, Rd : 0110 001S SSSR DDDD   (top7 = 7'b0110_001)
  //   SRA Rs, Rd : 0110 010S SSSR DDDD   (top7 = 7'b0110_010)
  //   SRL Rs, Rd : 0110 011S SSSR DDDD   (top7 = 7'b0110_011)
  //   RL  Rs, Rd : 0110 100S SSSR DDDD   (top7 = 7'b0110_100)
  //
  // The shift amount comes from Rs[4:0]. Per A0019 (extended for the
  // Rs-form): "the SRA Rs, Rd and SRL Rs, Rd use the 2s complement
  // value of the 5 LSBs in Rs". So the core's shifter-amount mux must
  // negate Rs[4:0] for the right-shift opcodes.
  localparam logic [6:0] SLA_RR_TOP7  = 7'b0110_000;
  localparam logic [6:0] SLL_RR_TOP7  = 7'b0110_001;
  localparam logic [6:0] SRA_RR_TOP7  = 7'b0110_010;
  localparam logic [6:0] SRL_RR_TOP7  = 7'b0110_011;
  localparam logic [6:0] RL_RR_TOP7   = 7'b0110_100;

  // JRcc short form: chart row "1100 code xxxx xxxx" with any cc.
  // bits[15:12] = 4'b1100; bits[11:8] = cc (4 bits); bits[7:0] = signed
  // 8-bit displacement. The two low-byte values 0x00 and 0x80 are reserved
  // (long-relative and absolute-form markers respectively).
  localparam logic [3:0] JRCC_TOP4 = 4'b1100;

  // NOP: single full encoding, no operand fields. Per SPVU001A page
  // 12-170 instruction-summary table: NOP = 0000 0011 0000 0000 = 0x0300
  // (A0021). Distinct from the unary family at 0000 0011 1xxx xxxx
  // (top9 = 9'b000000111); NOP's top9 = 9'b000000110, so no collision.
  localparam instr_word_t NOP_OPCODE = 16'h0300;

  // JUMP Rs (register-indirect jump). Per SPVU001A page 12-98 +
  // summary table line 13852: encoding `0000 0001 011R DDDD` —
  // top11 = 11'b00000001_011. Semantics: Rs → PC, with the bottom
  // 4 bits of PC forced to 0 (word alignment).
  localparam logic [10:0] JUMP_RS_TOP11 = 11'b0000_0001_011;

  // DSJ family: two-word instructions with a 16-bit signed
  // displacement following the opcode word. Per SPVU001A pages
  // 12-70..12-73 + summary table lines 27021-27023:
  //   DSJ   Rd, Address : 0000 1101 100R DDDD + 16-bit offset
  //   DSJEQ Rd, Address : 0000 1101 101R DDDD + 16-bit offset
  //   DSJNE Rd, Address : 0000 1101 110R DDDD + 16-bit offset
  // All three: status bits unaffected. Rd is decremented (when the
  // pre-condition holds), and the branch is taken iff the
  // post-decrement Rd is nonzero. Target math: PC' + offset*16,
  // where PC' is the address of the instruction following the
  // two-word DSJ — i.e., pc_value at CORE_WRITEBACK after both
  // FETCH/IMM_LO advances.
  localparam logic [10:0] DSJ_TOP11   = 11'b0000_1101_100;
  localparam logic [10:0] DSJEQ_TOP11 = 11'b0000_1101_101;
  localparam logic [10:0] DSJNE_TOP11 = 11'b0000_1101_110;

  // Status-register manipulation: single-fixed-encoding opcodes
  // CLRC / SETC (clear/set carry) and the two-register GETST / PUTST.
  // Per SPVU001A summary table (page A-14):
  //   CLRC  = 16'h0320  ("0000 0011 0010 0000")
  //   SETC  = 16'h0DE0  ("0000 1101 1110 0000")
  //   GETST Rd : top11 = 11'b00000001_100 = 0x00C  ⇒ base 0x0180
  //   PUTST Rs : top11 = 11'b00000001_101 = 0x00D  ⇒ base 0x01A0
  localparam instr_word_t CLRC_OPCODE   = 16'h0320;
  localparam instr_word_t SETC_OPCODE   = 16'h0DE0;
  localparam logic [10:0] GETST_TOP11   = 11'b0000_0001_100;
  localparam logic [10:0] PUTST_TOP11   = 11'b0000_0001_101;

  // GETPC, EXGPC, REV — small PC/revision register-context ops.
  // Per SPVU001A summary table page A-16:
  //   GETPC Rd  : 0000 0001 010R DDDD  (top11 = 11'b00000001_010 = 0x00A)
  //   EXGPC Rd  : 0000 0001 001R DDDD  (top11 = 11'b00000001_001 = 0x009)
  //   REV   Rd  : 0000 0000 001R DDDD  (top11 = 11'b00000000_001 = 0x001)
  // REV value: per spec page 12-233, the chart bits are largely
  // "undefined" but the worked example shows `REV A1 → 0x00000008`
  // (see A0025). We emit 32'h0000_0008 as the constant.
  localparam logic [10:0] GETPC_TOP11   = 11'b0000_0001_010;
  localparam logic [10:0] EXGPC_TOP11   = 11'b0000_0001_001;
  localparam logic [10:0] REV_TOP11     = 11'b0000_0000_001;

  // BTST K, Rd and BTST Rs, Rd (Test Register Bit). Per SPVU001A
  // pages 12-46/12-47 + summary table lines 26942/26943:
  //   BTST K, Rd  : 0001 11KK KKKR DDDD   (top6 = 6'b000111 = 0x07)
  //   BTST Rs, Rd : 0100 101S SSSR DDDD   (top7 = 7'b0100_101)
  // Both forms test a single bit of Rd (selected by K or by Rs[4:0])
  // and set Z = !bit; N, C, V are Unaffected per spec — the wb_flag_mask
  // blocks updates to those three flags.
  localparam logic [5:0] BTST_K_TOP6   = 6'b000111;
  localparam logic [6:0] BTST_RR_TOP7  = 7'b0100_101;

  // DSJS Rd, Address (Decrement-and-Skip-Jump Short — single-word).
  // Per SPVU001A page 12-74 + summary table line 13844:
  //   `0011 1Dxx xxxR DDDD` — top5 = 5'b00111.
  // Bit[10] = D (direction: 0=forward, 1=backward).
  // Bits[9:5] = 5-bit unsigned offset (words from PC').
  // Bit[4] = file (R). Bits[3:0] = Rd index.
  localparam logic [4:0]  DSJS_TOP5  = 5'b0011_1;

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
    // Default flag-update mask = all-ones. Instructions that need
    // selective updates (BTST → Z only; ABS → all but C) override
    // this in their arms below.
    decoded.wb_flag_mask    = '{n: 1'b1, c: 1'b1, z: 1'b1, v: 1'b1};
    decoded.needs_memory_op = 1'b0;

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
    // IL-form immediate family (32-bit immediate)
    //
    //   ADDI IL  =  0000 1011 001R DDDD + 32-bit imm
    //   SUBI IL  =  0000 1101 000R DDDD + 32-bit imm   (different base prefix!)
    //   CMPI IL  =  0000 1011 011R DDDD + 32-bit imm   (wb_reg_en = 0)
    //   ANDI IL  =  0000 1011 100R DDDD + 32-bit imm
    //   ORI  IL  =  0000 1011 101R DDDD + 32-bit imm
    //   XORI IL  =  0000 1011 110R DDDD + 32-bit imm
    //
    // All reuse MOVI IL's CORE_FETCH_IMM_LO/HI path (needs_imm32=1,
    // imm_sign_extend=0). 32-bit immediate is already full-width.
    // -----------------------------------------------------------------------
    if (top11 == ADDI_IL_TOP11) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_ADDI_IL;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.needs_imm32 = 1'b1;
      decoded.alu_op      = ALU_OP_ADD;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top11 == SUBI_IL_TOP11) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_SUBI_IL;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.needs_imm32 = 1'b1;
      decoded.alu_op      = ALU_OP_SUB;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top11 == CMPI_IL_TOP11) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_CMPI_IL;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.needs_imm32 = 1'b1;
      decoded.alu_op      = ALU_OP_CMP;
      decoded.wb_reg_en   = 1'b0;
      decoded.wb_flags_en = 1'b1;
    end
    if (top11 == ANDI_IL_TOP11) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_ANDI_IL;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.needs_imm32 = 1'b1;
      decoded.alu_op      = ALU_OP_AND;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top11 == ORI_IL_TOP11) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_ORI_IL;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.needs_imm32 = 1'b1;
      decoded.alu_op      = ALU_OP_OR;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top11 == XORI_IL_TOP11) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_XORI_IL;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.needs_imm32 = 1'b1;
      decoded.alu_op      = ALU_OP_XOR;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end

    // -----------------------------------------------------------------------
    // MOVE Rs, Rd  (register-to-register, same file)
    //
    // Encoding: `1001 00FS SSSR DDDD`. The F bit (position 9) selects
    // the field-size mode (FE0/FE1 in ST). Phase 4 ignores F and treats
    // this as a 32-bit register copy (per A0020); revisit when field-
    // size semantics land in Phase 5.
    //
    // Flag effects: N and Z from the source value (per A0009 default
    // for PASS_A operations). C and V cleared.
    // -----------------------------------------------------------------------
    if (top6 == MOVE_RR_TOP6) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_MOVE_RR;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.rs_idx      = rs_idx_from_instr;
      decoded.alu_op      = ALU_OP_PASS_A;        // alu_a = rf_rs1_data (= Rs)
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
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
        2'b00: begin   // ABS: spec says C is "Unaffected" — mask blocks C.
          decoded.illegal         = 1'b0;
          decoded.iclass          = INSTR_ABS;
          decoded.rd_file         = reg_file_from_instr;
          decoded.rd_idx          = reg_idx_from_instr;
          decoded.alu_op          = ALU_OP_ABS;
          decoded.wb_reg_en       = 1'b1;
          decoded.wb_flags_en     = 1'b1;
          decoded.wb_flag_mask    = '{n: 1'b1, c: 1'b0, z: 1'b1, v: 1'b1};
        end
        2'b01: begin   // NEG
          decoded.illegal         = 1'b0;
          decoded.iclass          = INSTR_NEG;
          decoded.rd_file         = reg_file_from_instr;
          decoded.rd_idx          = reg_idx_from_instr;
          decoded.alu_op          = ALU_OP_NEG;
          decoded.wb_reg_en       = 1'b1;
          decoded.wb_flags_en     = 1'b1;
        end
        2'b10: begin   // NEGB  (Rd ← 0 - Rd - C; uses SUBB with a=0)
          decoded.illegal         = 1'b0;
          decoded.iclass          = INSTR_NEGB;
          decoded.rd_file         = reg_file_from_instr;
          decoded.rd_idx          = reg_idx_from_instr;
          decoded.alu_op          = ALU_OP_SUBB;
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
      endcase
    end

    // -----------------------------------------------------------------------
    // Shift Rs-form family (SLA / SLL / SRA / SRL / RL Rs, Rd)
    //
    // Shift amount comes from rf_rs1_data[4:0]; the core's
    // shifter-amount mux applies the 2's-complement negation for
    // SRA/SRL per A0019 (extended).
    // -----------------------------------------------------------------------
    if (top7 == SLA_RR_TOP7) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_SLA_RR;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.rs_idx      = rs_idx_from_instr;
      decoded.shift_op    = SHIFT_OP_SLA;
      decoded.use_shifter = 1'b1;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top7 == SLL_RR_TOP7) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_SLL_RR;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.rs_idx      = rs_idx_from_instr;
      decoded.shift_op    = SHIFT_OP_SLL;
      decoded.use_shifter = 1'b1;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top7 == SRA_RR_TOP7) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_SRA_RR;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.rs_idx      = rs_idx_from_instr;
      decoded.shift_op    = SHIFT_OP_SRA;
      decoded.use_shifter = 1'b1;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top7 == SRL_RR_TOP7) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_SRL_RR;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.rs_idx      = rs_idx_from_instr;
      decoded.shift_op    = SHIFT_OP_SRL;
      decoded.use_shifter = 1'b1;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end
    if (top7 == RL_RR_TOP7) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_RL_RR;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.rs_idx      = rs_idx_from_instr;
      decoded.shift_op    = SHIFT_OP_RL;
      decoded.use_shifter = 1'b1;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b1;
    end

    // -----------------------------------------------------------------------
    // LMO Rs, Rd  (Leftmost-One priority encoder)
    //
    // Rd <- 31 - bit_pos(leftmost-1 in Rs)  (5 bits; upper 27 bits = 0)
    //   if Rs == 0: Rd <- 0; Z <- 1
    //   else:        Z <- 0
    // N, C, V "Unaffected" per SPVU001A page 12-108 — wb_flag_mask
    // gates them out.
    // -----------------------------------------------------------------------
    if (top7 == LMO_RR_TOP7) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_LMO_RR;
      decoded.rd_file      = reg_file_from_instr;
      decoded.rd_idx       = reg_idx_from_instr;
      decoded.rs_idx       = rs_idx_from_instr;
      decoded.wb_reg_en    = 1'b1;
      decoded.wb_flags_en  = 1'b1;
      decoded.wb_flag_mask = '{n: 1'b0, c: 1'b0, z: 1'b1, v: 1'b0};
    end

    // -----------------------------------------------------------------------
    // SETF FS, FE, F : update the field-size pair selected by F bit
    // (instr[9]).  Status bits unaffected. The core constructs the new
    // ST value by reading st_value, modifying the F-selected FS/FE
    // bits, and writing back via st_write_en. Operand extraction
    // happens in the core directly from instr_word_q (F, FE, FS).
    // -----------------------------------------------------------------------
    if (instr[15:10] == SETF_TOP6 && instr[8] && (instr[7:6] == 2'b01)) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_SETF;
      decoded.wb_reg_en    = 1'b0;
      decoded.wb_flags_en  = 1'b0;
    end

    // -----------------------------------------------------------------------
    // SEXT Rd, F : sign-extend the low FS<F> bits of Rd to 32 bits.
    //   Encoding: bits[15:10]=6'b000001, bit[9]=F, bit[8]=1,
    //             bits[7:5]=3'b000, bit[4]=R, bits[3:0]=Rd.
    //   Flags: N from result, Z from result; C and V "Unaffected".
    //
    // ZEXT Rd, F : zero-extend the low FS<F> bits of Rd to 32 bits.
    //   Same encoding shape but bits[7:5]=3'b001.
    //   Flags: Z only; N, C, V "Unaffected".
    //
    // F is read directly from instr_word_q[9] in the core; the SEXT/
    // ZEXT datapath there reads the F-selected FS field from st_value
    // and constructs the appropriate mask + extension.
    // -----------------------------------------------------------------------
    if (instr[15:10] == SETF_TOP6 && instr[8] && (instr[7:5] == 3'b000)) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_SEXT;
      decoded.rd_file      = reg_file_from_instr;
      decoded.rd_idx       = reg_idx_from_instr;
      decoded.wb_reg_en    = 1'b1;
      decoded.wb_flags_en  = 1'b1;
      decoded.wb_flag_mask = '{n: 1'b1, c: 1'b0, z: 1'b1, v: 1'b0};
    end
    if (instr[15:10] == SETF_TOP6 && instr[8] && (instr[7:5] == 3'b001)) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_ZEXT;
      decoded.rd_file      = reg_file_from_instr;
      decoded.rd_idx       = reg_idx_from_instr;
      decoded.wb_reg_en    = 1'b1;
      decoded.wb_flags_en  = 1'b1;
      decoded.wb_flag_mask = '{n: 1'b0, c: 1'b0, z: 1'b1, v: 1'b0};
    end

    // -----------------------------------------------------------------------
    // EXGF Rd, F : atomic swap Rd[5:0] ↔ FE<F>:FS<F> in ST. Rd's
    // upper 26 bits are cleared. Status unaffected.
    //
    // The core handles both halves of the swap in one CORE_WRITEBACK
    // cycle: rf_wr_data delivers the new Rd (= {26'b0, FE_old, FS_old}),
    // and st_write_en+st_write_data deliver the new ST (= current ST
    // with the F-selected slot replaced by Rd_old[5:0]).
    // -----------------------------------------------------------------------
    if (instr[15:10] == EXGF_TOP6 && instr[8] && (instr[7:5] == 3'b000)) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_EXGF;
      decoded.rd_file      = reg_file_from_instr;
      decoded.rd_idx       = reg_idx_from_instr;
      decoded.wb_reg_en    = 1'b1;
      decoded.wb_flags_en  = 1'b0;
    end

    // -----------------------------------------------------------------------
    // DINT : clear ST.IE (disable interrupts). Single fixed encoding 0x0360.
    // EINT : set   ST.IE (enable  interrupts). Single fixed encoding 0x0D60.
    // Status bits N, C, Z, V all unaffected. The core constructs the new
    // ST value by reading current st_value, clearing or setting bit 21,
    // and using the existing full-ST-write path.
    // -----------------------------------------------------------------------
    if (instr == DINT_OPCODE) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_DINT;
      decoded.wb_reg_en   = 1'b0;
      decoded.wb_flags_en = 1'b0;
    end
    if (instr == EINT_OPCODE) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_EINT;
      decoded.wb_reg_en   = 1'b0;
      decoded.wb_flags_en = 1'b0;
    end

    // -----------------------------------------------------------------------
    // PUSHST — push ST onto the stack. Per SPVU001A summary table:
    //   SP <- SP - 32; mem[SP] <- ST  (32-bit write).
    // Single fixed encoding 0x01E0. Status bits Unaffected.
    //
    // ALU computes (SP - 32): alu_a = rf_rs1_data (reads A15 = SP via
    // the regfile's SP-alias); alu_b = 32 via a new core-side mux
    // entry; alu_op = SUB. Then the core fires a 32-bit memory write
    // to alu_result with mem_wdata = st_value; finally WRITEBACK
    // updates SP (rd_idx=15) with alu_result.
    // -----------------------------------------------------------------------
    if (instr == PUSHST_OPCODE) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_PUSHST;
      decoded.rd_file         = REG_FILE_A;
      decoded.rd_idx          = REG_SP_IDX;     // write back to SP (= A15)
      decoded.rs_idx          = REG_SP_IDX;     // read SP via rs1 port
      decoded.alu_op          = ALU_OP_SUB;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b0;
      decoded.needs_memory_op = 1'b1;
    end

    // -----------------------------------------------------------------------
    // POPST — pop ST from stack. Per SPVU001A summary table:
    //   ST <- mem[SP]    (32-bit read)
    //   SP <- SP + 32
    // Single fixed encoding 0x01C0. All status bits are written by
    // the popped value (since the read covers all 32 bits of ST).
    //
    // ALU computes (SP + 32): alu_a = rf_rs1_data (= SP), alu_b = 32
    // via the same constant-32 mux entry PUSHST uses, alu_op = ADD.
    // The mem read uses the OLD SP (= rf_rs1_data) — not alu_result —
    // because we read BEFORE the increment. WRITEBACK then writes
    // the new SP via the regfile and the new ST via st_write_en
    // (st_write_data = mem_rdata).
    // -----------------------------------------------------------------------
    if (instr == POPST_OPCODE) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_POPST;
      decoded.rd_file         = REG_FILE_A;
      decoded.rd_idx          = REG_SP_IDX;
      decoded.rs_idx          = REG_SP_IDX;
      decoded.alu_op          = ALU_OP_ADD;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b0;          // ST update via st_write_en, not flag mask
      decoded.needs_memory_op = 1'b1;
    end

    // -----------------------------------------------------------------------
    // CALL Rs — Call Subroutine Indirect.
    //   SP -= 32;  mem[SP] = PC';  PC = Rs  (with bottom 4 bits cleared)
    //
    // Setup: rs2 reads SP (rd_idx=15) so the ALU's swap-group can put
    // it on alu_a; rs1 reads Rs (rs_idx from instr[3:0]) so the PC-load
    // mux can read it via rf_rs1_data. ALU computes alu_a - alu_b =
    // SP - 32 via the constant-32 mux entry. The CORE_MEMORY arm
    // writes pc_value (= PC' at that point in the FSM) to mem[alu_result].
    // CORE_WRITEBACK then updates SP (rf_wr_en) and loads PC (pc_load_en).
    // Status bits all Unaffected.
    // -----------------------------------------------------------------------
    if (top11 == CALL_RS_TOP11) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_CALL_RS;
      decoded.rd_file         = reg_file_from_instr;  // = R bit (file of Rs)
      decoded.rd_idx          = REG_SP_IDX;            // write back to SP
      decoded.rs_idx          = reg_idx_from_instr;    // Rs read via rs1 port
      decoded.alu_op          = ALU_OP_SUB;
      decoded.wb_reg_en       = 1'b1;
      decoded.wb_flags_en     = 1'b0;
      decoded.needs_memory_op = 1'b1;
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
    // ADDC Rs, Rd  (Rs + Rd + C → Rd; carry-in from ST.C)
    //
    // Spec source: SPVU001A page 12-37 (per-instruction page) and the
    // instruction-summary table — encoding `0100 001S SSSR DDDD`. Used
    // for extended-precision arithmetic chained with ADD/ADDI/ADDK.
    //
    // ADDC is commutative on its register operands so the default
    // operand routing (alu_a=Rs, alu_b=Rd) needs no swap. The ALU
    // already wires alu_cin from st_c, so this just selects ALU_OP_ADDC.
    // -----------------------------------------------------------------------
    if (top7 == ADDC_RR_TOP7) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_ADDC_RR;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.rs_idx          = rs_idx_from_instr;
      decoded.alu_op          = ALU_OP_ADDC;
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
    // SUBB Rs, Rd  (Rd - Rs - C → Rd; borrow-in from ST.C)
    //
    // Spec source: SPVU001A page 12-248 (per-instruction page) and the
    // instruction-summary table — encoding `0100 011S SSSR DDDD`. Used
    // for extended-precision arithmetic chained with SUB/SUBI/SUBK.
    //
    // Same operand-swap as SUB: alu_a = Rd, alu_b = Rs so the ALU
    // computes a - b - cin = Rd - Rs - C. SUBB just selects ALU_OP_SUBB.
    // SPVU001A page 12-248 provides authoritative test vectors; see
    // tb_addc_subb for the rows used.
    // -----------------------------------------------------------------------
    if (top7 == SUBB_RR_TOP7) begin
      decoded.illegal         = 1'b0;
      decoded.iclass          = INSTR_SUBB_RR;
      decoded.rd_file         = reg_file_from_instr;
      decoded.rd_idx          = reg_idx_from_instr;
      decoded.rs_idx          = rs_idx_from_instr;
      decoded.alu_op          = ALU_OP_SUBB;
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
    // Short form: `1100 cccc dddd dddd` with dddd_dddd != 0x00 and != 0x80.
    // Target = PC_post_fetch + sign_extend(disp8) × 16 (per A0016).
    if (instr[15:12] == JRCC_TOP4 &&
        instr[7:0] != 8'h00 && instr[7:0] != 8'h80 &&
        (instr[11:8] == CC_UC ||
         instr[11:8] == CC_LO ||
         instr[11:8] == CC_LS ||
         instr[11:8] == CC_HI ||
         instr[11:8] == CC_LT ||
         instr[11:8] == CC_LE ||
         instr[11:8] == CC_GT ||
         instr[11:8] == CC_GE ||
         instr[11:8] == CC_EQ ||
         instr[11:8] == CC_NE ||
         instr[11:8] == CC_HS)) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_JRCC_SHORT;
      decoded.branch_cc   = instr[11:8];
      decoded.wb_reg_en   = 1'b0;
      decoded.wb_flags_en = 1'b0;
    end

    // -----------------------------------------------------------------------
    // JRcc long form (16-bit signed displacement)
    //
    // Encoding: `1100 cccc 0000 0000` followed by a 16-bit signed-word
    // displacement in the next instruction word. Per SPVU001A page 12-96:
    // "The assembler calculates the offset as (Address - PC')/16 and
    // inserts the resulting offset into the second instruction word of
    // the opcode. The range for this form of the JRcc instruction is
    // -32,768 to +32,767 words (excluding 0)."
    //
    // Target math (A0016 generalized): branch_target_long =
    // PC_after_both_fetches + sign_extend(disp16) × 16. By the time the
    // FSM is in CORE_WRITEBACK, PC has already been advanced twice
    // (once per FETCH ack), so `pc_value` already equals
    // PC_original + 32 — matching the spec's PC'.
    //
    // The absolute-form marker (disp8 == 0x80) remains deferred; only
    // disp8 == 0x00 unlocks the long form here.
    // -----------------------------------------------------------------------
    if (instr[15:12] == JRCC_TOP4 &&
        instr[7:0] == 8'h00 &&
        (instr[11:8] == CC_UC ||
         instr[11:8] == CC_LO ||
         instr[11:8] == CC_LS ||
         instr[11:8] == CC_HI ||
         instr[11:8] == CC_LT ||
         instr[11:8] == CC_LE ||
         instr[11:8] == CC_GT ||
         instr[11:8] == CC_GE ||
         instr[11:8] == CC_EQ ||
         instr[11:8] == CC_NE ||
         instr[11:8] == CC_HS)) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_JRCC_LONG;
      decoded.branch_cc   = instr[11:8];
      decoded.needs_imm16 = 1'b1;
      decoded.wb_reg_en   = 1'b0;
      decoded.wb_flags_en = 1'b0;
    end

    // -----------------------------------------------------------------------
    // NOP — no operation. Single fixed encoding 0x0300 (A0021). Decoded as
    // valid; both writeback gates stay 0 so the FSM walks the full
    // FETCH→DECODE→EXECUTE→WRITEBACK loop with no datapath effect, leaving
    // PC advance (driven by FETCH ack) as the only architectural change.
    // -----------------------------------------------------------------------
    if (instr == NOP_OPCODE) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_NOP;
      decoded.wb_reg_en   = 1'b0;
      decoded.wb_flags_en = 1'b0;
    end

    // -----------------------------------------------------------------------
    // JUMP Rs (register-indirect jump)
    //
    // Encoding (SPVU001A page 12-98 + summary table):
    //   bits[15:5] = 11'b00000001_011 (= 0x00B)
    //   bit[4]     = R (file: 0 = A, 1 = B)
    //   bits[3:0]  = Rs index
    //
    // Semantics: Rs → PC, with the bottom 4 bits of PC forced to 0.
    // No status-register effect. Single-word instruction (no immediate).
    //
    // We populate the source-register selectors so the regfile's rs1
    // port reads Rs; the core's PC-load mux then masks rf_rs1_data
    // with `~32'hF` to enforce word alignment, and asserts pc_load_en
    // in CORE_WRITEBACK.
    // -----------------------------------------------------------------------
    if (top11 == JUMP_RS_TOP11) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_JUMP_RS;
      decoded.rd_file     = reg_file_from_instr;   // same file bit governs Rs
      decoded.rs_idx      = reg_idx_from_instr;    // Rs index lives in low 4 bits
      decoded.wb_reg_en   = 1'b0;
      decoded.wb_flags_en = 1'b0;
    end

    // -----------------------------------------------------------------------
    // DSJ / DSJEQ / DSJNE Rd, Address  (Decrement Rd and Skip Jump)
    //
    // All three share:
    //   - bits[4]    = R (file)
    //   - bits[3:0]  = Rd index
    //   - 16-bit signed offset in the next instruction word
    //   - alu computes Rd - 1 (alu_a = Rd via the swap group; alu_b = 1
    //     via the K-form arm with decoded.k5 = 5'd1)
    //   - wb_reg_en = 1 (write decremented Rd; gated by core based on
    //     the pre-condition for DSJEQ/DSJNE)
    //   - wb_flags_en = 0 (status bits unaffected per the spec)
    //   - needs_imm16 = 1 (fetch the offset word)
    //
    // The branch decision and the Rd-writeback gating both depend on
    // runtime state (ST.Z and post-decrement Rd nonzero). Those gates
    // live in the core, not the decoder. The decoder just identifies
    // the class.
    // -----------------------------------------------------------------------
    if (top11 == DSJ_TOP11 || top11 == DSJEQ_TOP11 || top11 == DSJNE_TOP11) begin
      decoded.illegal     = 1'b0;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.k5          = 5'd1;          // alu_b = 1 via K-form mux arm
      decoded.alu_op      = ALU_OP_SUB;    // alu computes Rd - 1
      decoded.needs_imm16 = 1'b1;
      decoded.imm_sign_extend = 1'b0;      // offset is consumed directly, not via imm32
      decoded.wb_reg_en   = 1'b1;          // gated further by core (DSJEQ/DSJNE)
      decoded.wb_flags_en = 1'b0;          // spec: N/C/Z/V unaffected
      unique case (top11)
        DSJ_TOP11:   decoded.iclass = INSTR_DSJ;
        DSJEQ_TOP11: decoded.iclass = INSTR_DSJEQ;
        DSJNE_TOP11: decoded.iclass = INSTR_DSJNE;
        default:     decoded.iclass = INSTR_ILLEGAL;
      endcase
    end

    // -----------------------------------------------------------------------
    // JAcc Address (absolute-form conditional jump)
    //
    // Encoding (SPVU001A page 12-91 + summary table):
    //   word 0:  1100 cccc 1000 0000     (low byte = 0x80 unlocks JAcc)
    //   word 1:  16 LSBs of absolute address
    //   word 2:  16 MSBs of absolute address
    //
    // Semantics: if condition true, PC ← address (with bottom 4 bits
    // forced to 0 per spec). N/C/Z/V unaffected by the instruction.
    //
    // Reuses the same 11-cc recognized set as JRcc (A0023). The 32-bit
    // address fetch uses the existing IMM_LO/IMM_HI path via
    // needs_imm32=1, just like MOVI IL — but the core extracts the
    // address from {imm_hi_q, imm_lo_q} for a PC load, not for the
    // register file.
    // -----------------------------------------------------------------------
    if (instr[15:12] == JRCC_TOP4 &&
        instr[7:0] == 8'h80 &&
        (instr[11:8] == CC_UC ||
         instr[11:8] == CC_LO ||
         instr[11:8] == CC_LS ||
         instr[11:8] == CC_HI ||
         instr[11:8] == CC_LT ||
         instr[11:8] == CC_LE ||
         instr[11:8] == CC_GT ||
         instr[11:8] == CC_GE ||
         instr[11:8] == CC_EQ ||
         instr[11:8] == CC_NE ||
         instr[11:8] == CC_HS)) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_JACC;
      decoded.branch_cc   = instr[11:8];
      decoded.needs_imm32 = 1'b1;
      decoded.wb_reg_en   = 1'b0;
      decoded.wb_flags_en = 1'b0;
    end

    // -----------------------------------------------------------------------
    // DSJS Rd, Address (Decrement-and-Skip-Jump Short, single-word)
    //
    // Encoding (SPVU001A page 12-74 + summary table line 13844):
    //   bits[15:11] = 5'b00111
    //   bit[10]     = D (direction; 0 = forward, 1 = backward)
    //   bits[9:5]   = 5-bit unsigned offset (words from PC')
    //   bit[4]      = R (file)
    //   bits[3:0]   = Rd index
    //
    // Semantics: Rd ← Rd - 1; if Rd' != 0, branch (PC' +/- offset*16);
    // else fall through. Status bits N/C/Z/V unaffected.
    //
    // The decoder identifies the class and sets the SAME control as
    // DSJ (alu_op=SUB, k5=1, wb_reg_en=1, wb_flags_en=0). The
    // direction and offset are not captured in the decoded struct;
    // the core extracts them combinationally from instr_word_q[10]
    // and instr_word_q[9:5] for the branch-target computation.
    // -----------------------------------------------------------------------
    if (instr[15:11] == DSJS_TOP5) begin
      decoded.illegal     = 1'b0;
      decoded.iclass      = INSTR_DSJS;
      decoded.rd_file     = reg_file_from_instr;
      decoded.rd_idx      = reg_idx_from_instr;
      decoded.k5          = 5'd1;          // alu_b = 1 via K-form mux arm
      decoded.alu_op      = ALU_OP_SUB;
      decoded.wb_reg_en   = 1'b1;
      decoded.wb_flags_en = 1'b0;          // spec: N/C/Z/V unaffected
    end

    // -----------------------------------------------------------------------
    // BTST K, Rd  (Test Register Bit — Constant)
    //
    // Encoding: bits[15:10] = 6'b000111, bits[9:5] = K (5-bit unsigned
    // bit index), bit[4] = R, bits[3:0] = Rd index. Per SPVU001A
    // page 12-46 + summary table line 26942. Status: Z = !(bit_K_of_Rd);
    // N, C, V unaffected — gated via wb_flag_mask.
    //
    // The bit-mask `1 << K` is computed in the core (alu_b mux) and
    // ANDed with Rd. The Z flag from the AND result is what we want.
    // -----------------------------------------------------------------------
    if (top6 == BTST_K_TOP6) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_BTST_K;
      decoded.rd_file      = reg_file_from_instr;
      decoded.rd_idx       = reg_idx_from_instr;
      decoded.k5           = instr[9:5];   // bit index for the test
      decoded.alu_op       = ALU_OP_AND;
      decoded.wb_reg_en    = 1'b0;          // Rd is NOT written
      decoded.wb_flags_en  = 1'b1;
      decoded.wb_flag_mask = '{n: 1'b0, c: 1'b0, z: 1'b1, v: 1'b0};
    end

    // -----------------------------------------------------------------------
    // CLRC : ST.C ← 0. Single fixed encoding 0x0320. N, Z, V unaffected.
    // Implemented via the new per-flag mask: only C updates, and the
    // C value comes from a custom-flags mux in the core (set to 0).
    // -----------------------------------------------------------------------
    if (instr == CLRC_OPCODE) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_CLRC;
      decoded.wb_reg_en    = 1'b0;
      decoded.wb_flags_en  = 1'b1;
      decoded.wb_flag_mask = '{n: 1'b0, c: 1'b1, z: 1'b0, v: 1'b0};
    end

    // -----------------------------------------------------------------------
    // SETC : ST.C ← 1. Single fixed encoding 0x0DE0. Same mask as CLRC.
    // -----------------------------------------------------------------------
    if (instr == SETC_OPCODE) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_SETC;
      decoded.wb_reg_en    = 1'b0;
      decoded.wb_flags_en  = 1'b1;
      decoded.wb_flag_mask = '{n: 1'b0, c: 1'b1, z: 1'b0, v: 1'b0};
    end

    // -----------------------------------------------------------------------
    // GETST Rd : Rd ← ST. Per the summary table, top11 = 11'b00000001_100.
    // bit[4]=R, bits[3:0]=Rd. Status bits unaffected.
    //
    // The core's regfile-write-data mux gains an INSTR_GETST arm
    // routing `st_value` to `rf_wr_data`.
    // -----------------------------------------------------------------------
    if (top11 == GETST_TOP11) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_GETST;
      decoded.rd_file      = reg_file_from_instr;
      decoded.rd_idx       = reg_idx_from_instr;
      decoded.wb_reg_en    = 1'b1;
      decoded.wb_flags_en  = 1'b0;
    end

    // -----------------------------------------------------------------------
    // PUTST Rs : ST ← Rs (full 32-bit write). top11 = 11'b00000001_101.
    // bit[4]=R, bits[3:0]=Rs (the chart writes DODD but it's the
    // source-register field).
    //
    // We use the existing full ST-write path (st_write_en + st_write_data
    // in the core), driving st_write_data from rf_rs1_data (which is
    // already gated by decoded.rd_file/rs_idx in this kind of arm).
    //
    // Per spec summary table page A-15, PUTST DOES affect N C Z V —
    // because the bits being copied to ST happen to lie at the N/C/Z/V
    // positions. Our full-write path stores all 32 bits, so this is
    // automatically correct.
    // -----------------------------------------------------------------------
    if (top11 == PUTST_TOP11) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_PUTST;
      decoded.rd_file      = reg_file_from_instr;
      decoded.rs_idx       = reg_idx_from_instr;   // Rs index for the rs1 read
      decoded.wb_reg_en    = 1'b0;
      decoded.wb_flags_en  = 1'b0;                  // full ST write covers all bits
    end

    // -----------------------------------------------------------------------
    // GETPC Rd : Rd ← PC. Per SPVU001A summary table A-16.
    // The current PC is bit-addressed; we deliver pc_value (the value
    // observed at CORE_WRITEBACK, which already reflects the opcode
    // fetch's PC advance).
    // -----------------------------------------------------------------------
    if (top11 == GETPC_TOP11) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_GETPC;
      decoded.rd_file      = reg_file_from_instr;
      decoded.rd_idx       = reg_idx_from_instr;
      decoded.wb_reg_en    = 1'b1;
      decoded.wb_flags_en  = 1'b0;
    end

    // -----------------------------------------------------------------------
    // EXGPC Rd : atomic swap PC ↔ Rd. Per the spec, the low 4 bits of
    // the new PC are forced to 0 (word alignment, per A0025).
    //
    // We use the regfile's rs2 port (which reads decoded.rd_idx) to
    // get the OLD Rd value for the PC-load. The regfile write port
    // simultaneously stores pc_value into Rd. Because the regfile is
    // async-read + sync-write, rf_rs2_data sees the OLD value during
    // the same WRITEBACK cycle, so the swap is atomic.
    // -----------------------------------------------------------------------
    if (top11 == EXGPC_TOP11) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_EXGPC;
      decoded.rd_file      = reg_file_from_instr;
      decoded.rd_idx       = reg_idx_from_instr;
      decoded.wb_reg_en    = 1'b1;
      decoded.wb_flags_en  = 1'b0;
    end

    // -----------------------------------------------------------------------
    // REV Rd : Rd ← chip revision-number constant. Per spec example
    // (page 12-233), the value is 32'h0000_0008 (A0025). Status bits
    // unaffected.
    // -----------------------------------------------------------------------
    if (top11 == REV_TOP11) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_REV;
      decoded.rd_file      = reg_file_from_instr;
      decoded.rd_idx       = reg_idx_from_instr;
      decoded.wb_reg_en    = 1'b1;
      decoded.wb_flags_en  = 1'b0;
    end

    // -----------------------------------------------------------------------
    // BTST Rs, Rd  (Test Register Bit — Register)
    //
    // Encoding: bits[15:9] = 7'b0100_101 (top7), bits[8:5] = Rs idx,
    // bit[4] = R, bits[3:0] = Rd idx. Per SPVU001A page 12-47 +
    // summary table line 26943. Bit index is Rs[4:0].
    // Same flag policy as BTST K (Z only).
    // -----------------------------------------------------------------------
    if (top7 == BTST_RR_TOP7) begin
      decoded.illegal      = 1'b0;
      decoded.iclass       = INSTR_BTST_RR;
      decoded.rd_file      = reg_file_from_instr;
      decoded.rd_idx       = reg_idx_from_instr;
      decoded.rs_idx       = rs_idx_from_instr;
      decoded.alu_op       = ALU_OP_AND;
      decoded.wb_reg_en    = 1'b0;
      decoded.wb_flags_en  = 1'b1;
      decoded.wb_flag_mask = '{n: 1'b0, c: 1'b0, z: 1'b1, v: 1'b0};
    end
  end

endmodule : tms34010_decode
