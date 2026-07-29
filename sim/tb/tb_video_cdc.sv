// -----------------------------------------------------------------------------
// tb_video_cdc.sv
//
// Focused non-integer-clock regression for the dedicated VCLK subsystem.
// Proves atomic/coalesced configuration, coalesced live-register commands,
// coherent returned snapshots, lossless display interrupts, and a bundled
// held screen-refresh transaction through arbitrary core-domain wait states.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps
`default_nettype none

module tb_video_cdc;
  import tms34010_pkg::*;

  logic core_clk = 1'b0;
  logic video_clk = 1'b0;
  logic rst = 1'b1;

  always #7 core_clk = ~core_clk;
  always #5 video_clk = ~video_clk;

  logic [15:0] hesync;
  logic [15:0] heblnk;
  logic [15:0] hsblnk;
  logic [15:0] htotal;
  logic [15:0] vesync;
  logic [15:0] veblnk;
  logic [15:0] vsblnk;
  logic [15:0] vtotal;
  logic [15:0] dpyint;
  logic [15:0] dpystart;
  logic [15:0] dpyctl;
  logic [15:0] dpytap;
  logic        config_write;

  logic        hcount_write;
  logic [15:0] hcount_wdata;
  logic        vcount_write;
  logic [15:0] vcount_wdata;
  logic        dpyadr_write;
  logic [15:0] dpyadr_wdata;

  logic [15:0] hcount;
  logic [15:0] vcount;
  logic [15:0] dpyadr;
  logic        dpyint_pulse;
  logic        hsync;
  logic        vsync;
  logic        hblank;
  logic        vblank;
  logic        blank;

  logic        screen_req;
  logic        screen_ack;
  logic [13:0] screen_srfaddr;
  logic [15:0] screen_dpytap;
  logic        screen_org;

  integer errors = 0;
  integer dip_pulse_count = 0;

  localparam logic [15:0] ENV_MASK =
      16'h0001 << DPYCTL_ENV_BIT;
  localparam logic [15:0] SRE_MASK =
      16'h0001 << DPYCTL_SRE_BIT;

  tms34010_video_subsystem dut (
    .core_clk_i       (core_clk),
    .core_rst_i       (rst),
    .video_clk_i      (video_clk),
    .video_rst_i      (rst),
    .hesync_i         (hesync),
    .heblnk_i         (heblnk),
    .hsblnk_i         (hsblnk),
    .htotal_i         (htotal),
    .vesync_i         (vesync),
    .veblnk_i         (veblnk),
    .vsblnk_i         (vsblnk),
    .vtotal_i         (vtotal),
    .dpyint_i         (dpyint),
    .dpystart_i       (dpystart),
    .dpyctl_i         (dpyctl),
    .dpytap_i         (dpytap),
    .config_write_i   (config_write),
    .hcount_write_i   (hcount_write),
    .hcount_wdata_i   (hcount_wdata),
    .vcount_write_i   (vcount_write),
    .vcount_wdata_i   (vcount_wdata),
    .dpyadr_write_i   (dpyadr_write),
    .dpyadr_wdata_i   (dpyadr_wdata),
    .hcount_o         (hcount),
    .vcount_o         (vcount),
    .dpyadr_o         (dpyadr),
    .dpyint_pulse_o   (dpyint_pulse),
    .hsync_o          (hsync),
    .vsync_o          (vsync),
    .hblank_o         (hblank),
    .vblank_o         (vblank),
    .blank_o          (blank),
    .screen_req_o     (screen_req),
    .screen_ack_i     (screen_ack),
    .screen_srfaddr_o (screen_srfaddr),
    .screen_dpytap_o  (screen_dpytap),
    .screen_org_o     (screen_org)
  );

  always_ff @(posedge core_clk) begin
    if (rst) begin
      dip_pulse_count <= 0;
    end else if (dpyint_pulse) begin
      dip_pulse_count <= dip_pulse_count + 1;
    end
  end

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $display("CHECK_FAIL: %s at t=%0t hc=%04h vc=%04h da=%04h",
                 message, $time, hcount, vcount, dpyadr);
        errors = errors + 1;
      end
    end
  endtask

  task automatic pulse_config;
    begin
      @(negedge core_clk);
      config_write = 1'b1;
      @(negedge core_clk);
      config_write = 1'b0;
    end
  endtask

  task automatic write_hcount(input logic [15:0] value);
    begin
      @(negedge core_clk);
      hcount_wdata = value;
      hcount_write = 1'b1;
      @(negedge core_clk);
      hcount_write = 1'b0;
    end
  endtask

  task automatic write_vcount(input logic [15:0] value);
    begin
      @(negedge core_clk);
      vcount_wdata = value;
      vcount_write = 1'b1;
      @(negedge core_clk);
      vcount_write = 1'b0;
    end
  endtask

  task automatic write_dpyadr(input logic [15:0] value);
    begin
      @(negedge core_clk);
      dpyadr_wdata = value;
      dpyadr_write = 1'b1;
      @(negedge core_clk);
      dpyadr_write = 1'b0;
    end
  endtask

  task automatic wait_video_config(input logic [15:0] expected_htotal);
    integer watchdog;
    begin
      watchdog = 0;
      while ((dut.config_video_q.htotal != expected_htotal)
             && (watchdog < 100)) begin
        @(posedge video_clk);
        watchdog = watchdog + 1;
      end
      check(dut.config_video_q.htotal == expected_htotal,
            "configuration did not reach VCLK");
    end
  endtask

  initial begin : main
    integer watchdog;
    logic [13:0] held_srfaddr;
    logic [15:0] held_dpytap;
    logic        held_org;

    hesync       = 16'h0000;
    heblnk       = 16'h0000;
    hsblnk       = 16'h0000;
    htotal       = 16'h0000;
    vesync       = 16'h0000;
    veblnk       = 16'h0000;
    vsblnk       = 16'h0000;
    vtotal       = 16'h0000;
    dpyint       = 16'h0000;
    dpystart     = 16'h0000;
    dpyctl       = 16'h0000;
    dpytap       = 16'h0000;
    config_write = 1'b0;
    hcount_write = 1'b0;
    hcount_wdata = 16'h0000;
    vcount_write = 1'b0;
    vcount_wdata = 16'h0000;
    dpyadr_write = 1'b0;
    dpyadr_wdata = 16'h0000;
    screen_ack   = 1'b0;

    repeat (6) @(posedge core_clk);
    repeat (3) @(posedge video_clk);
    @(negedge core_clk);
    rst = 1'b0;

    // Launch one snapshot, then rewrite every field while that transfer is
    // outstanding. The later dirty snapshot must arrive atomically.
    hesync   = 16'h0101;
    heblnk   = 16'h0202;
    hsblnk   = 16'h0303;
    htotal   = 16'h0404;
    vesync   = 16'h0505;
    veblnk   = 16'h0606;
    vsblnk   = 16'h0707;
    vtotal   = 16'h0808;
    dpyint   = 16'h0909;
    dpystart = 16'h0A0A;
    dpyctl   = 16'h0B08;
    dpytap   = 16'h0C0C;
    pulse_config();
    wait (dut.config_accept);

    hesync   = 16'h1111;
    heblnk   = 16'h2222;
    hsblnk   = 16'h3333;
    htotal   = 16'h7FFF;
    vesync   = 16'h5555;
    veblnk   = 16'h6666;
    vsblnk   = 16'h7777;
    vtotal   = 16'h8888;
    dpyint   = 16'h9999;
    dpystart = 16'hAAAA;
    dpyctl   = 16'h1001;
    dpytap   = 16'h1234;
    pulse_config();
    wait_video_config(16'h7FFF);
    @(negedge video_clk);
    check(dut.config_video_q.hesync == 16'h1111,
          "atomic config HESYNC");
    check(dut.config_video_q.heblnk == 16'h2222,
          "atomic config HEBLNK");
    check(dut.config_video_q.hsblnk == 16'h3333,
          "atomic config HSBLNK");
    check(dut.config_video_q.vesync == 16'h5555,
          "atomic config VESYNC");
    check(dut.config_video_q.veblnk == 16'h6666,
          "atomic config VEBLNK");
    check(dut.config_video_q.vsblnk == 16'h7777,
          "atomic config VSBLNK");
    check(dut.config_video_q.vtotal == 16'h8888,
          "atomic config VTOTAL");
    check(dut.config_video_q.dpyint == 16'h9999,
          "atomic config DPYINT");
    check(dut.config_video_q.dpystart == 16'hAAAA,
          "atomic config DPYSTRT");
    check(dut.config_video_q.dpyctl == 16'h1001,
          "atomic config DPYCTL");
    check(dut.config_video_q.dpytap == 16'h1234,
          "atomic config DPYTAP");

    // Fill the command mailbox, then write all three live owners while the
    // first command is in flight. The pending command retains distinct flags
    // and the latest value for each owner.
    write_hcount(16'h0004);
    wait (dut.command_accept);
    write_hcount(16'h0009);
    write_vcount(16'h0002);
    write_dpyadr(16'h4803);

    watchdog = 0;
    while (((dut.vcount_video != 16'h0002)
            || (dut.dpyadr_video != 16'h4803)
            || (dut.hcount_video < 16'h0009))
           && (watchdog < 200)) begin
      @(posedge video_clk);
      watchdog = watchdog + 1;
    end
    check(dut.vcount_video == 16'h0002,
          "coalesced VCOUNT command");
    check(dut.dpyadr_video == 16'h4803,
          "coalesced DPYADR command");
    check(dut.hcount_video >= 16'h0009,
          "latest coalesced HCOUNT command");

    watchdog = 0;
    while (((vcount != 16'h0002) || (dpyadr != 16'h4803))
           && (watchdog < 200)) begin
      @(posedge core_clk);
      watchdog = watchdog + 1;
    end
    check(vcount == 16'h0002,
          "coherent core VCOUNT snapshot");
    check(dpyadr == 16'h4803,
          "coherent core DPYADR snapshot");

    // Compact frame for an exact one-event DIP test and the first active-line
    // screen request.
    hesync   = 16'd2;
    heblnk   = 16'd3;
    hsblnk   = 16'd6;
    htotal   = 16'd7;
    vesync   = 16'd1;
    veblnk   = 16'd1;
    vsblnk   = 16'd14;
    vtotal   = 16'd15;
    dpyint   = 16'd2;
    dpystart = 16'h0003;
    dpyctl   = ENV_MASK;
    dpytap   = 16'h1234;
    pulse_config();
    wait_video_config(16'd7);

    write_hcount(16'd5);
    write_vcount(16'd2);
    watchdog = 0;
    while ((dip_pulse_count == 0) && (watchdog < 100)) begin
      @(posedge core_clk);
      watchdog = watchdog + 1;
    end
    check(dip_pulse_count == 1,
          "one-VCLK DIP event was not delivered exactly once");
    @(posedge core_clk);
    check(!dpyint_pulse, "DIP destination pulse wider than one core clock");

    // Enable automatic screen refresh and place the live owners immediately
    // before the first-active-line HBLANK event.
    dpyctl = ENV_MASK | SRE_MASK | 16'h0004;
    pulse_config();
    wait_video_config(16'd7);
    write_dpyadr(16'h4800);
    write_hcount(16'd5);
    write_vcount(16'd1);

    watchdog = 0;
    while (!screen_req && (watchdog < 200)) begin
      @(posedge core_clk);
      watchdog = watchdog + 1;
    end
    check(screen_req, "screen request did not cross into core domain");
    held_srfaddr = screen_srfaddr;
    held_dpytap  = screen_dpytap;
    held_org     = screen_org;
    check(held_srfaddr == 14'h1200,
          "screen SRFADR payload");
    check(held_dpytap == 16'h1234,
          "screen DPYTAP payload");
    check(!held_org, "screen ORG payload");

    repeat (11) begin
      @(posedge core_clk);
      check(screen_req, "screen request dropped during memory wait");
      check(screen_srfaddr == held_srfaddr,
            "screen SRFADR changed during memory wait");
      check(screen_dpytap == held_dpytap,
            "screen DPYTAP changed during memory wait");
      check(screen_org == held_org,
            "screen ORG changed during memory wait");
    end

    @(negedge core_clk);
    screen_ack = 1'b1;
    @(negedge core_clk);
    screen_ack = 1'b0;
    @(posedge core_clk);
    check(!screen_req, "screen request did not retire on core completion");

    watchdog = 0;
    while (!dut.screen_ack_video && (watchdog < 100)) begin
      @(posedge video_clk);
      watchdog = watchdog + 1;
    end
    check(dut.screen_ack_video,
          "screen completion did not return to VCLK");
    @(posedge video_clk);
    @(negedge video_clk);
    check(dut.dpyadr_video[15:2] == 14'h1201,
          "completed screen request did not advance SRFADR");
    check(dut.dpyadr_video[1:0] == 2'b11,
          "completed screen request did not reload LNCNT");

    if (errors == 0) begin
      $display("TEST_RESULT: PASS");
    end else begin
      $display("TEST_RESULT: FAIL (%0d errors)", errors);
    end
    $finish;
  end

  initial begin
    #50000;
    $display("TEST_RESULT: FAIL: timeout");
    $finish;
  end

endmodule : tb_video_cdc

`default_nettype wire
