// -----------------------------------------------------------------------------
// tb_io_video.sv
//
// I/O integration regression for the Chapter 6 video registers across the
// dedicated VCLK boundary. Programs a compact noninterlaced frame, observes
// coherent live HCOUNT/VCOUNT snapshots and VCLK timing outputs, and verifies
// that DPYCTL.ENV gates BLANK plus the hardware-set/write-zero-clear DIP latch.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_io_video;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic vclk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;
  always #7 vclk = ~vclk;

  logic                  req;
  logic                  we;
  logic [ADDR_WIDTH-1:0] addr;
  logic [15:0]           wdata;
  logic [15:0]           rdata;
  logic                  is_io;
  logic [15:0]           intpend;
  logic [15:0]           hcount;
  logic [15:0]           vcount;
  logic                  hsync;
  logic                  vsync;
  logic                  hblank;
  logic                  vblank;
  logic                  blank;
  logic                  video_hsync_n;
  logic                  video_vsync_n;
  logic                  video_hsync_oe;
  logic                  video_vsync_oe;

  localparam logic [ADDR_WIDTH-1:0] A_HESYNC =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HESYNC) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HEBLNK =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HEBLNK) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HSBLNK =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HSBLNK) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HTOTAL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HTOTAL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_VESYNC =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_VESYNC) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_VEBLNK =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_VEBLNK) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_VSBLNK =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_VSBLNK) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_VTOTAL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_VTOTAL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYCTL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYCTL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYINT =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYINT) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_INTPEND =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_INTPEND) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HCOUNT =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HCOUNT) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_VCOUNT =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_VCOUNT) << 4);
  localparam logic [15:0] INTERNAL_NONINTERLACED =
      (16'h0001 << DPYCTL_DXV_BIT)
    | (16'h0001 << DPYCTL_NIL_BIT);
  localparam logic [15:0] ENABLED_INTERNAL_NONINTERLACED =
      INTERNAL_NONINTERLACED | (16'h0001 << DPYCTL_ENV_BIT);
  localparam logic [15:0] DIP_MASK = 16'h0001 << INT_DI_BIT;

  tms34010_io_regs u_dut (
    .clk           (clk),
    .vclk_i        (vclk),
    .rst           (rst), .vclk_rst_i(rst),
    .video_hsync_n_i(video_hsync_n),
    .video_vsync_n_i(video_vsync_n),
    .video_hsync_oe_o(video_hsync_oe),
    .video_vsync_oe_o(video_vsync_oe),
    .req           (req),
    .we            (we),
    .addr          (addr),
    .req_addr_i    (addr),
    .wdata         (wdata),
    .rdata         (rdata),
    .is_io         (is_io),
    .psize_o       (),
    .convdp_o      (),
    .convsp_o      (),
    .control_o     (),
    .pmask_o       (), .pixel_srt_o(),
    .intenb_o      (),
    .intpend_o     (intpend),
    .hstctlh_o     (),
    .refcnt_o      (),
    .refresh_req_o (),
    .refresh_row_o (),
    .refresh_cbr_o (),
    .hcount_o      (hcount),
    .vcount_o      (vcount),
    .video_hsync_o (hsync),
    .video_vsync_o (vsync),
    .video_hblank_o(hblank),
    .video_vblank_o(vblank),
    .video_blank_o (blank),
    .dpyadr_o      (),
    .screen_refresh_req_o(),
    .screen_refresh_ack_i(1'b0),
    .screen_refresh_srfaddr_o(),
    .screen_refresh_dpytap_o(),
    .screen_refresh_org_o(),
    .nmi_clear     (1'b0),
    .wvp_set       (1'b0),
    .dpyint_set    (1'b0),
    .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_is_io_o(), .host_mem_io_rdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .hlt_o(),
    .lint1_n_i     (1'b1),
    .lint2_n_i     (1'b1)
  );

  int unsigned failures;

  task automatic io_write(
    input logic [ADDR_WIDTH-1:0] write_addr,
    input logic [15:0]           write_data
  );
    begin
      @(negedge clk);
      req   = 1'b1;
      we    = 1'b1;
      addr  = write_addr;
      wdata = write_data;
      @(negedge clk);
      req = 1'b0;
      we  = 1'b0;
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

  task automatic wait_video_config(
    input logic [15:0] expected_dpyctl
  );
    integer watchdog_count;
    begin
      watchdog_count = 0;
      while (((u_dut.u_video_subsystem.config_video_q.htotal != 16'd7)
              || (u_dut.u_video_subsystem.config_video_q.dpyctl
                  != expected_dpyctl))
             && (watchdog_count < 200)) begin
        @(posedge vclk);
        watchdog_count++;
      end
      check_value("video configuration reached VCLK",
                  u_dut.u_video_subsystem.config_video_q.htotal, 16'd7);
      check_value("DPYCTL reached VCLK",
                  u_dut.u_video_subsystem.config_video_q.dpyctl,
                  expected_dpyctl);
    end
  endtask

  task automatic wait_video_position(
    input logic [15:0] expected_hcount,
    input logic [15:0] expected_vcount
  );
    integer watchdog_count;
    begin
      watchdog_count = 0;
      while (((u_dut.u_video_subsystem.hcount_video != expected_hcount)
              || (u_dut.u_video_subsystem.vcount_video != expected_vcount))
             && (watchdog_count < 200)) begin
        @(negedge vclk);
        watchdog_count++;
      end
      check_value("VCLK HCOUNT command",
                  u_dut.u_video_subsystem.hcount_video, expected_hcount);
      check_value("VCLK VCOUNT command",
                  u_dut.u_video_subsystem.vcount_video, expected_vcount);
    end
  endtask

  initial begin : main
    failures = 0;
    req      = 1'b0;
    we       = 1'b0;
    addr     = A_HCOUNT;
    wdata    = 16'h0000;
    video_hsync_n = 1'b1;
    video_vsync_n = 1'b1;

    repeat (3) @(posedge clk);
    @(negedge clk);
    check_value("HCOUNT reset", hcount, 16'h0000);
    check_value("VCOUNT reset", vcount, 16'h0000);
    check_bit("ENV reset forces BLANK", blank, 1'b1);
    rst = 1'b0;

    // Compact 8-pixel x 4-line internal/noninterlaced timing.
    io_write(A_HESYNC, 16'd2);
    io_write(A_HEBLNK, 16'd3);
    io_write(A_HSBLNK, 16'd6);
    io_write(A_HTOTAL, 16'd7);
    io_write(A_VESYNC, 16'd1);
    io_write(A_VEBLNK, 16'd1);
    io_write(A_VSBLNK, 16'd3);
    io_write(A_VTOTAL, 16'd15);
    io_write(A_DPYINT, 16'd2);
    wait_video_config(16'h0000);
    check_bit("external HSD=0 selects HSYNC input", video_hsync_oe, 1'b0);
    check_bit("external mode selects VSYNC input", video_vsync_oe, 1'b0);

    io_write(A_DPYCTL, 16'h0001 << DPYCTL_HSD_BIT);
    wait_video_config(16'h0001 << DPYCTL_HSD_BIT);
    check_bit("external HSD=1 selects HSYNC output", video_hsync_oe, 1'b1);
    check_bit("external HSD=1 leaves VSYNC input", video_vsync_oe, 1'b0);
    io_write(A_DPYCTL, 16'h0000);
    wait_video_config(16'h0000);

    // Writes address the VCLK owners. VCOUNT is stable until a line wrap,
    // while HCOUNT's coherent core snapshot may already have advanced beyond
    // the loaded value by the time the round-trip completes.
    io_write(A_VCOUNT, 16'd2);
    io_write(A_HCOUNT, 16'd4);
    wait_video_position(16'd4, 16'd2);
    wait (vcount == 16'd2);
    addr = A_VCOUNT;
    #1;
    check_value("live VCOUNT processor write/read", rdata, 16'd2);
    addr = A_HCOUNT;
    #1;
    check_value("HCOUNT read uses coherent live snapshot", rdata, hcount);

    // ENV=0 continues counting but forces BLANK and inhibits DIP even when
    // the counters cross the selected HSBLNK/VCOUNT compare.
    repeat (4) @(negedge vclk);
    check_bit("disabled video remains blanked", blank, 1'b1);
    check_value("disabled video did not set DIP", intpend & DIP_MASK, 16'h0000);

    // Enable video, position one count before horizontal blanking on the
    // selected line, and allow the registered pending latch to sample the
    // generated compare pulse.
    io_write(A_DPYCTL, ENABLED_INTERNAL_NONINTERLACED);
    wait_video_config(ENABLED_INTERNAL_NONINTERLACED);
    check_bit("internal mode selects HSYNC output", video_hsync_oe, 1'b1);
    check_bit("internal mode selects VSYNC output", video_vsync_oe, 1'b1);
    io_write(A_VCOUNT, 16'd2);
    io_write(A_HCOUNT, 16'd5);
    wait_video_position(16'd5, 16'd2);
    wait (u_dut.u_video_subsystem.hcount_video == 16'd6);
    @(negedge vclk);
    check_bit("HSBLNK equality precedes output blank transition", hblank, 1'b0);
    wait (u_dut.u_video_subsystem.hcount_video == 16'd7);
    @(negedge vclk);
    check_bit("count after HSBLNK asserts horizontal blank", hblank, 1'b1);
    wait ((intpend & DIP_MASK) != 16'h0000);
    check_value("HBLANK compare set DIP", intpend & DIP_MASK, DIP_MASK);

    // A processor zero clears the latch. Disabling video before recreating
    // the same compare prevents it from being set again.
    io_write(A_DPYCTL, INTERNAL_NONINTERLACED);
    wait_video_config(INTERNAL_NONINTERLACED);
    repeat (8) @(posedge clk);
    io_write(A_INTPEND, 16'h0000);
    check_value("processor cleared DIP", intpend & DIP_MASK, 16'h0000);
    io_write(A_VCOUNT, 16'd2);
    io_write(A_HCOUNT, 16'd5);
    wait_video_position(16'd5, 16'd2);
    repeat (5) @(negedge vclk);
    check_bit("disabled compare forces BLANK", blank, 1'b1);
    check_value("disabled compare leaves DIP clear",
                intpend & DIP_MASK, 16'h0000);

    // Reload a visible coordinate to exercise the integrated output windows.
    io_write(A_DPYCTL, ENABLED_INTERNAL_NONINTERLACED);
    wait_video_config(ENABLED_INTERNAL_NONINTERLACED);
    io_write(A_VCOUNT, 16'd2);
    io_write(A_HCOUNT, 16'd4);
    wait_video_position(16'd4, 16'd2);
    @(negedge vclk);
    check_bit("visible coordinate hsync low", hsync, 1'b0);
    check_bit("visible coordinate vsync low", vsync, 1'b0);
    check_bit("visible coordinate hblank low", hblank, 1'b0);
    check_bit("visible coordinate vblank low", vblank, 1'b0);
    check_bit("visible coordinate BLANK low", blank, 1'b0);

    if (failures == 0)
      $display("TEST_RESULT: PASS (I/O video: live counters, timing outputs, ENV, integrated DIP)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_io_video hard timeout");
    $fatal(1);
  end

endmodule : tb_io_video
