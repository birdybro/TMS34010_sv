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
  logic [ADDR_WIDTH-1:0] pc_value;

  tms34010_pc u_pc (
    .clk            (clk),
    .rst            (rst),
    .load_en        (1'b0),               // no branches yet (Phase 4)
    .load_value     ('0),
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
  // Immediate latch
  //
  // Long-immediate-form instructions (MOVI IW/IL, ADDI IW/IL, ...) fetch
  // one or two additional 16-bit words after the opcode word. We latch
  // them into imm_lo_q / imm_hi_q during the CORE_FETCH_IMM_LO and
  // CORE_FETCH_IMM_HI states, then sign-extend or concatenate into a
  // 32-bit operand in CORE_EXECUTE.
  // ---------------------------------------------------------------------------
  instr_word_t imm_lo_q;
  instr_word_t imm_hi_q;

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

  // Writeback enable is a one-cycle pulse, gated by the FSM state.
  assign rf_wr_en   = (state_q == CORE_WRITEBACK) && decoded.wb_reg_en;
  assign rf_wr_file = decoded.rd_file;
  assign rf_wr_idx  = decoded.rd_idx;
  assign rf_wr_data = alu_result;

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
      INSTR_SUB_RR: alu_a = rf_rs2_data;   // Rd is the minuend
      default:      alu_a = rf_rs1_data;   // Rs (commutative ops, MOVI ignores it)
    endcase
  end
  always_comb begin
    unique case (decoded.iclass)
      INSTR_MOVI_IW,
      INSTR_MOVI_IL: alu_b = imm32;
      INSTR_MOVK:    alu_b = {{(DATA_WIDTH-5){1'b0}}, decoded.k5};
      INSTR_SUB_RR:  alu_b = rf_rs1_data;  // Rs is the subtrahend
      default:       alu_b = rf_rs2_data;
    endcase
  end
  assign alu_cin = st_c;

  // Status-register inputs. Flag-update is gated by FSM state, like the
  // regfile write. Full ST write port is unused until POPST lands.
  assign st_flag_update_en = (state_q == CORE_WRITEBACK) && decoded.wb_flags_en;
  assign st_write_en       = 1'b0;
  assign st_write_data     = '0;

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

  tms34010_status_reg u_status_reg (
    .clk           (clk),
    .rst           (rst),
    .flag_update_en(st_flag_update_en),
    .flags_in      (alu_flags),
    .st_write_en   (st_write_en),
    .st_write_data (st_write_data),
    .st_o          (st_value),
    .n_o           (st_n),
    .c_o           (st_c),
    .z_o           (st_z),
    .v_o           (st_v)
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
