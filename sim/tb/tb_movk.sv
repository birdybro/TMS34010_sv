// -----------------------------------------------------------------------------
// tb_movk.sv
//
// End-to-end test for `MOVK K, Rd` (Move Constant - 5 bits).
//
// What this exercises that the MOVI tests didn't:
//   - Single-word (no extra immediate fetch) instruction path through the
//     FSM: FETCH → DECODE → EXECUTE → WRITEBACK → FETCH.
//   - K immediate sourced directly from the instruction word (bits [9:5]),
//     not from a follow-on fetched word.
//   - "Does not affect the status register" semantics: after a MOVK
//     sequence, ST is still at its reset value (zeros).
//
// Encoding (A0013): MOVK K, Rd = bits[15:10]=6'b000110, bits[9:5]=K
// (5-bit unsigned, zero-extended), bits[4:0]={file,idx}. Cross-checked
// against SPVU004 listing "MOVK 1, A12 → 0x182C" and "MOVK 8, SPTCH(B1)
// → 0x1911".
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_movk;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // Wiring
  // ---------------------------------------------------------------------------
  logic                          mem_req;
  logic                          mem_we;
  logic [ADDR_WIDTH-1:0]         mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0]   mem_size;
  logic [DATA_WIDTH-1:0]         mem_wdata;
  logic [DATA_WIDTH-1:0]         mem_rdata;
  logic                          mem_ack;
  core_state_t                   state_w;
  logic [ADDR_WIDTH-1:0]         pc_w;
  instr_word_t                   instr_w;
  logic                          illegal_w;

  tms34010_core u_core (
    .clk             (clk),
    .rst             (rst),
    .mem_req         (mem_req),
    .mem_we          (mem_we),
    .mem_addr        (mem_addr),
    .mem_size        (mem_size),
    .mem_wdata       (mem_wdata),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w)
  );

  sim_memory_model #(.DEPTH_WORDS(64)) u_mem (
    .clk      (clk),
    .rst      (rst),
    .mem_req  (mem_req),
    .mem_we   (mem_we),
    .mem_addr (mem_addr),
    .mem_size (mem_size),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata),
    .mem_ack  (mem_ack)
  );

  // ---------------------------------------------------------------------------
  // Encoding helper.
  //   MOVK K, Rd = 0x1800 | (K << 5) | (R << 4) | N
  // ---------------------------------------------------------------------------
  function automatic instr_word_t movk_enc(input logic [4:0] k,
                                           input reg_file_t  rf,
                                           input reg_idx_t   idx);
    movk_enc = 16'h1800
             | (instr_word_t'(k)  << 5)
             | (instr_word_t'(rf) << 4)
             | (instr_word_t'(idx));
  endfunction

  int unsigned failures;

  task automatic check_reg(input string                  label,
                           input logic [DATA_WIDTH-1:0]  actual,
                           input logic [DATA_WIDTH-1:0]  expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  task automatic check_bit(input string  label,
                           input logic   actual,
                           input logic   expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b",
               label, expected, actual);
      failures++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Test body
  // ---------------------------------------------------------------------------
  initial begin : main
    failures = 0;

    // Confirm the encoding helper matches the assembler listing:
    //   "MOVK 1, A12 → 0x182C"
    if (movk_enc(5'd1, REG_FILE_A, 4'd12) !== 16'h182C) begin
      $display("TEST_RESULT: FAIL: movk_enc(1,A12) = %04h, expected 182C",
               movk_enc(5'd1, REG_FILE_A, 4'd12));
      failures++;
    end
    //   "MOVK 8, B1 → 0x1911"
    if (movk_enc(5'd8, REG_FILE_B, 4'd1) !== 16'h1911) begin
      $display("TEST_RESULT: FAIL: movk_enc(8,B1) = %04h, expected 1911",
               movk_enc(5'd8, REG_FILE_B, 4'd1));
      failures++;
    end

    // Program: a few MOVK instructions covering K range edges.
    //   MOVK 1, A0      ← smallest non-zero
    //   MOVK 31, A14    ← largest 5-bit K, zero-extended to 32-bit
    //   MOVK 0, A1      ← K=0 (literal zero per A0013)
    //   MOVK 16, B3     ← bit 4 of K set
    //   MOVK 5, B12     ← arbitrary
    u_mem.mem[0] = movk_enc(5'd1,  REG_FILE_A, 4'd0);
    u_mem.mem[1] = movk_enc(5'd31, REG_FILE_A, 4'd14);
    u_mem.mem[2] = movk_enc(5'd0,  REG_FILE_A, 4'd1);
    u_mem.mem[3] = movk_enc(5'd16, REG_FILE_B, 4'd3);
    u_mem.mem[4] = movk_enc(5'd5,  REG_FILE_B, 4'd12);

    // Reset.
    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Each MOVK is a single-word instruction, ~5 cycles in the current
    // FSM (FETCH+ack, DECODE, EXECUTE, WRITEBACK plus mem-ack waits).
    // Five = ~25 cycles. Use 60 for headroom.
    repeat (60) @(posedge clk);
    #1;

    check_reg("A0  after MOVK 1",  u_core.u_regfile.a_regs[0],  32'h0000_0001);
    check_reg("A14 after MOVK 31", u_core.u_regfile.a_regs[14], 32'h0000_001F);
    check_reg("A1  after MOVK 0",  u_core.u_regfile.a_regs[1],  32'h0000_0000);
    check_reg("B3  after MOVK 16", u_core.u_regfile.b_regs[3],  32'h0000_0010);
    check_reg("B12 after MOVK 5",  u_core.u_regfile.b_regs[12], 32'h0000_0005);

    // ST must be unchanged from reset (all zeros) because MOVK doesn't
    // affect the status register.
    check_bit("ST.N preserved", u_core.u_status_reg.n_o, 1'b0);
    check_bit("ST.C preserved", u_core.u_status_reg.c_o, 1'b0);
    check_bit("ST.Z preserved", u_core.u_status_reg.z_o, 1'b0);
    check_bit("ST.V preserved", u_core.u_status_reg.v_o, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (5 MOVK writes verified; ST stayed at reset zeros)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #100_000;
    $display("TEST_RESULT: FAIL: tb_movk hard timeout");
    $fatal(1);
  end

endmodule : tb_movk
