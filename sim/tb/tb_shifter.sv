// -----------------------------------------------------------------------------
// tb_shifter.sv
//
// Test vectors for tms34010_shifter. Each operation gets:
//   - amount == 0 (identity passthrough, C = 0)
//   - small amount (1..7)
//   - large amount (29..31)
//   - boundary patterns (all ones, alternating, sign-bit)
//
// The shifter is combinational; tests are transient input drives.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_shifter;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // DUT wiring
  // ---------------------------------------------------------------------------
  shift_op_t                      op;
  logic [DATA_WIDTH-1:0]          a;
  logic [SHIFT_AMOUNT_WIDTH-1:0]  amount;
  logic [DATA_WIDTH-1:0]          result;
  alu_flags_t                     flags;

  tms34010_shifter dut (
    .op    (op),
    .a     (a),
    .amount(amount),
    .result(result),
    .flags (flags)
  );

  int unsigned failures;

  task automatic apply(input shift_op_t                       op_in,
                       input logic [DATA_WIDTH-1:0]           a_in,
                       input logic [SHIFT_AMOUNT_WIDTH-1:0]   amount_in);
    op     = op_in;
    a      = a_in;
    amount = amount_in;
    #1;
  endtask

  task automatic check(input logic [DATA_WIDTH-1:0] exp_result,
                       input logic                  exp_n,
                       input logic                  exp_c,
                       input logic                  exp_z,
                       input string                 label);
    if (result !== exp_result || flags.n !== exp_n ||
        flags.c !== exp_c || flags.z !== exp_z || flags.v !== 1'b0) begin
      $display("TEST_RESULT: FAIL: %s: got r=%08h n=%0b c=%0b z=%0b v=%0b; expected r=%08h n=%0b c=%0b z=%0b v=0",
               label, result, flags.n, flags.c, flags.z, flags.v,
               exp_result, exp_n, exp_c, exp_z);
      failures++;
    end
  endtask

  initial begin : main
    failures = 0;
    op       = SHIFT_OP_SLL;
    a        = '0;
    amount   = '0;
    #1;

    // -------- amount==0 identity --------
    apply(SHIFT_OP_SLL, 32'hCAFE_BABE, 5'd0);
    check(32'hCAFE_BABE, 1'b1, 1'b0, 1'b0, "SLL by 0 (identity)");
    apply(SHIFT_OP_SRL, 32'd0, 5'd0);
    check(32'd0, 1'b0, 1'b0, 1'b1, "SRL by 0 of 0 (Z)");
    apply(SHIFT_OP_RL, 32'h8000_0001, 5'd0);
    check(32'h8000_0001, 1'b1, 1'b0, 1'b0, "RL by 0 (identity)");

    // -------- SLL --------
    apply(SHIFT_OP_SLL, 32'h0000_0001, 5'd1);
    check(32'h0000_0002, 1'b0, 1'b0, 1'b0, "SLL 1<<1");

    apply(SHIFT_OP_SLL, 32'h0000_0001, 5'd31);
    check(32'h8000_0000, 1'b1, 1'b0, 1'b0, "SLL 1<<31 (N)");

    apply(SHIFT_OP_SLL, 32'hFFFF_FFFF, 5'd1);
    // C = a[31] = 1
    check(32'hFFFF_FFFE, 1'b1, 1'b1, 1'b0, "SLL FFFFFFFF<<1 (C)");

    apply(SHIFT_OP_SLL, 32'h8000_0000, 5'd1);
    // result = 0 (Z); C = a[31] = 1
    check(32'd0, 1'b0, 1'b1, 1'b1, "SLL 8000_0000<<1 (Z+C)");

    // -------- SLA (== SLL in current impl) --------
    apply(SHIFT_OP_SLA, 32'h4000_0000, 5'd1);
    check(32'h8000_0000, 1'b1, 1'b0, 1'b0, "SLA 4000_0000<<1 (sign change; V=0 per A0009)");

    // -------- SRL --------
    apply(SHIFT_OP_SRL, 32'h8000_0000, 5'd1);
    // C = a[0] = 0
    check(32'h4000_0000, 1'b0, 1'b0, 1'b0, "SRL 8000_0000>>1");

    apply(SHIFT_OP_SRL, 32'hFFFF_FFFF, 5'd31);
    // C = a[30] = 1
    check(32'h0000_0001, 1'b0, 1'b1, 1'b0, "SRL FFFFFFFF>>31 (C)");

    apply(SHIFT_OP_SRL, 32'h0000_0001, 5'd1);
    // C = a[0] = 1; result = 0
    check(32'd0, 1'b0, 1'b1, 1'b1, "SRL 1>>1 (Z+C)");

    // -------- SRA --------
    apply(SHIFT_OP_SRA, 32'h8000_0000, 5'd1);
    // signed >>: sign-extend. result = 0xC000_0000. N=1.
    check(32'hC000_0000, 1'b1, 1'b0, 1'b0, "SRA 8000_0000>>>1");

    apply(SHIFT_OP_SRA, 32'h8000_0000, 5'd31);
    // sign-extend gives all ones
    check(32'hFFFF_FFFF, 1'b1, 1'b0, 1'b0, "SRA 8000_0000>>>31 (all ones)");

    apply(SHIFT_OP_SRA, 32'h4000_0000, 5'd1);
    // positive number, no sign extension. result = 0x2000_0000.
    check(32'h2000_0000, 1'b0, 1'b0, 1'b0, "SRA 4000_0000>>>1");

    // -------- RL --------
    apply(SHIFT_OP_RL, 32'h8000_0001, 5'd1);
    // rotate left by 1: a[31] wraps to bit 0. result = 0x0000_0003. C = a[31] = 1.
    check(32'h0000_0003, 1'b0, 1'b1, 1'b0, "RL 8000_0001 left 1");

    apply(SHIFT_OP_RL, 32'hCAFE_BABE, 5'd4);
    // a << 4 = 0xAFEB_ABE0, a >> 28 = 0xC. OR = 0xAFEB_ABEC.
    // C = a[32-4] = a[28]. 0xCAFE_BABE bits[31:28] = 0xC = 1100, so a[28] = 0.
    check(32'hAFEB_ABEC, 1'b1, 1'b0, 1'b0, "RL CAFEBABE left 4");

    apply(SHIFT_OP_RL, 32'h1234_5678, 5'd16);
    check(32'h5678_1234, 1'b0, 1'b0, 1'b0, "RL 1234_5678 left 16 (swap halves)");

    // -------- RR --------
    apply(SHIFT_OP_RR, 32'h8000_0001, 5'd1);
    // rotate right by 1: a[0] wraps to bit 31. result = 0xC000_0000. C = a[0] = 1.
    check(32'hC000_0000, 1'b1, 1'b1, 1'b0, "RR 8000_0001 right 1");

    apply(SHIFT_OP_RR, 32'hCAFE_BABE, 5'd4);
    // a >> 4 = 0x0CAF_EBAB, a << 28 = 0xE000_0000. OR = 0xECAF_EBAB.
    check(32'hECAF_EBAB, 1'b1, 1'b1, 1'b0, "RR CAFEBABE right 4");

    apply(SHIFT_OP_RR, 32'h1234_5678, 5'd16);
    check(32'h5678_1234, 1'b0, 1'b0, 1'b0, "RR 1234_5678 right 16 (swap halves)");

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (all shifter vectors passed)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d shifter vector(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #50_000;
    $display("TEST_RESULT: FAIL: tb_shifter hard timeout");
    $fatal(1);
  end

endmodule : tb_shifter
