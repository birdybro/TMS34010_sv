// -----------------------------------------------------------------------------
// tb_refresh_prescale.sv
//
// REFCNT counts local clocks (1988 UG pages 6-45/6-46: RR=00 requests a
// refresh every 32 local clocks, RR=01 every 64). With CLKS_PER_STATE=8 the
// core clock is eight times the local clock, so requests must be 256 and 512
// core clocks apart, and REFCNT must change only once per eight core clocks.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_refresh_prescale;

  localparam int unsigned CPS = 8;

  logic        clk = 1'b0;
  logic        rst = 1'b1;
  logic [1:0]  rr  = 2'b00;
  logic        load = 1'b0;
  logic [15:0] refcnt;
  logic [7:0]  row;
  logic        req;
  int          failures = 0;

  always #5 clk = ~clk;

  tms34010_refresh #(.CLKS_PER_STATE(CPS)) dut (
    .clk          (clk),
    .rst          (rst),
    .rr           (rr),
    .refcnt_load  (load),
    .refcnt_wdata (16'h0000),
    .refcnt       (refcnt),
    .refresh_row  (row),
    .refresh_req  (req)
  );

  int unsigned now = 0;
  int unsigned last_req = 0;
  int unsigned n_req = 0;
  int unsigned changes = 0;
  logic [15:0] prev_refcnt = 16'h0000;

  always @(posedge clk) begin
    now <= now + 1;
    if (!rst) begin
      if (refcnt != prev_refcnt) changes <= changes + 1;
      prev_refcnt <= refcnt;
    end
  end

  task automatic expect_spacing(input logic [1:0] mode, input int unsigned states);
    int unsigned gap;
    rr = mode;
    // Resynchronise on one request, then measure the next three.
    @(posedge clk iff req);
    last_req = now;
    for (int i = 0; i < 3; i++) begin
      @(posedge clk iff req);
      gap = now - last_req;
      last_req = now;
      if (gap != states * CPS) begin
        $display("FAIL: RR=%b request gap %0d core clocks, expected %0d", mode, gap, states * CPS);
        failures++;
      end
    end
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst = 1'b0;
    expect_spacing(2'b00, 32);
    expect_spacing(2'b01, 64);

    // RR=11 stops the counter.
    rr = 2'b11;
    repeat (2) @(posedge clk);
    changes = 0;
    repeat (100) @(posedge clk);
    if (changes != 0) begin
      $display("FAIL: REFCNT changed %0d times with RR=11", changes);
      failures++;
    end

    // RR=01: REFCNT steps once per local clock.
    rr = 2'b01;
    repeat (2) @(posedge clk);
    changes = 0;
    repeat (80 * CPS) @(posedge clk);
    if (changes < 79 || changes > 81) begin
      $display("FAIL: %0d REFCNT changes in 80 local clocks", changes);
      failures++;
    end

    if (failures == 0) $display("TEST_RESULT: PASS");
    else               $display("TEST_RESULT: FAIL (%0d)", failures);
    $finish;
  end

endmodule
