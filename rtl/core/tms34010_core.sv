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
  // Datapath modules
  //
  // Phase 3 wiring: regfile, ALU, and status register are instantiated and
  // their datapath nets are connected, but every "go" signal (wr_en,
  // flag_update_en, st_write_en) is tied 0. This commit changes the
  // module graph but not any observable behavior — Task 0012 replaces the
  // tied-off control signals with decoded-instruction-driven values for
  // the first real instruction (MOVI).
  //
  // The wires that will become control points are named for clarity even
  // when currently constant, so Task 0012's diff is small and reviewable.
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

  // ---- Control: tied-off until Task 0012 wires decode-driven values ----
  assign rf_rs1_file = REG_FILE_A;
  assign rf_rs1_idx  = 4'd0;
  assign rf_rs2_file = REG_FILE_A;
  assign rf_rs2_idx  = 4'd0;
  assign rf_wr_en    = 1'b0;
  assign rf_wr_file  = REG_FILE_A;
  assign rf_wr_idx   = 4'd0;
  // Writeback path: ALU result flows here. Currently no-op (wr_en=0).
  assign rf_wr_data  = alu_result;

  assign alu_op  = ALU_OP_PASS_A;
  assign alu_a   = rf_rs1_data;
  assign alu_b   = rf_rs2_data;
  assign alu_cin = st_c;

  assign st_flag_update_en = 1'b0;
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
        // Phase 3 skeleton: decoder runs combinationally; we always
        // advance to EXECUTE on the next clock. Future phases may stall
        // here for multi-word fetches (long-immediate forms).
        state_d = CORE_EXECUTE;
      end

      CORE_EXECUTE: begin
        // Phase 3 skeleton: no real datapath. Illegal-opcode latch was
        // already set in the always_ff sticky block above. Advance.
        // Task 0011+ will switch on decoded.iclass here.
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
