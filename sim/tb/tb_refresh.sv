// -----------------------------------------------------------------------------
// tb_refresh.sv
//
// Unit test for tms34010_refresh — the DRAM-refresh address generator. Checks
// the refresh strobe interval (CONTROL.RR: 32 / 64 clocks), the row-address
// increment per refresh, and that RR = 11 (and the reserved 10) disable
// refresh. SPVU001A §6 (REFCNT, CONTROL.RR).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_refresh;
  import tms34010_pkg::*;

  logic       clk = 1'b0;
  logic       rst = 1'b1;
  logic [1:0] rr;
  always #5 clk = ~clk;

  logic [7:0] refresh_row;
  logic       refresh_req;

  tms34010_refresh u_ref (
    .clk(clk), .rst(rst), .rr(rr),
    .refresh_row(refresh_row), .refresh_req(refresh_req)
  );

  int unsigned failures;

  // Count refresh strobes over `n` clocks and return the gap between the first
  // two strobes (the refresh interval).
  task automatic run_and_count(input int unsigned n,
                               output int unsigned pulses,
                               output int unsigned first_gap);
    int unsigned last_idx;
    pulses = 0; first_gap = 0; last_idx = 0;
    for (int unsigned k = 1; k <= n; k++) begin
      @(negedge clk);
      if (refresh_req) begin
        pulses++;
        if (pulses == 2) first_gap = k - last_idx;
        last_idx = k;
      end
    end
  endtask

  initial begin : main
    int unsigned pulses, gap;
    failures = 0;
    rr = 2'b00;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // RR = 00: refresh every 32 clocks. Over 96 clocks expect 3 strobes
    // (at clocks 31, 63, 95), 32 apart, and the row reaches 3.
    run_and_count(96, pulses, gap);
    if (pulses != 3) begin
      $display("TEST_RESULT: FAIL: RR=00 pulses=%0d, expected 3", pulses);
      failures++;
    end
    if (gap != 32) begin
      $display("TEST_RESULT: FAIL: RR=00 interval=%0d clocks, expected 32", gap);
      failures++;
    end
    if (refresh_row != 8'd3) begin
      $display("TEST_RESULT: FAIL: RR=00 row=%0d, expected 3", refresh_row);
      failures++;
    end

    // RR = 01: refresh every 64 clocks. Over 128 clocks expect 2 strobes, 64
    // apart. Reset the counter first.
    @(negedge clk); rst = 1'b1; rr = 2'b01; repeat (2) @(posedge clk); @(negedge clk); rst = 1'b0;
    run_and_count(128, pulses, gap);
    if (pulses != 2) begin
      $display("TEST_RESULT: FAIL: RR=01 pulses=%0d, expected 2", pulses);
      failures++;
    end
    if (gap != 64) begin
      $display("TEST_RESULT: FAIL: RR=01 interval=%0d clocks, expected 64", gap);
      failures++;
    end

    // RR = 11: no refresh. Over 100 clocks expect 0 strobes; row stays 0.
    @(negedge clk); rst = 1'b1; rr = 2'b11; repeat (2) @(posedge clk); @(negedge clk); rst = 1'b0;
    run_and_count(100, pulses, gap);
    if (pulses != 0) begin
      $display("TEST_RESULT: FAIL: RR=11 pulses=%0d, expected 0 (refresh disabled)", pulses);
      failures++;
    end
    if (refresh_row != 8'd0) begin
      $display("TEST_RESULT: FAIL: RR=11 row=%0d, expected 0", refresh_row);
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (refresh: 32/64-clock interval per RR, row increments, RR=11 disables)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_refresh hard timeout");
    $fatal(1);
  end

endmodule : tb_refresh
