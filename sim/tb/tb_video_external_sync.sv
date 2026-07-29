// -----------------------------------------------------------------------------
// tb_video_external_sync.sv
//
// Cycle-level regression for User's Guide §9.9 external synchronization:
//   * active-low asynchronous inputs clear their counters on the third VCLK
//     update edge after assertion (the specified 2.5-clock sample delay);
//   * external HSYNC starts a line and advances VCOUNT when HSD=0;
//   * HSD=1 ignores the HSYNC input and retains internal horizontal timing;
//   * VSYNC remains an input throughout external mode and clears VCOUNT
//     without disturbing HCOUNT;
//   * HTOTAL/VTOTAL provide missing-sync fallbacks;
//   * external interlace discriminates odd/even fields from the recognition-
//     edge HCOUNT window; and
//   * DXV/HSD produce the architected synchronization-pin directions.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_video_external_sync;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic [15:0] htotal;
  logic [15:0] vtotal;
  logic        noninterlaced;
  logic        disable_external_video;
  logic        hsync_direction;
  logic        hsync_n_i;
  logic        vsync_n_i;
  logic        hcount_load;
  logic [15:0] hcount_wdata;
  logic        vcount_load;
  logic [15:0] vcount_wdata;
  logic [15:0] hcount;
  logic [15:0] vcount;
  logic        hsync;
  logic        vsync;
  logic        hblank;
  logic        vblank;
  logic        blank;
  logic        hsync_oe;
  logic        vsync_oe;
  logic        odd_field;

  int unsigned failures;

  tms34010_video u_dut (
    .clk            (clk),
    .rst            (rst),
    .hesync         (16'd1),
    .heblnk         (16'd2),
    .hsblnk         (16'd6),
    .htotal         (htotal),
    .vesync         (16'd1),
    .veblnk         (16'd2),
    .vsblnk         (16'd8),
    .vtotal         (vtotal),
    .dpyint         (16'd4),
    .display_enable (1'b1),
    .noninterlaced  (noninterlaced),
    .disable_external_video(disable_external_video),
    .hsync_direction(hsync_direction),
    .hsync_n_i      (hsync_n_i),
    .vsync_n_i      (vsync_n_i),
    .hcount_load    (hcount_load),
    .hcount_wdata   (hcount_wdata),
    .vcount_load    (vcount_load),
    .vcount_wdata   (vcount_wdata),
    .hcount         (hcount),
    .vcount         (vcount),
    .hsync          (hsync),
    .vsync          (vsync),
    .hblank         (hblank),
    .vblank         (vblank),
    .blank          (blank),
    .hsync_oe       (hsync_oe),
    .vsync_oe       (vsync_oe),
    .hblank_start   (),
    .dpyint_pulse   (),
    .odd_field      (odd_field)
  );

  task automatic fail(input string message);
    begin
      $display("TEST_RESULT: FAIL: %s (H=%0d V=%0d odd=%0b)",
               message, hcount, vcount, odd_field);
      failures++;
    end
  endtask

  task automatic check(
    input logic condition,
    input string message
  );
    begin
      if (!condition)
        fail(message);
    end
  endtask

  task automatic load_counts(
    input logic [15:0] horizontal,
    input logic [15:0] vertical
  );
    begin
      @(negedge clk);
      hcount_load  = 1'b1;
      hcount_wdata = horizontal;
      vcount_load  = 1'b1;
      vcount_wdata = vertical;
      @(negedge clk);
      check(hcount == horizontal, "HCOUNT load");
      check(vcount == vertical, "VCOUNT load");
      hcount_load = 1'b0;
      vcount_load = 1'b0;
    end
  endtask

  task automatic rearm_hsync;
    begin
      hsync_n_i = 1'b1;
      repeat (3) @(negedge clk);
    end
  endtask

  task automatic rearm_vsync;
    begin
      vsync_n_i = 1'b1;
      repeat (3) @(negedge clk);
    end
  endtask

  initial begin : main
    logic [15:0] expected_hcount;
    logic [15:0] held_vcount;

    failures               = 0;
    htotal                 = 16'h7FFF;
    vtotal                 = 16'h7FFF;
    noninterlaced          = 1'b1;
    disable_external_video = 1'b0;
    hsync_direction        = 1'b0;
    hsync_n_i              = 1'b1;
    vsync_n_i              = 1'b1;
    hcount_load            = 1'b0;
    hcount_wdata           = 16'h0000;
    vcount_load            = 1'b0;
    vcount_wdata           = 16'h0000;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;

    check(!hsync_oe, "DXV=0 HSD=0 did not select HSYNC input");
    check(!vsync_oe, "DXV=0 did not select VSYNC input");

    // The transition is presented before the next active update edge.
    // Neither of the first two edges may clear HCOUNT; the third must clear
    // it and advance VCOUNT exactly once.
    load_counts(16'd9, 16'd4);
    expected_hcount = 16'd9;
    held_vcount     = 16'd4;
    hsync_n_i       = 1'b0;
    repeat (2) begin
      @(negedge clk);
      expected_hcount++;
      check(hcount == expected_hcount,
            "external HSYNC cleared HCOUNT before 2.5-clock delay");
      check(vcount == held_vcount,
            "external HSYNC advanced VCOUNT before recognition");
    end
    @(negedge clk);
    check(hcount == 16'd0, "external HSYNC did not clear HCOUNT");
    check(vcount == held_vcount + 16'd1,
          "external HSYNC did not advance VCOUNT");
    rearm_hsync();

    // HTOTAL remains a safety limit when an external pulse is absent.
    htotal = 16'd12;
    load_counts(16'd12, 16'd7);
    @(negedge clk);
    check(hcount == 16'd0, "external-mode HTOTAL fallback");
    check(vcount == 16'd8, "HTOTAL fallback did not advance VCOUNT");

    // At the fallback line boundary, VTOTAL independently limits VCOUNT.
    vtotal = 16'd8;
    load_counts(16'd12, 16'd8);
    @(negedge clk);
    check(hcount == 16'd0, "combined fallback did not clear HCOUNT");
    check(vcount == 16'd0, "external-mode VTOTAL fallback");
    check(!odd_field, "fallback did not recover the even field");

    // With HSD=1, horizontal timing is output/free-running and the external
    // HSYNC input must be ignored. VSYNC remains an input.
    htotal          = 16'h7FFF;
    vtotal          = 16'h7FFF;
    hsync_direction = 1'b1;
    @(negedge clk);
    check(hsync_oe, "DXV=0 HSD=1 did not select HSYNC output");
    check(!vsync_oe, "external mode unexpectedly drove VSYNC");
    load_counts(16'd20, 16'd9);
    hsync_n_i = 1'b0;
    repeat (3) @(negedge clk);
    check(hcount == 16'd23, "HSD=1 consumed external HSYNC");
    check(vcount == 16'd9, "HSD=1 external HSYNC advanced VCOUNT");
    rearm_hsync();

    // External VSYNC clears only VCOUNT after the same exact delay. In
    // interlaced mode, HCOUNT inside HEBLNK < HCOUNT <= HSBLNK denotes odd.
    noninterlaced = 1'b0;
    load_counts(16'd3, 16'd11);
    expected_hcount = 16'd3;
    vsync_n_i = 1'b0;
    repeat (2) begin
      @(negedge clk);
      expected_hcount++;
      check(vcount == 16'd11,
            "external VSYNC cleared VCOUNT before 2.5-clock delay");
    end
    @(negedge clk);
    expected_hcount++;
    check(hcount == expected_hcount,
          "external VSYNC disturbed HCOUNT");
    check(vcount == 16'd0, "external VSYNC did not clear VCOUNT");
    check(odd_field, "visible HCOUNT window did not classify odd field");
    rearm_vsync();

    // A sync recognized outside that window selects the even field.
    load_counts(16'd7, 16'd13);
    vsync_n_i = 1'b0;
    repeat (3) @(negedge clk);
    check(vcount == 16'd0, "second external VSYNC did not clear VCOUNT");
    check(!odd_field, "outside HCOUNT window did not classify even field");
    rearm_vsync();

    // NIL suppresses field distinction even for an odd-positioned input.
    noninterlaced = 1'b1;
    load_counts(16'd3, 16'd15);
    vsync_n_i = 1'b0;
    repeat (3) @(negedge clk);
    check(!odd_field, "NIL=1 retained external odd field");
    rearm_vsync();

    disable_external_video = 1'b1;
    hsync_direction        = 1'b0;
    @(negedge clk);
    check(hsync_oe, "DXV=1 did not drive HSYNC");
    check(vsync_oe, "DXV=1 did not drive VSYNC");

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (external sync: delay, direction, fallbacks, fields)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_video_external_sync hard timeout");
    $fatal(1);
  end

endmodule : tb_video_external_sync

`default_nettype wire
