// -----------------------------------------------------------------------------
// tb_alu.sv
//
// Test vectors for tms34010_alu. Every operation gets at least:
//   - One normal case.
//   - One zero-result case (verifies Z).
//   - One negative-result case (verifies N).
//   - Where applicable, an overflow case (verifies C and V independently).
//
// The ALU is purely combinational, so each "test vector" is a transient
// drive of inputs followed by a `#1` settle and a check of `result` + `flags`.
// No clock is needed; we still instantiate one for waveform niceness.
//
// Flag-semantics are the "obvious" two's-complement convention documented
// at the top of tms34010_alu.sv and tracked as docs/assumptions.md A0009.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_alu;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;  // unused by the DUT — present for waveform clarity

  // ---------------------------------------------------------------------------
  // DUT wiring
  // ---------------------------------------------------------------------------
  alu_op_t                op;
  logic [DATA_WIDTH-1:0]  a;
  logic [DATA_WIDTH-1:0]  b;
  logic                   cin;
  logic [DATA_WIDTH-1:0]  result;
  alu_flags_t             flags;

  tms34010_alu dut (
    .op    (op),
    .a     (a),
    .b     (b),
    .cin   (cin),
    .result(result),
    .flags (flags)
  );

  int unsigned failures;

  task automatic apply(input alu_op_t                op_in,
                       input logic [DATA_WIDTH-1:0]  a_in,
                       input logic [DATA_WIDTH-1:0]  b_in,
                       input logic                   cin_in);
    op  = op_in;
    a   = a_in;
    b   = b_in;
    cin = cin_in;
    #1;
  endtask

  task automatic check(input logic [DATA_WIDTH-1:0]  exp_result,
                       input logic                   exp_n,
                       input logic                   exp_c,
                       input logic                   exp_z,
                       input logic                   exp_v,
                       input string                  label);
    if (result !== exp_result || flags.n !== exp_n || flags.c !== exp_c ||
        flags.z !== exp_z || flags.v !== exp_v) begin
      $display("TEST_RESULT: FAIL: %s: got r=%08h n=%0b c=%0b z=%0b v=%0b; expected r=%08h n=%0b c=%0b z=%0b v=%0b",
               label, result, flags.n, flags.c, flags.z, flags.v,
               exp_result, exp_n, exp_c, exp_z, exp_v);
      failures++;
    end
  endtask

  initial begin : main
    failures = 0;
    op       = ALU_OP_ADD;
    a        = '0;
    b        = '0;
    cin      = 1'b0;
    #1;

    // ---------------- ADD ----------------
    apply(ALU_OP_ADD, 32'd5, 32'd7, 1'b0);
    check(32'd12, 1'b0, 1'b0, 1'b0, 1'b0, "ADD 5+7");

    apply(ALU_OP_ADD, 32'd0, 32'd0, 1'b0);
    check(32'd0, 1'b0, 1'b0, 1'b1, 1'b0, "ADD 0+0 (Z)");

    apply(ALU_OP_ADD, 32'hFFFF_FFFF, 32'd1, 1'b0);
    check(32'd0, 1'b0, 1'b1, 1'b1, 1'b0, "ADD -1+1 (C+Z)");

    apply(ALU_OP_ADD, 32'h7FFF_FFFF, 32'd1, 1'b0);
    check(32'h8000_0000, 1'b1, 1'b0, 1'b0, 1'b1, "ADD max+1 (N+V signed overflow)");

    apply(ALU_OP_ADD, 32'h8000_0000, 32'h8000_0000, 1'b0);
    check(32'd0, 1'b0, 1'b1, 1'b1, 1'b1, "ADD min+min (Z+C+V)");

    // ---------------- ADDC ----------------
    apply(ALU_OP_ADDC, 32'd5, 32'd7, 1'b1);
    check(32'd13, 1'b0, 1'b0, 1'b0, 1'b0, "ADDC 5+7+1");

    apply(ALU_OP_ADDC, 32'hFFFF_FFFF, 32'd0, 1'b1);
    check(32'd0, 1'b0, 1'b1, 1'b1, 1'b0, "ADDC FFFF_FFFF+0+1 (C+Z)");

    // ---------------- SUB ----------------
    apply(ALU_OP_SUB, 32'd10, 32'd3, 1'b0);
    check(32'd7, 1'b0, 1'b0, 1'b0, 1'b0, "SUB 10-3");

    apply(ALU_OP_SUB, 32'd5, 32'd5, 1'b0);
    check(32'd0, 1'b0, 1'b0, 1'b1, 1'b0, "SUB 5-5 (Z)");

    apply(ALU_OP_SUB, 32'd3, 32'd10, 1'b0);
    // 3 - 10 = -7 = 32'hFFFF_FFF9. Borrow (a < b unsigned). N=1.
    check(32'hFFFF_FFF9, 1'b1, 1'b1, 1'b0, 1'b0, "SUB 3-10 (N+C borrow)");

    apply(ALU_OP_SUB, 32'h8000_0000, 32'd1, 1'b0);
    // min - 1 = max, signed overflow (negative - positive -> positive).
    check(32'h7FFF_FFFF, 1'b0, 1'b0, 1'b0, 1'b1, "SUB min-1 (V)");

    // ---------------- SUBB ----------------
    apply(ALU_OP_SUBB, 32'd10, 32'd3, 1'b1);
    // 10 - 3 - 1 = 6.
    check(32'd6, 1'b0, 1'b0, 1'b0, 1'b0, "SUBB 10-3-1");

    apply(ALU_OP_SUBB, 32'd0, 32'd0, 1'b1);
    // 0 - 0 - 1 = -1, borrow.
    check(32'hFFFF_FFFF, 1'b1, 1'b1, 1'b0, 1'b0, "SUBB 0-0-1 (N+C)");

    // ---------------- CMP (same as SUB, semantics are caller-side) ----------------
    apply(ALU_OP_CMP, 32'd5, 32'd5, 1'b0);
    check(32'd0, 1'b0, 1'b0, 1'b1, 1'b0, "CMP equal");

    apply(ALU_OP_CMP, 32'd3, 32'd5, 1'b0);
    check(32'hFFFF_FFFE, 1'b1, 1'b1, 1'b0, 1'b0, "CMP a<b unsigned");

    // ---------------- NEG ----------------
    apply(ALU_OP_NEG, 32'd5, 32'd0, 1'b0);
    check(32'hFFFF_FFFB, 1'b1, 1'b1, 1'b0, 1'b0, "NEG 5");

    apply(ALU_OP_NEG, 32'd0, 32'd0, 1'b0);
    check(32'd0, 1'b0, 1'b0, 1'b1, 1'b0, "NEG 0 (Z, no borrow)");

    apply(ALU_OP_NEG, 32'h8000_0000, 32'd0, 1'b0);
    // -MIN = MIN, signed overflow.
    check(32'h8000_0000, 1'b1, 1'b1, 1'b0, 1'b1, "NEG min (V)");

    // ---------------- AND ----------------
    apply(ALU_OP_AND, 32'hF0F0_F0F0, 32'h0FF0_FF0F, 1'b0);
    check(32'h00F0_F000, 1'b0, 1'b0, 1'b0, 1'b0, "AND mixed");

    apply(ALU_OP_AND, 32'h8000_0000, 32'hFFFF_FFFF, 1'b0);
    check(32'h8000_0000, 1'b1, 1'b0, 1'b0, 1'b0, "AND N-set");

    apply(ALU_OP_AND, 32'hAAAA_AAAA, 32'h5555_5555, 1'b0);
    check(32'd0, 1'b0, 1'b0, 1'b1, 1'b0, "AND zero (Z)");

    // ---------------- ANDN ----------------
    apply(ALU_OP_ANDN, 32'hFFFF_FFFF, 32'hF0F0_F0F0, 1'b0);
    check(32'h0F0F_0F0F, 1'b0, 1'b0, 1'b0, 1'b0, "ANDN");

    apply(ALU_OP_ANDN, 32'hF0F0_F0F0, 32'hF0F0_F0F0, 1'b0);
    check(32'd0, 1'b0, 1'b0, 1'b1, 1'b0, "ANDN identical -> 0");

    // ---------------- OR ----------------
    apply(ALU_OP_OR, 32'h0F0F_0F0F, 32'hF0F0_F0F0, 1'b0);
    check(32'hFFFF_FFFF, 1'b1, 1'b0, 1'b0, 1'b0, "OR -> all ones");

    apply(ALU_OP_OR, 32'd0, 32'd0, 1'b0);
    check(32'd0, 1'b0, 1'b0, 1'b1, 1'b0, "OR 0|0 (Z)");

    // ---------------- XOR ----------------
    apply(ALU_OP_XOR, 32'hAAAA_AAAA, 32'h5555_5555, 1'b0);
    check(32'hFFFF_FFFF, 1'b1, 1'b0, 1'b0, 1'b0, "XOR -> all ones");

    apply(ALU_OP_XOR, 32'hCAFEBABE, 32'hCAFEBABE, 1'b0);
    check(32'd0, 1'b0, 1'b0, 1'b1, 1'b0, "XOR a^a (Z)");

    // ---------------- NOT ----------------
    apply(ALU_OP_NOT, 32'hF0F0_F0F0, 32'd0, 1'b0);
    check(32'h0F0F_0F0F, 1'b0, 1'b0, 1'b0, 1'b0, "NOT");

    apply(ALU_OP_NOT, 32'hFFFF_FFFF, 32'd0, 1'b0);
    check(32'd0, 1'b0, 1'b0, 1'b1, 1'b0, "NOT -1 (Z)");

    apply(ALU_OP_NOT, 32'd0, 32'd0, 1'b0);
    check(32'hFFFF_FFFF, 1'b1, 1'b0, 1'b0, 1'b0, "NOT 0 (N)");

    // ---------------- PASS_A ----------------
    apply(ALU_OP_PASS_A, 32'h1234_5678, 32'hDEAD_BEEF, 1'b0);
    check(32'h1234_5678, 1'b0, 1'b0, 1'b0, 1'b0, "PASS_A");

    apply(ALU_OP_PASS_A, 32'h8000_0000, 32'd0, 1'b0);
    check(32'h8000_0000, 1'b1, 1'b0, 1'b0, 1'b0, "PASS_A N-set");

    // ---------------- PASS_B ----------------
    apply(ALU_OP_PASS_B, 32'h1111_1111, 32'h8000_0000, 1'b0);
    check(32'h8000_0000, 1'b1, 1'b0, 1'b0, 1'b0, "PASS_B");

    apply(ALU_OP_PASS_B, 32'h1111_1111, 32'd0, 1'b0);
    check(32'd0, 1'b0, 1'b0, 1'b1, 1'b0, "PASS_B Z");

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (all ALU vectors passed)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d ALU vector(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #50_000;
    $display("TEST_RESULT: FAIL: tb_alu hard timeout");
    $fatal(1);
  end

endmodule : tb_alu
