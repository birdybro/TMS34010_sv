// -----------------------------------------------------------------------------
// tms34010_core.sv
//
// Top-level TMS34010 core wrapper. Phase 3 — decode skeleton integrated.
//
// What this module IS, today:
//   - A clocked top-level entity with explicit synchronous active-high reset.
//   - A typed-enum core FSM that fully cycles: CORE_RESET → CORE_FETCH →
//     CORE_DECODE → CORE_EXECUTE → CORE_WRITEBACK → CORE_FETCH (no
//     instruction touches memory in Phase 3, so CORE_MEMORY is unused).
//   - Memory IF that drives `mem_addr` from the PC register and asserts a
//     16-bit fetch in CORE_FETCH. On mem_ack the fetched word is latched
//     into `instr_word_q` and the PC advances by INSTR_WORD_BITS.
//   - A tms34010_decode instance evaluates `instr_word_q` combinationally.
//     Phase 3 skeleton: every encoding is flagged ILLEGAL.
//   - Sticky `illegal_opcode_o` observability output.
//   - Register file, ALU, and status register instantiated and connected
//     into the datapath: ALU result → regfile write-data port, ALU flags
//     → status-register flag-update port. All "go" signals (rf_wr_en,
//     st_flag_update_en, st_write_en) are currently tied to 0 — no
//     instruction is yet decoded into a real datapath action. Task 0012
//     replaces these tie-offs with decoded-instruction-driven values for
//     the first real instruction (MOVI).
//
// What this module IS NOT, yet:
//   - No real instruction decoded. EXECUTE / WRITEBACK are pass-through
//     states; the datapath stays at quiescent values.
//   - No branches / jumps yet, so the PC `load_en` port is tied 0.
//   - The PC starts at `RESET_PC` from the package, currently a placeholder
//     '0 — see docs/assumptions.md A0008 for the architectural reset-vector
//     fetch sequence that is Phase 8 work.
//
// Synthesis notes:
//   - One sequential `always_ff` for the state register.
//   - One `always_comb` for next-state and combinational outputs, with safe
//     defaults at the top to prevent latch inference.
//   - No `/`, `%`, runtime loops, or `initial` blocks.
//   - Reset is synchronous active-high (project convention A0003).
//
// Spec source: third_party/TMS34010_Info/docs/ti-official/
//              1988_TI_TMS34010_Users_Guide.pdf
// -----------------------------------------------------------------------------

module tms34010_core
  import tms34010_pkg::*;
