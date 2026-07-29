// -----------------------------------------------------------------------------
// tb_video.sv
//
// Unit test for tms34010_video — the horizontal/vertical timing generator.
// Drives the video clock with small timing-register values and checks every
// cycle over ~2.5 frames: writable HCOUNT/VCOUNT, HTOTAL/VTOTAL wrapping,
// sync/blank window compares, DPYCTL.ENV behavior, and the one-clock DPYINT
// strobe at the start of horizontal blanking.
//
// Timing: HTOTAL=7 (8-count line), HESYNC=2, HEBLNK=3, HSBLNK=6;
//         VTOTAL=3 (4-line frame), VESYNC=1, VEBLNK=1, VSBLNK=3; DPYINT=2.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_video;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  localparam logic [15:0] HESYNC = 16'd2,  HEBLNK = 16'd3,  HSBLNK = 16'd6,  HTOTAL = 16'd7;
  localparam logic [15:0] VESYNC = 16'd1,  VEBLNK = 16'd1,  VSBLNK = 16'd3,  VTOTAL = 16'd3;
  localparam logic [15:0] DPYINT = 16'd2;

  logic [15:0] hcount, vcount;
  logic        hsync, vsync, hblank, vblank, blank;
  logic        hblank_start, dpyint_pulse;
  logic        display_enable;
  logic        hcount_load, vcount_load;
  logic [15:0] hcount_wdata, vcount_wdata;

  tms34010_video u_video (
    .clk(clk), .rst(rst),
    .hesync(HESYNC), .heblnk(HEBLNK), .hsblnk(HSBLNK), .htotal(HTOTAL),
    .vesync(VESYNC), .veblnk(VEBLNK), .vsblnk(VSBLNK), .vtotal(VTOTAL),
    .dpyint(DPYINT), .display_enable(display_enable),
    .noninterlaced(1'b1),
    .hcount_load(hcount_load), .hcount_wdata(hcount_wdata),
    .vcount_load(vcount_load), .vcount_wdata(vcount_wdata),
    .hcount(hcount), .vcount(vcount),
    .hsync(hsync), .vsync(vsync), .hblank(hblank), .vblank(vblank),
    .blank(blank), .hblank_start(hblank_start),
    .dpyint_pulse(dpyint_pulse), .odd_field()
  );

  int unsigned failures;
  int unsigned dpyint_count;
  logic        saw_htotal, saw_vtotal, saw_hwrap, saw_vwrap;
  logic [15:0] prev_hc, prev_vc;
  logic        have_prev;

  task automatic fail(input string msg);
    $display("TEST_RESULT: FAIL: %s (hc=%0d vc=%0d)", msg, hcount, vcount);
    failures++;
  endtask

  initial begin : main
    failures = 0; dpyint_count = 0;
    saw_htotal = 0; saw_vtotal = 0; saw_hwrap = 0; saw_vwrap = 0; have_prev = 0;
    display_enable = 1'b0;
    hcount_load = 1'b0;
    vcount_load = 1'b0;
    hcount_wdata = 16'h0000;
    vcount_wdata = 16'h0000;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Counters continue while video is disabled, but BLANK is forced active
    // and display-interrupt generation is inhibited for a complete frame.
    repeat (36) begin
      @(negedge clk);
      if (!blank) fail("ENV=0 did not force blank");
      if (dpyint_pulse) fail("ENV=0 did not inhibit dpyint");
    end

    // Both architected counters are writable. Load them simultaneously in
    // this direct unit test, verify the result, then restart at frame origin.
    hcount_load  = 1'b1;
    hcount_wdata = 16'd4;
    vcount_load  = 1'b1;
    vcount_wdata = 16'd3;
    @(negedge clk);
    hcount_load = 1'b0;
    vcount_load = 1'b0;
    if (hcount !== 16'd4) fail("HCOUNT parallel load");
    if (vcount !== 16'd3) fail("VCOUNT parallel load");

    hcount_load  = 1'b1;
    hcount_wdata = 16'd0;
    vcount_load  = 1'b1;
    vcount_wdata = 16'd0;
    @(negedge clk);
    hcount_load = 1'b0;
    vcount_load = 1'b0;
    display_enable = 1'b1;

    // Run ~2.5 frames (8*4*2.5 = 80 clocks) and check every cycle.
    for (int unsigned k = 0; k < 84; k++) begin
      @(negedge clk);
      // Combinational window compares.
      if (hsync  !== (hcount <= HESYNC))                       fail("hsync window");
      if (vsync  !== (vcount <= VESYNC))                       fail("vsync window");
      if (hblank !== ((hcount <= HEBLNK) || (hcount > HSBLNK))) fail("hblank window");
      if (vblank !== ((vcount <= VEBLNK) || (vcount > VSBLNK))) fail("vblank window");
      if (blank  !== (hblank || vblank))                        fail("blank combine");
      if (hblank_start !== (hcount == HSBLNK))                  fail("hblank-start event");
      if (dpyint_pulse !== ((hcount == HSBLNK) && (vcount == DPYINT)))
        fail("dpyint strobe");
      if (dpyint_pulse) dpyint_count++;
      // Counter range.
      if (hcount > HTOTAL) fail("hcount > HTOTAL");
      if (vcount > VTOTAL) fail("vcount > VTOTAL");
      if (hcount == HTOTAL) saw_htotal = 1;
      if (vcount == VTOTAL) saw_vtotal = 1;
      // Transition check vs previous cycle.
      if (have_prev) begin
        if (prev_hc == HTOTAL) begin
          saw_hwrap = 1;
          if (hcount !== 16'd0) fail("hcount did not wrap to 0");
          if (prev_vc == VTOTAL) begin
            saw_vwrap = 1;
            if (vcount !== 16'd0) fail("vcount did not wrap to 0");
          end else if (vcount !== prev_vc + 16'd1) fail("vcount did not increment on hwrap");
        end else begin
          if (hcount !== prev_hc + 16'd1) fail("hcount did not increment");
          if (vcount !== prev_vc)         fail("vcount changed without hwrap");
        end
      end
      prev_hc = hcount; prev_vc = vcount; have_prev = 1;
    end

    if (!saw_htotal) fail("never reached HTOTAL");
    if (!saw_vtotal) fail("never reached VTOTAL");
    if (!saw_hwrap)  fail("never saw a horizontal wrap");
    if (!saw_vwrap)  fail("never saw a vertical (frame) wrap");
    if (dpyint_count < 2) begin
      $display("TEST_RESULT: FAIL: DPYINT strobe fired %0d times (expected >= 2 over 2.5 frames)",
               dpyint_count);
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (video: writable counters, timing windows, ENV, HBLANK DPYINT)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_video hard timeout");
    $fatal(1);
  end

endmodule : tb_video
