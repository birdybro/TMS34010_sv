// -----------------------------------------------------------------------------
// tb_sub_rr.sv
//
// End-to-end test for `SUB Rs, Rd`.
//
// Operation: Rd - Rs → Rd. Flags: N, C, Z, V from the difference (C is the
// borrow output, V is signed overflow).
//
// Encoding (SPVU001A A-14): `0100 010S SSSR DDDD`, 7-bit prefix
// 7'b0100010. Rs in bits[8:5], R in bit[4], Rd in bits[3:0]. Rs and Rd
// share the same file.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_sub_rr;
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

  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
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

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t idx);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(idx));
  endfunction
  function automatic instr_word_t sub_rr_enc(input reg_file_t rf,
                                             input reg_idx_t  rs,
                                             input reg_idx_t  rd);
    sub_rr_enc = 16'h4400
               | (instr_word_t'(rs) << 5)
               | (instr_word_t'(rf) << 4)
               | (instr_word_t'(rd));
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

  function automatic int unsigned place_movi_il(input int unsigned         p,
                                                input reg_file_t           rf,
                                                input reg_idx_t            idx,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(rf, idx);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_sub_rr(input int unsigned p,
                                               input reg_file_t   rf,
                                               input reg_idx_t    rs,
                                               input reg_idx_t    rd);
    u_mem.mem[p] = sub_rr_enc(rf, rs, rd);
    place_sub_rr = p + 1;
  endfunction

  initial begin : main
    int unsigned p;
    failures = 0;

    // Encoding sanity (SPVU001A A-14):
    //   SUB A1, A2 = 0100_010_0001_0_0010 = 0100 0100 0010 0010 = 0x4422
    if (sub_rr_enc(REG_FILE_A, 4'd1, 4'd2) !== 16'h4422) begin
      $display("TEST_RESULT: FAIL: sub_rr_enc(A1,A2)=%04h, expected 4422",
               sub_rr_enc(REG_FILE_A, 4'd1, 4'd2));
      failures++;
    end

    // Cases:
    //   1. Simple positive: 10 - 3 = 7. No borrow, no overflow.
    //   2. Equal: 5 - 5 = 0. Z=1.
    //   3. Borrow (a < b unsigned): 3 - 10 = -7 = 0xFFFFFFF9. C=1, N=1.
    //   4. Signed overflow: 0x80000000 - 1 = 0x7FFFFFFF. V=1, N=0.
    //   5. B-file: 0x0000_2000 - 0x0000_0FF0 = 0x0000_1010.
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'd10);
    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'd3);
    p = place_sub_rr (p, REG_FILE_A, 4'd2, 4'd1);   // A1 = A1 - A2 = 7

    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'd5);
    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'd5);
    p = place_sub_rr (p, REG_FILE_A, 4'd4, 4'd3);   // A3 = 0

    p = place_movi_il(p, REG_FILE_A, 4'd5, 32'd3);
    p = place_movi_il(p, REG_FILE_A, 4'd6, 32'd10);
    p = place_sub_rr (p, REG_FILE_A, 4'd6, 4'd5);   // A5 = 3-10 = -7 = 0xFFFFFFF9

    p = place_movi_il(p, REG_FILE_A, 4'd7, 32'h8000_0000);
    p = place_movi_il(p, REG_FILE_A, 4'd8, 32'd1);
    p = place_sub_rr (p, REG_FILE_A, 4'd8, 4'd7);   // A7 = MIN - 1 = MAX (V=1)

    p = place_movi_il(p, REG_FILE_B, 4'd0, 32'h0000_2000);
    p = place_movi_il(p, REG_FILE_B, 4'd1, 32'h0000_0FF0);
    p = place_sub_rr (p, REG_FILE_B, 4'd1, 4'd0);   // B0 = 0x1010

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // 15 instructions * average 9 cycles ~= 135. Use 250 for headroom.
    repeat (250) @(posedge clk);
    #1;

    check_reg("A1 = 10 - 3 = 7",  u_core.u_regfile.a_regs[1], 32'd7);
    check_reg("A3 = 5 - 5 = 0",   u_core.u_regfile.a_regs[3], 32'd0);
    check_reg("A5 = 3 - 10 = -7", u_core.u_regfile.a_regs[5], 32'hFFFF_FFF9);
    check_reg("A7 = MIN - 1 = MAX", u_core.u_regfile.a_regs[7], 32'h7FFF_FFFF);
    check_reg("B0 = 0x2000 - 0xFF0 = 0x1010", u_core.u_regfile.b_regs[0], 32'h0000_1010);

    // Final ST reflects the last SUB (B0 = 0x2000 - 0xFF0 = 0x1010).
    // Result is positive, nonzero, no borrow (0x2000 > 0xFF0 unsigned),
    // no signed overflow.
    check_bit("ST.N final", u_core.u_status_reg.n_o, 1'b0);
    check_bit("ST.Z final", u_core.u_status_reg.z_o, 1'b0);
    check_bit("ST.C final", u_core.u_status_reg.c_o, 1'b0);
    check_bit("ST.V final", u_core.u_status_reg.v_o, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (5 SUB RR cases verified: simple, equal-zero, borrow, signed overflow, B-file)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #500_000;
    $display("TEST_RESULT: FAIL: tb_sub_rr hard timeout");
    $fatal(1);
  end

endmodule : tb_sub_rr
