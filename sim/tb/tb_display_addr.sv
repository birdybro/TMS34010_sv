// -----------------------------------------------------------------------------
// tb_display_addr.sv
//
// Direct regression for live DPYADR and the held noninterlaced screen-refresh
// request. Covers frame reload, vertical-blank suppression, first-active-line
// scheduling, LCSTRT+1 cadence, request/payload stability, acknowledge-time
// DUDATE/ORG updates, SRE re-enable, processor load precedence, and reset.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_display_addr;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic        hblank_start;
  logic [15:0] vcount;
  logic [15:0] veblnk;
  logic [15:0] vsblnk;
  logic [15:0] dpystart;
  logic [15:0] dpyctl;
  logic [15:0] dpytap;
  logic        dpyadr_load;
  logic [15:0] dpyadr_wdata;
  logic [15:0] dpyadr;
  logic        refresh_req;
  logic        refresh_ack;
  logic [13:0] refresh_srfaddr;
  logic [15:0] refresh_dpytap;
  logic        refresh_org;

  localparam logic [15:0] SRE_DUDATE4 =
      (16'h0001 << DPYCTL_SRE_BIT)
    | (16'h0004 << DPYCTL_DUDATE_LO);
  localparam logic [15:0] SRE_ORG_DUDATE4 =
      SRE_DUDATE4 | (16'h0001 << DPYCTL_ORG_BIT);

  tms34010_display_addr u_dut (
    .clk             (clk),
    .rst             (rst),
    .hblank_start    (hblank_start),
    .vcount          (vcount),
    .veblnk          (veblnk),
    .vsblnk          (vsblnk),
    .dpystart        (dpystart),
    .dpyctl          (dpyctl),
    .dpytap          (dpytap),
    .dpyadr_load     (dpyadr_load),
    .dpyadr_wdata    (dpyadr_wdata),
    .dpyadr          (dpyadr),
    .refresh_req     (refresh_req),
    .refresh_ack     (refresh_ack),
    .refresh_srfaddr (refresh_srfaddr),
    .refresh_dpytap  (refresh_dpytap),
    .refresh_org     (refresh_org)
  );

  int unsigned failures;

  task automatic pulse_hblank(input logic [15:0] line);
    begin
      @(negedge clk);
      vcount       = line;
      hblank_start = 1'b1;
      @(negedge clk);
      hblank_start = 1'b0;
    end
  endtask

  task automatic pulse_ack;
    begin
      @(negedge clk);
      refresh_ack = 1'b1;
      @(negedge clk);
      refresh_ack = 1'b0;
    end
  endtask

  task automatic load_dpyadr(input logic [15:0] value);
    begin
      @(negedge clk);
      dpyadr_load  = 1'b1;
      dpyadr_wdata = value;
      @(negedge clk);
      dpyadr_load = 1'b0;
    end
  endtask

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

  task automatic check_addr(
    input string       label,
    input logic [13:0] actual,
    input logic [13:0] expected
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

  initial begin : main
    failures      = 0;
    hblank_start = 1'b0;
    vcount       = 16'h0000;
    veblnk       = 16'd2;
    vsblnk       = 16'd8;
    dpystart     = {14'h0123, 2'd1};
    dpyctl       = 16'h0000;
    dpytap       = 16'hABCD;
    dpyadr_load  = 1'b0;
    dpyadr_wdata = 16'h0000;
    refresh_ack  = 1'b0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    check_value("DPYADR reset", dpyadr, 16'h0000);
    check_bit("request reset", refresh_req, 1'b0);
    check_bit("ORG payload reset", refresh_org, 1'b0);
    rst = 1'b0;

    // Processor writes load all 16 live bits.
    load_dpyadr({14'h0200, 2'd3});
    check_value("processor DPYADR load", dpyadr, {14'h0200, 2'd3});

    dpyctl = SRE_DUDATE4;

    // Beginning vertical blank reloads SRFADR only. No screen refresh occurs
    // within vertical blank, even though SRE is enabled.
    pulse_hblank(vsblnk);
    check_value("frame reload preserves LNCNT",
                dpyadr, {14'h0123, 2'd3});
    pulse_hblank(16'd0);
    check_bit("vertical blank suppresses request", refresh_req, 1'b0);

    // The final HBLANK before active video loads LCSTRT and requests the
    // starting SRFADR. The request payload must remain stable through stalls.
    pulse_hblank(veblnk);
    check_value("first-active loads LCSTRT", dpyadr, {14'h0123, 2'd1});
    check_bit("first-active request", refresh_req, 1'b1);
    check_addr("starting SRFADR payload", refresh_srfaddr, 14'h0123);
    check_value("starting DPYTAP payload masks reserved bits",
                refresh_dpytap, 16'h2BCD);
    check_bit("starting ORG payload", refresh_org, 1'b0);

    dpytap = 16'h5555;
    repeat (6) @(negedge clk);
    check_bit("request held through stall", refresh_req, 1'b1);
    check_addr("stalled SRFADR stable", refresh_srfaddr, 14'h0123);
    check_value("stalled DPYTAP stable", refresh_dpytap, 16'h2BCD);
    check_bit("stalled ORG stable", refresh_org, 1'b0);

    // Completion, not request, advances SRFADR and reloads LNCNT.
    pulse_ack();
    check_bit("ack clears request", refresh_req, 1'b0);
    check_value("ack increments SRFADR by DUDATE",
                dpyadr, {14'h0127, 2'd1});

    // LCSTRT=1 means two displayed scan lines between refresh cycles.
    pulse_hblank(16'd3);
    check_bit("first intervening line no request", refresh_req, 1'b0);
    check_value("LNCNT decremented", dpyadr, {14'h0127, 2'd0});
    pulse_hblank(16'd4);
    check_bit("second line requests", refresh_req, 1'b1);
    check_addr("second request address", refresh_srfaddr, 14'h0127);

    // ORG reverses the completion update direction.
    dpyctl = SRE_ORG_DUDATE4;
    check_bit("pending request retains captured ORG", refresh_org, 1'b0);
    pulse_ack();
    check_value("ORG decrement on completion",
                dpyadr, {14'h0123, 2'd1});

    // Disabling SRE prevents new requests and holds LNCNT. Re-enabling forces
    // the next eligible HBLANK regardless of the processor-loaded count.
    dpyctl = 16'h0000;
    load_dpyadr({14'h0333, 2'd3});
    pulse_hblank(16'd5);
    check_bit("SRE disabled", refresh_req, 1'b0);
    check_value("disabled LNCNT holds", dpyadr, {14'h0333, 2'd3});
    dpyctl = SRE_ORG_DUDATE4;
    repeat (2) @(negedge clk);
    pulse_hblank(16'd6);
    check_bit("SRE re-enable requests next eligible line", refresh_req, 1'b1);
    check_addr("re-enabled request address", refresh_srfaddr, 14'h0333);
    check_bit("re-enabled request captures ORG", refresh_org, 1'b1);

    // Processor load wins a same-edge completion while the request still
    // retires. This deterministic collision rule keeps split-screen writes
    // from being overwritten by an automatic update.
    @(negedge clk);
    dpyadr_load  = 1'b1;
    dpyadr_wdata = {14'h02AA, 2'd2};
    refresh_ack  = 1'b1;
    @(negedge clk);
    dpyadr_load = 1'b0;
    refresh_ack = 1'b0;
    check_value("processor load wins completion", dpyadr, {14'h02AA, 2'd2});
    check_bit("collision still retires request", refresh_req, 1'b0);

    // Synchronous reset clears live state and any held request.
    @(negedge clk);
    rst = 1'b1;
    @(negedge clk);
    check_value("reset recovery DPYADR", dpyadr, 16'h0000);
    check_bit("reset recovery request", refresh_req, 1'b0);
    check_bit("reset recovery ORG payload", refresh_org, 1'b0);

    if (failures == 0)
      $display("TEST_RESULT: PASS (display address: frame/line scheduling, held request, ack update)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_display_addr hard timeout");
    $fatal(1);
  end

endmodule : tb_display_addr
