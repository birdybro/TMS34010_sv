// -----------------------------------------------------------------------------
// tb_pc.sv
//
// Targeted unit test for tms34010_pc. Covers:
//   1. Reset produces RESET_VALUE.
//   2. Hold-when-idle (neither load nor advance) keeps PC stable.
//   3. Single advance increments PC by the requested bit count.
//   4. Cumulative advances accumulate.
//   5. Single load overrides PC.
//   6. Load takes precedence over a simultaneously-asserted advance.
//   7. Advance by INSTR_WORD_BITS matches the architectural instruction
//      step (16 bits per fetch — see 01-architecture.md).
//
// Pass/fail convention: prints "TEST_RESULT: PASS" if every check passes,
// "TEST_RESULT: FAIL: <reason>" otherwise. The testbench performs every
// check before exiting so a multi-failure run reports the first failure
// found.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pc;
  import tms34010_pkg::*;

  // ---------------------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------------------
  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // DUT wiring
  // ---------------------------------------------------------------------------
  // Use a non-zero RESET_VALUE so we can distinguish "reset took" from
  // "register happened to be zero".
  localparam logic [ADDR_WIDTH-1:0] TB_RESET_VALUE = 32'h0000_1000;

  logic                          load_en;
  logic [ADDR_WIDTH-1:0]         load_value;
  logic                          advance_en;
  logic [PC_ADVANCE_WIDTH-1:0]   advance_amount;
  logic [ADDR_WIDTH-1:0]         pc_o;

  tms34010_pc #(
    .RESET_VALUE (TB_RESET_VALUE)
  ) dut (
    .clk            (clk),
    .rst            (rst),
    .load_en        (load_en),
    .load_value     (load_value),
    .advance_en     (advance_en),
    .advance_amount (advance_amount),
    .pc_o           (pc_o)
  );

  // ---------------------------------------------------------------------------
  // Test helpers
  //
  // Drive control inputs for exactly one clock edge, then de-assert. Each
  // call returns control to the caller AFTER the resulting PC value has
  // been latched by the DUT. We sample after `#1` to slip past the NBA
  // region so reads observe the freshly-written PC.
  // ---------------------------------------------------------------------------
  task automatic do_idle();
    load_en        = 1'b0;
    advance_en     = 1'b0;
    @(posedge clk);
    #1;
  endtask

  task automatic do_advance(input logic [PC_ADVANCE_WIDTH-1:0] amount);
    advance_en     = 1'b1;
    advance_amount = amount;
    load_en        = 1'b0;
    @(posedge clk);
    advance_en     = 1'b0;
    #1;
  endtask

  task automatic do_load(input logic [ADDR_WIDTH-1:0] value);
    load_en        = 1'b1;
    load_value     = value;
    advance_en     = 1'b0;
    @(posedge clk);
    load_en        = 1'b0;
    #1;
  endtask

  task automatic do_load_and_advance(
    input logic [ADDR_WIDTH-1:0]      value,
    input logic [PC_ADVANCE_WIDTH-1:0] amount
  );
    load_en        = 1'b1;
    load_value     = value;
    advance_en     = 1'b1;
    advance_amount = amount;
    @(posedge clk);
    load_en        = 1'b0;
    advance_en     = 1'b0;
    #1;
  endtask

  int unsigned failures;

  task automatic expect_pc(input logic [ADDR_WIDTH-1:0] expected,
                           input string                 label);
    if (pc_o !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected PC=%08h, observed=%08h",
               label, expected, pc_o);
      failures++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // Test body
  // ---------------------------------------------------------------------------
  initial begin : main
    failures       = 0;
    load_en        = 1'b0;
    load_value     = '0;
    advance_en     = 1'b0;
    advance_amount = '0;

    // 1. Reset produces RESET_VALUE.
    repeat (3) @(posedge clk);
    #1;
    expect_pc(TB_RESET_VALUE, "after-reset");

    // Release reset.
    rst = 1'b0;

    // 2. Hold-when-idle.
    do_idle();
    expect_pc(TB_RESET_VALUE, "idle-after-reset-release");
    do_idle();
    expect_pc(TB_RESET_VALUE, "two-idles");

    // 3. Single advance by INSTR_WORD_BITS (=16).
    do_advance(PC_ADVANCE_WIDTH'(INSTR_WORD_BITS));
    expect_pc(TB_RESET_VALUE + 32'd16, "advance-by-16");

    // 4. Cumulative advances.
    do_advance(PC_ADVANCE_WIDTH'(INSTR_WORD_BITS));
    expect_pc(TB_RESET_VALUE + 32'd32, "advance-twice-32");
    do_advance(8'd32);
    expect_pc(TB_RESET_VALUE + 32'd64, "advance-by-32-cumulative");

    // 5. Single absolute load.
    do_load(32'hDEAD_0000);
    expect_pc(32'hDEAD_0000, "load-absolute");
    do_idle();
    expect_pc(32'hDEAD_0000, "load-then-idle");

    // 6. Load wins over simultaneous advance.
    do_load_and_advance(32'h1234_5678, 8'd16);
    expect_pc(32'h1234_5678, "load-wins-over-advance");

    // Independent confirmation that advance still works after a load.
    do_advance(PC_ADVANCE_WIDTH'(INSTR_WORD_BITS));
    expect_pc(32'h1234_5688, "advance-after-load");

    // 7. INSTR_WORD_BITS matches the package's architectural step.
    if (INSTR_WORD_BITS !== 6'd16) begin
      $display("TEST_RESULT: FAIL: INSTR_WORD_BITS=%0d, expected 16",
               INSTR_WORD_BITS);
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (all PC checks passed)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed (see lines above)",
               failures);
    end

    $finish;
  end

  // Watchdog.
  initial begin : watchdog
    #10_000;
    $display("TEST_RESULT: FAIL: tb_pc hard timeout at 10us simulated");
    $fatal(1);
  end

endmodule : tb_pc
