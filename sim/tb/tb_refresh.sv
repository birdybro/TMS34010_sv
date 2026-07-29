// -----------------------------------------------------------------------------
// tb_refresh.sv
//
// Unit regression for the exact REFCNT counter described by the 1988 User's
// Guide pages 6-45/6-46. It checks the first post-reset borrow, 32/64-clock
// periods, descending ROWADR, both disabled RR modes, processor load
// precedence, reserved-bit retention, odd RR=00 underflow, and row wrap.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_refresh;
  import tms34010_pkg::*;

  logic        clk = 1'b0;
  logic        rst = 1'b1;
  logic [1:0]  rr;
  logic        refcnt_load;
  logic [15:0] refcnt_wdata;
  always #5 clk = ~clk;

  logic [15:0] refcnt;
  logic [7:0]  refresh_row;
  logic        refresh_req;

  tms34010_refresh u_ref (
    .clk          (clk),
    .rst          (rst),
    .rr           (rr),
    .refcnt_load  (refcnt_load),
    .refcnt_wdata (refcnt_wdata),
    .refcnt       (refcnt),
    .refresh_row  (refresh_row),
    .refresh_req  (refresh_req)
  );

  int unsigned failures;

  task automatic check_value(
    input string       label,
    input logic [15:0] actual,
    input logic [15:0] expected
  );
    begin
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%04h actual=%04h",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  task automatic check_bit(
    input string label,
    input logic  actual,
    input logic  expected
  );
    begin
      if (actual !== expected) begin
        $display("TEST_RESULT: FAIL: %s expected=%0b actual=%0b",
                 label, expected, actual);
        failures++;
      end
    end
  endtask

  task automatic apply_reset(input logic [1:0] new_rr);
    begin
      @(negedge clk);
      rst          = 1'b1;
      rr           = new_rr;
      refcnt_load  = 1'b0;
      refcnt_wdata = 16'h0000;
      repeat (2) @(posedge clk);
      @(negedge clk);
      rst = 1'b0;
    end
  endtask

  task automatic load_refcnt(input logic [15:0] value);
    begin
      @(negedge clk);
      refcnt_wdata = value;
      refcnt_load  = 1'b1;
      @(negedge clk);
      refcnt_load = 1'b0;
    end
  endtask

  initial begin : main
    int unsigned pulse_count;

    failures     = 0;
    rr           = 2'b00;
    refcnt_load  = 1'b0;
    refcnt_wdata = 16'h0000;

    // RR=00: reset REFCNT=0. The first decrement by two borrows immediately,
    // producing row FF/RINTVL 62, then requests recur every 32 clocks.
    repeat (3) @(posedge clk);
    @(negedge clk);
    check_value("reset REFCNT", refcnt, 16'h0000);
    rst = 1'b0;
    @(negedge clk);
    check_bit("RR00 first-clock request", refresh_req, 1'b1);
    check_value("RR00 first decrement", refcnt, 16'hFFF8);
    check_value("RR00 first row", {8'h00, refresh_row}, 16'h00FF);

    pulse_count = 0;
    for (int unsigned k = 1; k <= 32; k++) begin
      @(negedge clk);
      if (refresh_req)
        pulse_count++;
      if ((k < 32) && refresh_req) begin
        $display("TEST_RESULT: FAIL: RR00 early request at gap %0d", k);
        failures++;
      end
    end
    if (pulse_count != 1) begin
      $display("TEST_RESULT: FAIL: RR00 requests over next 32 clocks=%0d expected=1",
               pulse_count);
      failures++;
    end
    check_value("RR00 second decremented row/refill", refcnt, 16'hFEF8);

    // RR=01: one count per clock, immediate first borrow then a 64-clock gap.
    apply_reset(2'b01);
    @(negedge clk);
    check_bit("RR01 first-clock request", refresh_req, 1'b1);
    check_value("RR01 first decrement", refcnt, 16'hFFFC);

    pulse_count = 0;
    for (int unsigned k = 1; k <= 64; k++) begin
      @(negedge clk);
      if (refresh_req)
        pulse_count++;
      if ((k < 64) && refresh_req) begin
        $display("TEST_RESULT: FAIL: RR01 early request at gap %0d", k);
        failures++;
      end
    end
    if (pulse_count != 1) begin
      $display("TEST_RESULT: FAIL: RR01 requests over next 64 clocks=%0d expected=1",
               pulse_count);
      failures++;
    end
    check_value("RR01 second decremented row/refill", refcnt, 16'hFEFC);

    // RR=10 is reserved and RR=11 disables refresh. This implementation
    // deterministically holds REFCNT for both non-counting encodings.
    apply_reset(2'b10);
    repeat (70) begin
      @(negedge clk);
      check_bit("RR10 no request", refresh_req, 1'b0);
    end
    check_value("RR10 counter held", refcnt, 16'h0000);

    apply_reset(2'b11);
    repeat (70) begin
      @(negedge clk);
      check_bit("RR11 no request", refresh_req, 1'b0);
    end
    check_value("RR11 counter held", refcnt, 16'h0000);

    // A software load owns all 16 bits. Reserved bits 1:0 persist while the
    // architected 14-bit counter decrements; the load itself suppresses req.
    load_refcnt(16'h0203);
    check_value("software load", refcnt, 16'h0203);
    check_bit("load suppresses request", refresh_req, 1'b0);
    rr = 2'b01;
    @(negedge clk);
    check_bit("loaded zero interval underflows", refresh_req, 1'b1);
    check_value("row decrements and reserved bits persist", refcnt, 16'h01FF);
    @(negedge clk);
    check_bit("request is one clock", refresh_req, 1'b0);
    check_value("RR01 resumes counting", refcnt, 16'h01FB);

    // A coincident load has explicit priority over automatic counting.
    load_refcnt(16'hAA03);
    check_value("load precedence", refcnt, 16'hAA03);
    check_bit("load precedence suppresses request", refresh_req, 1'b0);

    // RR=00 subtracts two, so both RINTVL=0 and RINTVL=1 borrow.
    rr = 2'b11;
    load_refcnt(16'h0007);
    rr = 2'b00;
    @(negedge clk);
    check_bit("RR00 odd interval borrow", refresh_req, 1'b1);
    check_value("RR00 odd interval row wrap", refcnt, 16'hFFFF);

    if (failures == 0)
      $display("TEST_RESULT: PASS (REFCNT: exact decrement, borrow, row, load, and RR semantics)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_refresh hard timeout");
    $fatal(1);
  end

endmodule : tb_refresh