(
  input  logic                                clk,
  input  logic                                rst,

  // Memory request/valid interface (stub in Phase 0 skeleton).
  output logic                                mem_req,
  output logic                                mem_we,
  output logic [ADDR_WIDTH-1:0]               mem_addr,
  output logic [FIELD_SIZE_WIDTH-1:0]         mem_size,
  output logic [DATA_WIDTH-1:0]               mem_wdata,
  input  logic [DATA_WIDTH-1:0]               mem_rdata,
  input  logic                                mem_ack,

  // Observability for testbenches (Phase 0..3 — may move to an
  // sva/observability bundle later).
  output core_state_t                         state_o,
  output logic [ADDR_WIDTH-1:0]               pc_o,
  output instr_word_t                         instr_word_o,
  output logic                                illegal_opcode_o
);

  // ---------------------------------------------------------------------------
  // Program counter
  // ---------------------------------------------------------------------------
  logic                  pc_advance_en;
  logic                  pc_load_en;
  logic [ADDR_WIDTH-1:0] pc_load_value;
  logic [ADDR_WIDTH-1:0] pc_value;

  tms34010_pc u_pc (
    .clk            (clk),
    .rst            (rst),
    .load_en        (pc_load_en),
    .load_value     (pc_load_value),
    .advance_en     (pc_advance_en),
    .advance_amount (PC_ADVANCE_WIDTH'(INSTR_WORD_BITS)),
    .pc_o           (pc_value)
  );

  // ---------------------------------------------------------------------------
  // State register
  // ---------------------------------------------------------------------------
  core_state_t state_q;
  core_state_t state_d;

  always_ff @(posedge clk) begin
    if (rst) begin
      state_q <= CORE_RESET;
    end else begin
      state_q <= state_d;
    end
  end

  // ---------------------------------------------------------------------------
  // Instruction word latch + decoder
  //
  // instr_word_q is latched the cycle the memory acks an instruction
  // fetch. The decoder runs combinationally; consumers see the decoded
  // result from CORE_DECODE onward.
  // ---------------------------------------------------------------------------
  instr_word_t    instr_word_q;
  decoded_instr_t decoded;

  always_ff @(posedge clk) begin
    if (rst) begin
      instr_word_q <= '0;
    end else if (state_q == CORE_FETCH && mem_ack) begin
      instr_word_q <= mem_rdata[INSTR_WORD_WIDTH-1:0];
    end
  end

  tms34010_decode u_decode (
    .instr  (instr_word_q),
    .decoded(decoded)
  );

  // Sticky illegal-opcode latch. Set on the cycle we are in CORE_DECODE
  // with an illegal `decoded`. Cleared only by reset.
  logic illegal_q;
  always_ff @(posedge clk) begin
    if (rst) begin
      illegal_q <= 1'b0;
    end else if (state_q == CORE_DECODE && decoded.illegal) begin
      illegal_q <= 1'b1;
    end
  end

  // ---------------------------------------------------------------------------
  // Branch-target computation (PC-relative, short form)
  //
  // For JRUC short and (future) JRcc short: the displacement in
  // instr_word_q[7:0] is a signed 8-bit count of 16-bit words. The new PC
  // is `current_pc + disp * 16` (in bits). `current_pc` is the value AFTER
  // the opcode fetch already advanced the PC by 16, which matches what
  // hand-decoding `JRGT L5 = 0xC70B` at PC=0x3B0 → target 0x470 produces
  // (target = (0x3B0+16) + 11*16 = 0x470).
  //
  // The full target is computed combinationally and only consumed when
  // the FSM is in CORE_WRITEBACK with a taken-branch decoded class.
  // ---------------------------------------------------------------------------
  logic [ADDR_WIDTH-1:0] branch_target_short;
  logic signed [INSTR_WORD_WIDTH-1:0] disp_signed_12;
  // {disp8, 4'h0} = disp * 16 expressed in 12 bits, sign-bit at [11].
  assign disp_signed_12   = $signed({instr_word_q[7:0], 4'h0});
  assign branch_target_short = pc_value + ADDR_WIDTH'(disp_signed_12);

  // Immediate latches — declared up here (before their first use in
  // the branch_target_long / branch_target_jacc combinational
  // computations below) because Questa is strict about forward
  // references in `assign` statements, even though Verilator hoists
  // them. The matching `always_ff` that actually latches imm_lo_q /
  // imm_hi_q on memory acks lives further down (search for
  // CORE_FETCH_IMM_LO / CORE_FETCH_IMM_HI).
  instr_word_t imm_lo_q;
  instr_word_t imm_hi_q;

  // Long-form JRcc target: PC_after_both_fetches + sign_extend(disp16) × 16.
  // By the time the FSM hits CORE_WRITEBACK, pc_value already equals
  // (PC_original + 32 bits) — the opcode FETCH and the IMM_LO FETCH each
  // advanced the PC by 16. `imm_lo_q` holds the 16-bit displacement word.
  // {disp16, 4'h0} is a 20-bit value; sign bit at [19] equals imm_lo_q[15].
  logic [ADDR_WIDTH-1:0]   branch_target_long;
  logic signed [19:0]      disp_signed_20;
  assign disp_signed_20   = $signed({imm_lo_q, 4'h0});
  assign branch_target_long = pc_value + ADDR_WIDTH'(disp_signed_20);

  // JAcc absolute target: PC ← address with the bottom 4 bits forced to 0
  // (spec page 12-91 explicitly: "lower four bits of the program counter
  // are set to 0"). Address is assembled from the two 16-bit imm words
  // already fetched via needs_imm32, same as MOVI IL.
  logic [ADDR_WIDTH-1:0] branch_target_jacc;
  assign branch_target_jacc = {imm_hi_q, imm_lo_q[INSTR_WORD_WIDTH-1:4], 4'h0};

  // DSJS short-form target: PC' ± offset×16 bits.
  // pc_value at CORE_WRITEBACK already equals PC' (= PC_original + 16
  // after the single-word opcode fetch). instr_word_q[10] is the
  // direction bit; instr_word_q[9:5] is the 5-bit unsigned offset.
  logic [ADDR_WIDTH-1:0] branch_target_dsjs;
  logic signed [9:0]     dsjs_disp_bits;
  // Build positive bit-offset = {1'b0, offset5, 4'h0} (signed 10-bit
  // value in [0, +496]), then negate when D=1.
  assign dsjs_disp_bits = instr_word_q[10]
                        ? -10'($signed({1'b0, instr_word_q[9:5], 4'h0}))
                        :  10'($signed({1'b0, instr_word_q[9:5], 4'h0}));
  assign branch_target_dsjs = pc_value + ADDR_WIDTH'(dsjs_disp_bits);

  // ---------------------------------------------------------------------------
  // Immediate latch
  //
  // Long-immediate-form instructions (MOVI IW/IL, ADDI IW/IL, ...) fetch
  // one or two additional 16-bit words after the opcode word. The
  // imm_lo_q / imm_hi_q registers are DECLARED earlier (just before
  // the branch_target_long block) so the assigns above can reference
  // them under strict simulators like Questa; the always_ff that
  // updates them sits here.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst) begin
      imm_lo_q <= '0;
      imm_hi_q <= '0;
    end else begin
      if (state_q == CORE_FETCH_IMM_LO && mem_ack) begin
        imm_lo_q <= mem_rdata[INSTR_WORD_WIDTH-1:0];
      end
      if (state_q == CORE_FETCH_IMM_HI && mem_ack) begin
        imm_hi_q <= mem_rdata[INSTR_WORD_WIDTH-1:0];
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Datapath modules
  //
  // Control signals are now driven by `decoded.*` plus the FSM state:
  // writes only happen in CORE_WRITEBACK, and only for instructions whose
  // decoded record requests a writeback (decoded.wb_reg_en /
  // decoded.wb_flags_en).
  // ---------------------------------------------------------------------------

  // Register-file ports.
  reg_file_t              rf_rs1_file;
  reg_idx_t               rf_rs1_idx;
  logic [DATA_WIDTH-1:0]  rf_rs1_data;
  reg_file_t              rf_rs2_file;
  reg_idx_t               rf_rs2_idx;
  logic [DATA_WIDTH-1:0]  rf_rs2_data;
  logic                   rf_wr_en;
  reg_file_t              rf_wr_file;
  reg_idx_t               rf_wr_idx;
  logic [DATA_WIDTH-1:0]  rf_wr_data;
  logic [DATA_WIDTH-1:0]  rf_sp;

  // ALU ports.
  alu_op_t                alu_op;
  logic [DATA_WIDTH-1:0]  alu_a;
  logic [DATA_WIDTH-1:0]  alu_b;
  logic                   alu_cin;
  logic [DATA_WIDTH-1:0]  alu_result;
  alu_flags_t             alu_flags;

  // Status-register ports.
  logic                   st_flag_update_en;
  logic                   st_write_en;
  logic [DATA_WIDTH-1:0]  st_write_data;
  logic [DATA_WIDTH-1:0]  st_value;
  logic                   st_n, st_c, st_z, st_v;

  // Shifter ports.
  logic [DATA_WIDTH-1:0]  shifter_result;
  alu_flags_t             shifter_flags;

  // ---- Operand assembly ----------------------------------------------------
  // Full 32-bit immediate composed from the latched 16-bit pieces. For
  // IW form: sign-extend (or zero-extend) imm_lo_q. For IL form (Task
  // 0013): concatenate {imm_hi_q, imm_lo_q}.
  logic [DATA_WIDTH-1:0] imm32;
  always_comb begin
    if (decoded.needs_imm32) begin
      imm32 = {imm_hi_q, imm_lo_q};
    end else if (decoded.imm_sign_extend) begin
      imm32 = {{(DATA_WIDTH-INSTR_WORD_WIDTH){imm_lo_q[INSTR_WORD_WIDTH-1]}}, imm_lo_q};
    end else begin
      imm32 = {{(DATA_WIDTH-INSTR_WORD_WIDTH){1'b0}}, imm_lo_q};
    end
  end

  // ---- Register-file selectors driven by decode ----------------------------
  // rs1 reads Rs (used as ALU `a` for reg-reg ops). rs2 reads Rd (used as
  // ALU `b` for reg-reg ops where Rd is also a source, e.g. ADD Rs,Rd).
  // For MOVI / MOVK, the rs1/rs2 reads still occur but their values are
  // not routed to alu_a/b (the alu_b mux picks imm32 or zero-extended k5
  // instead).
  //
  // TMS34010 reg-reg encoding constrains Rs and Rd to the same file, so
  // a single `decoded.rd_file` drives both reads.
  assign rf_rs1_file = decoded.rd_file;
  assign rf_rs1_idx  = decoded.rs_idx;
  assign rf_rs2_file = decoded.rd_file;
  assign rf_rs2_idx  = decoded.rd_idx;

  // DSJ-family runtime gate. For DSJEQ/DSJNE, the decrement (and any
  // subsequent jump) happens only if the Z bit pre-condition holds:
  //   - DSJ:   unconditional   → gate = 1
  //   - DSJEQ: gated on Z=1    → gate = st_z
  //   - DSJNE: gated on Z=0    → gate = !st_z
  // For non-DSJ instructions this signal is irrelevant; we default
  // it to 1 so it doesn't interfere with their writebacks.
  logic dsj_precondition;
  always_comb begin
    unique case (decoded.iclass)
      INSTR_DSJ,
      INSTR_DSJS:   dsj_precondition = 1'b1;
      INSTR_DSJEQ:  dsj_precondition = st_z;
      INSTR_DSJNE:  dsj_precondition = !st_z;
      default:      dsj_precondition = 1'b1;
    endcase
  end

  // "Will Rd be zero after the decrement?" — needed for the DSJ
  // branch decision. alu_result at WRITEBACK is the decremented Rd
  // (when iclass is one of the DSJ family).
  logic dsj_rd_nonzero;
  assign dsj_rd_nonzero = (alu_result != '0);

  // Writeback enable is a one-cycle pulse, gated by the FSM state.
  // Writeback data and flag-input come from either the ALU or the
  // shifter depending on `decoded.use_shifter`. For DSJEQ/DSJNE the
  // dsj_precondition further gates the write: if Z doesn't match the
  // pre-condition the spec mandates Rd is left unchanged.
  assign rf_wr_en   = (state_q == CORE_WRITEBACK)
                   && decoded.wb_reg_en
                   && dsj_precondition;
  assign rf_wr_file = decoded.rd_file;
  assign rf_wr_idx  = decoded.rd_idx;
  // SEXT / ZEXT field-extension datapath. Per SPVU001A pages 12-238
  // (SEXT) and 12-256 (ZEXT): take the low `FS` bits of Rd, then
  // either sign-extend (copy the field MSB into bits[31:FS]) or
  // zero-extend (clear bits[31:FS]). FS is read from the F-selected
  // pair in ST (FS0 if instr_word_q[9]=0, FS1 if =1). FS=5'b00000
  // encodes a field-size of 32 per Table 5-3, so the data is the
  // full 32-bit register and no extension is needed.
  logic [4:0]            fs_selected;
  logic [DATA_WIDTH-1:0] field_mask;
  logic                  field_msb;
  logic [DATA_WIDTH-1:0] sext_result;
  logic [DATA_WIDTH-1:0] zext_result;
  assign fs_selected = instr_word_q[9]
                     ? st_value[ST_FS1_HI:ST_FS1_LO]
                     : st_value[ST_FS0_HI:ST_FS0_LO];
  always_comb begin
    if (fs_selected == 5'd0) begin
      // Field-size = 32: identity.
      field_mask  = '1;
      field_msb   = rf_rs2_data[DATA_WIDTH-1];
      sext_result = rf_rs2_data;
      zext_result = rf_rs2_data;
    end else begin
      field_mask  = (32'd1 << fs_selected) - 32'd1;
      field_msb   = rf_rs2_data[fs_selected - 5'd1];
      sext_result = field_msb ? ((rf_rs2_data & field_mask) | ~field_mask)
                              :  (rf_rs2_data & field_mask);
      zext_result = rf_rs2_data & field_mask;
    end
  end

  // LMO (Leftmost-One) datapath. Pure combinational — finds the
  // highest-set bit of rf_rs1_data and computes Rd = 31 - bit_pos
  // (i.e., one's-complement of the bit position in 5 bits). The
  // upper 27 bits of Rd are zero. If rf_rs1_data == 0, Rd = 0 and
  // the Z flag (gated by wb_flag_mask) is set.
  logic [4:0]            lmo_bit_pos;
  logic [DATA_WIDTH-1:0] lmo_result;
  always_comb begin
    // Iterate low-to-high so the LAST overwrite (highest set bit)
    // wins. Synthesizable — no `break`, no run-time loop.
    lmo_bit_pos = 5'd0;
    for (int i = 0; i < DATA_WIDTH; i++) begin
      if (rf_rs1_data[i]) lmo_bit_pos = 5'(i);
    end
    if (rf_rs1_data == '0)
      lmo_result = '0;
    else
      lmo_result = {{(DATA_WIDTH-5){1'b0}}, ~lmo_bit_pos};
  end

  // Regfile write-data mux. Several "Rd ← something" instructions
  // bypass the ALU/shifter and route a different source:
  //   GETST  → ST value
  //   GETPC  → current PC value
  //   EXGPC  → current PC value (the other half of the swap)
  //   REV    → chip-revision constant (A0025)
  //   LMO_RR → priority-encoder result
  // The default routes the shifter or ALU result per decoded.use_shifter.
  always_comb begin
    unique case (decoded.iclass)
      INSTR_GETST:  rf_wr_data = st_value;
      INSTR_GETPC,
      INSTR_EXGPC:  rf_wr_data = pc_value;
      INSTR_REV:    rf_wr_data = 32'h0000_0008;
      INSTR_LMO_RR: rf_wr_data = lmo_result;
      INSTR_SEXT:   rf_wr_data = sext_result;
      INSTR_ZEXT:   rf_wr_data = zext_result;
      default:      rf_wr_data = decoded.use_shifter ? shifter_result : alu_result;
    endcase
  end

  // ALU operand selection.
  //
  // Default routing puts Rs on `alu_a` and Rd on `alu_b`, which works for
  // commutative reg-reg ops (ADD, AND, OR, XOR, ...) and for the move
  // family (`alu_b` is overridden to the immediate / K).
  //
  // For SUB (Rd - Rs → Rd) the order matters: we need `alu_a = Rd` and
  // `alu_b = Rs` because the ALU computes `a - b`. The two muxes below
  // swap routing for `INSTR_SUB_RR`.
  assign alu_op  = decoded.alu_op;
  always_comb begin
    unique case (decoded.iclass)
      INSTR_SUB_RR,
      INSTR_SUBB_RR,
      INSTR_ANDN_RR,
      INSTR_CMP_RR,
      INSTR_ADDK,
      INSTR_SUBK,
      INSTR_NEG,
      INSTR_NOT,
      INSTR_ABS,
      INSTR_ADDI_IW,
      INSTR_SUBI_IW,
      INSTR_CMPI_IW,
      INSTR_ADDI_IL,
      INSTR_SUBI_IL,
      INSTR_CMPI_IL,
      INSTR_ANDI_IL,
      INSTR_ORI_IL,
      INSTR_XORI_IL,
      INSTR_DSJ,
      INSTR_DSJEQ,
      INSTR_DSJNE,
      INSTR_DSJS,
      INSTR_BTST_K,
      INSTR_BTST_RR: alu_a = rf_rs2_data;   // Rd is the operand
      INSTR_NEGB:    alu_a = '0;            // NEGB: 0 - Rd - C via SUBB
      default:       alu_a = rf_rs1_data;   // Rs (or unused for MOVI/MOVK)
    endcase
  end
  always_comb begin
    unique case (decoded.iclass)
      INSTR_MOVI_IW,
      INSTR_MOVI_IL,
      INSTR_ADDI_IW,
      INSTR_SUBI_IW,
      INSTR_CMPI_IW,
      INSTR_ADDI_IL,
      INSTR_SUBI_IL,
      INSTR_CMPI_IL,
      INSTR_ANDI_IL,
      INSTR_ORI_IL,
      INSTR_XORI_IL: alu_b = imm32;
      INSTR_MOVK,
      INSTR_ADDK,
      INSTR_SUBK,
      INSTR_DSJ,
      INSTR_DSJEQ,
      INSTR_DSJNE,
      INSTR_DSJS:    alu_b = {{(DATA_WIDTH-5){1'b0}}, decoded.k5};
      INSTR_BTST_K:  alu_b = 32'd1 << decoded.k5;
      INSTR_BTST_RR: alu_b = 32'd1 << rf_rs1_data[4:0];
      INSTR_SUB_RR,
      INSTR_SUBB_RR,
      INSTR_ANDN_RR,
      INSTR_CMP_RR:  alu_b = rf_rs1_data;   // Rs is the "second" operand
      default:       alu_b = rf_rs2_data;
    endcase
  end
  assign alu_cin = st_c;

  // Status-register inputs. Flag-update is gated by FSM state, like the
  // regfile write. Full ST write port is unused until POPST lands.
  assign st_flag_update_en = (state_q == CORE_WRITEBACK) && decoded.wb_flags_en;
  // ST-write data + enable. Two instructions drive the full ST-write
  // path:
  //   PUTST Rs: ST ← Rs (full copy).
  //   SETF FS, FE, F: read current ST, splice the F-selected FS/FE
  //                   pair with the new values from the instruction
  //                   word, write back.
  //
  // SETF operand extraction (from instr_word_q):
  //   F  = instr_word_q[9]
  //   FE = instr_word_q[5]
  //   FS = instr_word_q[4:0]
  logic [DATA_WIDTH-1:0] setf_new_st;
  always_comb begin
    setf_new_st = st_value;  // start from current
    if (instr_word_q[9]) begin
      // F=1: update FS1 (bits[10:6]) and FE1 (bit[11]).
      setf_new_st[ST_FS1_HI:ST_FS1_LO] = instr_word_q[4:0];
      setf_new_st[ST_FE1_BIT]          = instr_word_q[5];
    end else begin
      // F=0: update FS0 (bits[4:0]) and FE0 (bit[5]).
      setf_new_st[ST_FS0_HI:ST_FS0_LO] = instr_word_q[4:0];
      setf_new_st[ST_FE0_BIT]          = instr_word_q[5];
    end
  end

  assign st_write_en = (state_q == CORE_WRITEBACK)
                    && ((decoded.iclass == INSTR_PUTST) ||
                        (decoded.iclass == INSTR_SETF));
  always_comb begin
    unique case (decoded.iclass)
      INSTR_PUTST: st_write_data = rf_rs1_data;
      INSTR_SETF:  st_write_data = setf_new_st;
      default:     st_write_data = '0;
    endcase
  end

  // ---- Branch-condition evaluator -----------------------------------------
  // Combinational decode of decoded.branch_cc against the current ST
  // flags. Returns 1 if the branch should be taken. Codes not in the
  // verified set (A0017) return 0 (no branch); the decoder is responsible
  // for routing unverified codes to ILLEGAL so this default isn't reached
  // by a recognized JRCC.
  logic branch_taken;
  always_comb begin
    unique case (decoded.branch_cc)
      CC_UC:   branch_taken = 1'b1;
      CC_LO:   branch_taken = st_c;                   // unsigned <
      CC_LS:   branch_taken = st_c | st_z;             // unsigned <=
      CC_HI:   branch_taken = !st_c & !st_z;           // unsigned >
      CC_LT:   branch_taken = st_n ^ st_v;             // signed   <
      CC_LE:   branch_taken = (st_n ^ st_v) | st_z;    // signed   <=
      CC_GT:   branch_taken = !(st_n ^ st_v) & !st_z;  // signed   >
      CC_GE:   branch_taken = !(st_n ^ st_v);          // signed   >=
      CC_EQ:   branch_taken = st_z;                    // =
      CC_NE:   branch_taken = !st_z;                   // !=
      CC_HS:   branch_taken = !st_c;                   // unsigned >=  (== NC)
      default: branch_taken = 1'b0;
    endcase
  end

  // ---- PC-load (branches) -------------------------------------------------
  // Gated by FSM state. For JRcc short, load the relative target in
  // CORE_WRITEBACK only when the condition is met.
  always_comb begin
    pc_load_en    = 1'b0;
    pc_load_value = '0;
    if (state_q == CORE_WRITEBACK) begin
      unique case (decoded.iclass)
        INSTR_JRCC_SHORT: begin
          if (branch_taken) begin
            pc_load_en    = 1'b1;
            pc_load_value = branch_target_short;
          end
        end
        INSTR_JRCC_LONG: begin
          if (branch_taken) begin
            pc_load_en    = 1'b1;
            pc_load_value = branch_target_long;
          end
        end
        INSTR_JUMP_RS: begin
          // Unconditional indirect jump: load PC from Rs (read via rs1
          // port) with the bottom 4 bits forced to 0 to enforce
          // word alignment per SPVU001A page 12-98.
          pc_load_en    = 1'b1;
          pc_load_value = {rf_rs1_data[ADDR_WIDTH-1:4], 4'h0};
        end
        INSTR_EXGPC: begin
          // Atomic swap PC ↔ Rd: PC ← old Rd (with bottom 4 bits forced
          // to 0 per A0025), Rd ← PC (via the rf_wr_data mux above).
          // rf_rs2_data is the async-read value of decoded.rd_idx in
          // the same file as the destination — i.e., the OLD Rd value.
          pc_load_en    = 1'b1;
          pc_load_value = {rf_rs2_data[ADDR_WIDTH-1:4], 4'h0};
        end
        INSTR_DSJ,
        INSTR_DSJEQ,
        INSTR_DSJNE: begin
          // Decrement-and-skip-jump family. Branch taken iff the
          // runtime pre-condition (always for DSJ; Z gate for
          // DSJEQ/DSJNE) holds AND the post-decrement Rd is nonzero.
          // Target shape matches the long-form JRcc:
          //   target = PC' + sign_extend(offset16) * 16
          // where PC' is pc_value at WRITEBACK (already advanced
          // through the opcode + offset-word fetches).
          if (dsj_precondition && dsj_rd_nonzero) begin
            pc_load_en    = 1'b1;
            pc_load_value = branch_target_long;
          end
        end
        INSTR_JACC: begin
          // Absolute conditional jump: PC ← {imm_hi_q, imm_lo_q} with
          // the bottom 4 bits forced to 0 (word alignment per spec
          // page 12-91). Re-uses the JRcc condition evaluator.
          if (branch_taken) begin
            pc_load_en    = 1'b1;
            pc_load_value = branch_target_jacc;
          end
        end
        INSTR_DSJS: begin
          // Short-form decrement-and-skip-jump. Branch taken iff the
          // post-decrement Rd is non-zero (dsj_precondition = 1 for
          // DSJS just like DSJ). Target = PC' ± offset×16 per
          // instr_word_q[10] direction bit.
          if (dsj_rd_nonzero) begin
            pc_load_en    = 1'b1;
            pc_load_value = branch_target_dsjs;
          end
        end
        default: ; // no branch
      endcase
    end
  end

  tms34010_regfile u_regfile (
    .clk      (clk),
    .rst      (rst),
    .rs1_file (rf_rs1_file),
    .rs1_idx  (rf_rs1_idx),
    .rs1_data (rf_rs1_data),
    .rs2_file (rf_rs2_file),
    .rs2_idx  (rf_rs2_idx),
    .rs2_data (rf_rs2_data),
    .wr_en    (rf_wr_en),
    .wr_file  (rf_wr_file),
    .wr_idx   (rf_wr_idx),
    .wr_data  (rf_wr_data),
    .sp_o     (rf_sp)
  );

  tms34010_alu u_alu (
    .op    (alu_op),
    .a     (alu_a),
    .b     (alu_b),
    .cin   (alu_cin),
    .result(alu_result),
    .flags (alu_flags)
  );

  // Shifter datapath. Operand is the Rd register value (via rf_rs2_data,
  // which already reads decoded.rd_idx in the same file as the
  // destination). Shift amount comes from one of two sources:
  //   - K-form shifts (SLA/SLL/SRA/SRL/RL K, Rd):  decoded.k5 (literal K)
  //   - Rs-form left/rotate shifts (SLA/SLL/RL Rs, Rd):  Rs[4:0] directly
  //   - Rs-form right shifts (SRA/SRL Rs, Rd):  2's complement of Rs[4:0]
  //     (per spec page 12-219; "use the 2s complement value of the
  //     5 LSBs in Rs"). The negation is done here in the amount mux.
  logic [SHIFT_AMOUNT_WIDTH-1:0] shifter_amount;
  always_comb begin
    unique case (decoded.iclass)
      INSTR_SLA_RR,
      INSTR_SLL_RR,
      INSTR_RL_RR:  shifter_amount = rf_rs1_data[SHIFT_AMOUNT_WIDTH-1:0];
      INSTR_SRA_RR,
      INSTR_SRL_RR: shifter_amount = (~rf_rs1_data[SHIFT_AMOUNT_WIDTH-1:0])
                                     + {{(SHIFT_AMOUNT_WIDTH-1){1'b0}}, 1'b1};
      default:      shifter_amount = decoded.k5;
    endcase
  end

  tms34010_shifter u_shifter (
    .op    (decoded.shift_op),
    .a     (rf_rs2_data),
    .amount(shifter_amount),
    .result(shifter_result),
    .flags (shifter_flags)
  );

  // Flag-input mux: status register samples either ALU flags or shifter
  // flags depending on the source of the result.
  // Flag-input mux: SET/CLR-C inject a constant C value (paired with
  // the wb_flag_mask = c-only in their decoder arms); other
  // flag-affecting instructions get their flags from the ALU or shifter
  // per `decoded.use_shifter`.
  alu_flags_t  flag_input;
  always_comb begin
    unique case (decoded.iclass)
      INSTR_SETC:   flag_input = '{n: 1'b0, c: 1'b1, z: 1'b0, v: 1'b0};
      INSTR_CLRC:   flag_input = '{n: 1'b0, c: 1'b0, z: 1'b0, v: 1'b0};
      INSTR_LMO_RR: flag_input = '{n: 1'b0, c: 1'b0,
                                    z: (rf_rs1_data == '0), v: 1'b0};
      INSTR_SEXT:   flag_input = '{n: sext_result[DATA_WIDTH-1], c: 1'b0,
                                    z: (sext_result == '0), v: 1'b0};
      INSTR_ZEXT:   flag_input = '{n: 1'b0, c: 1'b0,
                                    z: (zext_result == '0), v: 1'b0};
      default:      flag_input = decoded.use_shifter ? shifter_flags : alu_flags;
    endcase
  end

  tms34010_status_reg u_status_reg (
    .clk             (clk),
    .rst             (rst),
    .flag_update_en  (st_flag_update_en),
    .flags_in        (flag_input),
    .flag_update_mask(decoded.wb_flag_mask),
    .st_write_en     (st_write_en),
    .st_write_data   (st_write_data),
    .st_o            (st_value),
    .n_o             (st_n),
    .c_o             (st_c),
    .z_o             (st_z),
    .v_o             (st_v)
  );

  // Currently-unused datapath observability — keep the lint sweep
  // clean without falsely claiming we consume the value.
  logic [DATA_WIDTH-1:0] unused_rf_sp;
  logic [DATA_WIDTH-1:0] unused_st_value;
  logic                  unused_st_nv;
  assign unused_rf_sp    = rf_sp;
  assign unused_st_value = st_value;
  assign unused_st_nv    = st_n ^ st_v ^ st_z;  // touch all three to suppress


  // ---------------------------------------------------------------------------
  // Next-state + combinational outputs
  //
  // Safe defaults at the top — none of the output muxes can infer a latch.
  // ---------------------------------------------------------------------------
  always_comb begin
    // Defaults.
    state_d       = state_q;
    mem_req       = 1'b0;
    mem_we        = 1'b0;
    mem_addr      = '0;
    mem_size      = '0;
    mem_wdata     = '0;
    pc_advance_en = 1'b0;

    unique case (state_q)
      CORE_RESET: begin
        // Unconditional one-cycle transition out of reset.
        state_d = CORE_FETCH;
      end

      CORE_FETCH: begin
        // Architectural instruction word is 16 bits. Fetch from PC.
        mem_req  = 1'b1;
        mem_we   = 1'b0;
        mem_addr = pc_value;
        mem_size = INSTR_WORD_BITS;
        if (mem_ack) begin
          state_d       = CORE_DECODE;
          pc_advance_en = 1'b1;       // advance PC by INSTR_WORD_BITS
        end
      end

      CORE_DECODE: begin
        // Branch based on how many immediate words the decoded
        // instruction needs.
        if (decoded.needs_imm32) begin
          state_d = CORE_FETCH_IMM_LO;
        end else if (decoded.needs_imm16) begin
          state_d = CORE_FETCH_IMM_LO;
        end else begin
          state_d = CORE_EXECUTE;
        end
      end

      CORE_FETCH_IMM_LO: begin
        // Fetch the 16-bit low-immediate word from PC. Same protocol as
        // CORE_FETCH; PC advances by INSTR_WORD_BITS on ack.
        mem_req  = 1'b1;
        mem_we   = 1'b0;
        mem_addr = pc_value;
        mem_size = INSTR_WORD_BITS;
        if (mem_ack) begin
          pc_advance_en = 1'b1;
          state_d = decoded.needs_imm32 ? CORE_FETCH_IMM_HI : CORE_EXECUTE;
        end
      end

      CORE_FETCH_IMM_HI: begin
        mem_req  = 1'b1;
        mem_we   = 1'b0;
        mem_addr = pc_value;
        mem_size = INSTR_WORD_BITS;
        if (mem_ack) begin
          pc_advance_en = 1'b1;
          state_d = CORE_EXECUTE;
        end
      end

      CORE_EXECUTE: begin
        // ALU output and flags are combinational from decoded.alu_op,
        // alu_a, alu_b, and st_c. CORE_EXECUTE simply lets that result
        // settle for one cycle so CORE_WRITEBACK can latch it.
        state_d = CORE_WRITEBACK;
      end

      CORE_MEMORY: begin
        // Unused in Phase 3 — no instruction yet reaches this state.
        // Reserved for memory-touching instructions (Phase 4+).
        state_d = CORE_WRITEBACK;
      end

      CORE_WRITEBACK: begin
        state_d = CORE_FETCH;
      end

      default: begin
        // Defensive: any out-of-range encoding goes back to reset.
        state_d = CORE_RESET;
      end
    endcase
  end

  assign state_o          = state_q;
  assign pc_o             = pc_value;
  assign instr_word_o     = instr_word_q;
  assign illegal_opcode_o = illegal_q;

endmodule : tms34010_core
