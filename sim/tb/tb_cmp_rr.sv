// -----------------------------------------------------------------------------
// tb_cmp_rr.sv
//
// End-to-end test for `CMP Rs, Rd` (Compare Registers).
//
// Encoding (SPVU001A A-14): `0100 100S SSSR DDDD`, 7-bit prefix
// 7'b0100100. Same operand layout as SUB.
//
// Operation: status bits set as if `Rd - Rs` were computed; **Rd is
// unchanged** (the spec calls this a "nondestructive compare"). This
// is the first instruction in the project with `wb_reg_en = 0`.
//
// Test verifies, for each case:
//   1. Rs and Rd are both unchanged after CMP.
//   2. The N/C/Z/V flags equal what an equivalent SUB would have set.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_cmp_rr;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

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

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction
  function automatic instr_word_t cmp_rr_enc(input reg_file_t rf,
                                             input reg_idx_t  rs,
                                             input reg_idx_t  rd);
    cmp_rr_enc = 16'h4800
               | (instr_word_t'(rs) << 5)
               | (instr_word_t'(rf) << 4)
               | (instr_word_t'(rd));
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_file_t   rf,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(rf, i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_cmp_rr(input int unsigned p,
                                               input reg_file_t   rf,
                                               input reg_idx_t    rs,
                                               input reg_idx_t    rd);
    u_mem.mem[p] = cmp_rr_enc(rf, rs, rd);
    place_cmp_rr = p + 1;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual,
                           input logic [DATA_WIDTH-1:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_bit(input string label, input logic actual, input logic expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b",
               label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p;
    failures = 0;

    // Encoding sanity: CMP A1,A2 = 0100_100_0001_0_0010 = 0100 1000 0010 0010 = 0x4822
    if (cmp_rr_enc(REG_FILE_A, 4'd1, 4'd2) !== 16'h4822) begin
      $display("TEST_RESULT: FAIL: cmp_rr_enc(A1,A2)=%04h, expected 4822",
               cmp_rr_enc(REG_FILE_A, 4'd1, 4'd2));
      failures++;
    end

    // Program: prime registers, then CMP, ending each case with the
    // flag-defining CMP. The LAST CMP determines the final ST snapshot.
    //
    //   A1 = 7, A2 = 3
    //   CMP A2, A1   ; flags from 7-3 = 4; A1 stays 7, A2 stays 3.
    // Final state after this sole CMP:
    //   N=0 (result MSB), Z=0 (result != 0), C=0 (no borrow, 7 > 3 unsigned),
    //   V=0 (no signed overflow).
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'd7);
    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'd3);
    p = place_cmp_rr (p, REG_FILE_A, 4'd2, 4'd1);

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (100) @(posedge clk);
    #1;

    // 1. CMP did NOT modify either register.
    check_reg("A1 unchanged by CMP", u_core.u_regfile.a_regs[1], 32'd7);
    check_reg("A2 unchanged by CMP", u_core.u_regfile.a_regs[2], 32'd3);

    // 2. Flags match SUB-equivalent (7 - 3 = 4).
    check_bit("CMP 7,3 -> N=0", u_core.u_status_reg.n_o, 1'b0);
    check_bit("CMP 7,3 -> Z=0", u_core.u_status_reg.z_o, 1'b0);
    check_bit("CMP 7,3 -> C=0", u_core.u_status_reg.c_o, 1'b0);
    check_bit("CMP 7,3 -> V=0", u_core.u_status_reg.v_o, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (CMP did not modify Rs/Rd; flags match equivalent SUB)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #200_000;
    $display("TEST_RESULT: FAIL: tb_cmp_rr hard timeout");
    $fatal(1);
  end

endmodule : tb_cmp_rr
