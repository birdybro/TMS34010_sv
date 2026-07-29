// -----------------------------------------------------------------------------
// tb_video_interlace.sv
//
// Cycle-by-cycle regression for the internally generated interlaced timing
// rules in User's Guide §9.6.1.1 and §9.7:
//   * reset starts in the even-field phase;
//   * even-to-odd resets VCOUNT at HTOTAL/2 without resetting HCOUNT;
//   * the odd-field VESYNC half-line compare performs the extra VCOUNT step;
//   * odd-to-even resets both counters at the normal full-line boundary;
//   * vertical timing follows the architected VCOUNT sequence; and
//   * DPYINT=VESYNC is suppressed in the odd field when HSBLNK=HTOTAL/2.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_video_interlace;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  localparam logic [15:0] HESYNC = 16'd0;
  localparam logic [15:0] HEBLNK = 16'd1;
  localparam logic [15:0] HSBLNK = 16'd3;
  localparam logic [15:0] HTOTAL = 16'd7;
  localparam logic [15:0] HALF_LINE = HTOTAL >> 1;
  localparam logic [15:0] VESYNC = 16'd1;
  localparam logic [15:0] VEBLNK = 16'd2;
  localparam logic [15:0] VSBLNK = 16'd6;
  localparam logic [15:0] VTOTAL = 16'd7;
  localparam logic [15:0] DPYINT = VESYNC;

  logic        noninterlaced;
  logic [15:0] hcount;
  logic [15:0] vcount;
  logic        hsync;
  logic        vsync;
  logic        hblank;
  logic        vblank;
  logic        blank;
  logic        hblank_start;
  logic        dpyint_pulse;
  logic        odd_field;

  tms34010_video u_dut (
    .clk            (clk),
    .rst            (rst),
    .hesync         (HESYNC),
    .heblnk         (HEBLNK),
    .hsblnk         (HSBLNK),
    .htotal         (HTOTAL),
    .vesync         (VESYNC),
    .veblnk         (VEBLNK),
    .vsblnk         (VSBLNK),
    .vtotal         (VTOTAL),
    .dpyint         (DPYINT),
    .display_enable (1'b1),
    .noninterlaced  (noninterlaced),
    .disable_external_video(1'b1),
    .hsync_direction(1'b0),
    .hsync_n_i      (1'b1),
    .vsync_n_i      (1'b1),
    .hcount_load    (1'b0),
    .hcount_wdata   (16'h0000),
    .vcount_load    (1'b0),
    .vcount_wdata   (16'h0000),
    .hcount         (hcount),
    .vcount         (vcount),
    .hsync          (hsync),
    .vsync          (vsync),
    .hblank         (hblank),
    .vblank         (vblank),
    .blank          (blank),
    .hsync_oe       (),
    .vsync_oe       (),
    .hblank_start   (hblank_start),
    .dpyint_pulse   (dpyint_pulse),
    .odd_field      (odd_field)
  );

  int unsigned failures;
  int unsigned even_to_odd_count;
  int unsigned odd_sync_step_count;
  int unsigned odd_to_even_count;
  int unsigned even_dpyint_count;

  logic [15:0] expected_hcount;
  logic [15:0] expected_vcount;
  logic        expected_odd_field;

  task automatic fail(input string message);
    begin
      $display("TEST_RESULT: FAIL: %s (H=%0d V=%0d odd=%0b)",
               message, hcount, vcount, odd_field);
      failures++;
    end
  endtask

  task automatic check_cycle;
    logic [15:0] old_hcount;
    logic [15:0] old_vcount;
    logic        old_odd_field;
    begin
      old_hcount   = expected_hcount;
      old_vcount   = expected_vcount;
      old_odd_field = expected_odd_field;

      if (old_hcount == HTOTAL)
        expected_hcount = 16'd0;
      else
        expected_hcount = old_hcount + 16'd1;

      if (!old_odd_field
          && (old_vcount == VTOTAL)
          && (old_hcount == HALF_LINE)) begin
        expected_vcount   = 16'd0;
        expected_odd_field = 1'b1;
        even_to_odd_count++;
      end else if (old_odd_field
                   && (old_vcount == VESYNC)
                   && (old_hcount == HALF_LINE)) begin
        expected_vcount = old_vcount + 16'd1;
        odd_sync_step_count++;
      end else if (old_hcount == HTOTAL) begin
        if (old_vcount == VTOTAL) begin
          expected_vcount   = 16'd0;
          expected_odd_field = 1'b0;
          if (old_odd_field)
            odd_to_even_count++;
        end else begin
          expected_vcount = old_vcount + 16'd1;
        end
      end

      @(negedge clk);

      if (hcount !== expected_hcount)
        fail("horizontal counter sequence");
      if (vcount !== expected_vcount)
        fail("interlaced vertical counter sequence");
      if (odd_field !== expected_odd_field)
        fail("field phase sequence");
      if (hsync !== (hcount <= HESYNC))
        fail("horizontal sync interval");
      if (hblank !== ((hcount <= HEBLNK) || (hcount > HSBLNK)))
        fail("horizontal blank interval");
      if (vsync !== (vcount <= VESYNC))
        fail("vertical sync follows interlaced VCOUNT");
      if (vblank !== ((vcount <= VEBLNK) || (vcount > VSBLNK)))
        fail("vertical blank follows interlaced VCOUNT");
      if (blank !== (hblank || vblank))
        fail("combined blank interval");
      if (hblank_start !== (hcount == HSBLNK))
        fail("horizontal blank-start compare");

      if (dpyint_pulse) begin
        if (odd_field)
          fail("odd-field VESYNC display interrupt was not suppressed");
        else
          even_dpyint_count++;
      end

      if (old_odd_field && (old_vcount == VESYNC)
          && (old_hcount == HALF_LINE)) begin
        if (hcount !== (HALF_LINE + 16'd1))
          fail("odd-field sync step reset HCOUNT");
        if (vsync)
          fail("odd-field half-line step did not end VSYNC");
      end

      if (!old_odd_field && (old_vcount == VTOTAL)
          && (old_hcount == HALF_LINE)) begin
        if (hcount !== (HALF_LINE + 16'd1))
          fail("even-to-odd boundary reset HCOUNT");
        if (!vsync)
          fail("even-to-odd boundary did not start VSYNC");
      end
    end
  endtask

  initial begin : main
    failures           = 0;
    even_to_odd_count  = 0;
    odd_sync_step_count = 0;
    odd_to_even_count  = 0;
    even_dpyint_count  = 0;
    noninterlaced      = 1'b0;
    expected_hcount    = 16'd0;
    expected_vcount    = 16'd0;
    expected_odd_field = 1'b0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    if (odd_field)
      fail("reset did not select even field");
    rst = 1'b0;

    for (int unsigned cycle = 0; cycle < 320; cycle++)
      check_cycle();

    if (even_to_odd_count < 2)
      fail("too few half-line even-to-odd transitions");
    if (odd_sync_step_count < 2)
      fail("too few odd-field VESYNC increments");
    if (odd_to_even_count < 2)
      fail("too few full-line odd-to-even transitions");
    if (even_dpyint_count < 2)
      fail("DPYINT did not remain available in even fields");

    // A software mode change has a deterministic recovery point: selecting
    // noninterlaced timing clears the stored field phase on the next VCLK.
    while (!odd_field)
      check_cycle();
    noninterlaced = 1'b1;
    @(negedge clk);
    if (odd_field)
      fail("NIL=1 did not return to the even phase");

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (internal interlace: half-line fields, VCOUNT step, DPYINT)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_video_interlace hard timeout");
    $fatal(1);
  end

endmodule : tb_video_interlace
