// -----------------------------------------------------------------------------
// tb_io_video.sv
//
// Same-clock functional integration regression for the Chapter 6 video I/O
// registers and tms34010_video. Programs a compact noninterlaced frame,
// observes live writable HCOUNT/VCOUNT and timing outputs, and verifies that
// DPYCTL.ENV gates BLANK plus the hardware-set/write-zero-clear DIP latch.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_io_video;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

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
  localparam logic [15:0] ENV_MASK = 16'h0001 << DPYCTL_ENV_BIT;
  localparam logic [15:0] DIP_MASK = 16'h0001 << INT_DI_BIT;

  tms34010_io_regs u_dut (
    .clk           (clk),
    .rst           (rst),
    .req           (req),
    .we            (we),
    .addr          (addr),
    .wdata         (wdata),
    .rdata         (rdata),
    .is_io         (is_io),
    .psize_o       (),
    .convdp_o      (),
    .convsp_o      (),
    .control_o     (),
    .pmask_o       (),
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
    .nmi_clear     (1'b0),
    .wvp_set       (1'b0),
    .dpyint_set    (1'b0),
    .host_int_set  (1'b0),
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

  initial begin : main
    failures = 0;
    req      = 1'b0;
    we       = 1'b0;
    addr     = A_HCOUNT;
    wdata    = 16'h0000;

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
    io_write(A_VTOTAL, 16'd3);
    io_write(A_DPYINT, 16'd2);

    // Writes address the live counter owners, not stale io_reg mirrors.
    io_write(A_VCOUNT, 16'd2);
    addr = A_VCOUNT;
    #1;
    check_value("live VCOUNT processor write/read", rdata, 16'd2);
    io_write(A_HCOUNT, 16'd4);
    addr = A_HCOUNT;
    #1;
    check_value("live HCOUNT processor write/read", rdata, 16'd4);

    // ENV=0 continues counting but forces BLANK and inhibits DIP even when
    // the counters cross the selected HSBLNK/VCOUNT compare.
    repeat (4) @(negedge clk);
    check_bit("disabled video remains blanked", blank, 1'b1);
    check_value("disabled video did not set DIP", intpend & DIP_MASK, 16'h0000);

    // Enable video, position one count before horizontal blanking on the
    // selected line, and allow the registered pending latch to sample the
    // generated compare pulse.
    io_write(A_DPYCTL, ENV_MASK);
    io_write(A_VCOUNT, 16'd2);
    io_write(A_HCOUNT, 16'd5);
    @(negedge clk);
    check_value("counter reached HSBLNK", hcount, 16'd6);
    check_bit("HSBLNK equality precedes output blank transition", hblank, 1'b0);
    @(negedge clk);
    check_bit("count after HSBLNK asserts horizontal blank", hblank, 1'b1);
    check_value("HBLANK compare set DIP", intpend & DIP_MASK, DIP_MASK);

    // A processor zero clears the latch. Disabling video before recreating
    // the same compare prevents it from being set again.
    io_write(A_INTPEND, 16'h0000);
    check_value("processor cleared DIP", intpend & DIP_MASK, 16'h0000);
    io_write(A_DPYCTL, 16'h0000);
    io_write(A_VCOUNT, 16'd2);
    io_write(A_HCOUNT, 16'd5);
    repeat (2) @(negedge clk);
    check_bit("disabled compare forces BLANK", blank, 1'b1);
    check_value("disabled compare leaves DIP clear",
                intpend & DIP_MASK, 16'h0000);

    // Reload a visible coordinate to exercise the integrated output windows.
    io_write(A_DPYCTL, ENV_MASK);
    io_write(A_VCOUNT, 16'd2);
    io_write(A_HCOUNT, 16'd4);
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
