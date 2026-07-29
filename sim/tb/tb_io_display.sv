// -----------------------------------------------------------------------------
// tb_io_display.sv
//
// I/O-level integration regression for live DPYADR and automatic screen
// refresh. Processor writes configure timing/DPYSTRT/DPYCTL/DPYTAP, video
// counter events schedule a held request, and an explicit completion
// acknowledge advances the processor-visible DPYADR state.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_io_display;
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
  logic [15:0]           dpyadr;
  logic                  screen_req;
  logic                  screen_ack;
  logic [13:0]           screen_srfaddr;
  logic [15:0]           screen_dpytap;

  localparam logic [ADDR_WIDTH-1:0] A_HSBLNK =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HSBLNK) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HTOTAL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HTOTAL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_VEBLNK =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_VEBLNK) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_VSBLNK =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_VSBLNK) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYCTL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYCTL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYSTRT =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYSTRT) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYTAP =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYTAP) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HCOUNT =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HCOUNT) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_VCOUNT =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_VCOUNT) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYADR =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYADR) << 4);
  localparam logic [15:0] SRE_DUDATE1 =
      (16'h0001 << DPYCTL_SRE_BIT)
    | (16'h0001 << DPYCTL_DUDATE_LO);

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
    .intpend_o     (),
    .hstctlh_o     (),
    .refcnt_o      (),
    .refresh_req_o (),
    .refresh_row_o (),
    .refresh_cbr_o (),
    .hcount_o      (),
    .vcount_o      (),
    .video_hsync_o (),
    .video_vsync_o (),
    .video_hblank_o(),
    .video_vblank_o(),
    .video_blank_o (),
    .dpyadr_o      (dpyadr),
    .screen_refresh_req_o(screen_req),
    .screen_refresh_ack_i(screen_ack),
    .screen_refresh_srfaddr_o(screen_srfaddr),
    .screen_refresh_dpytap_o(screen_dpytap),
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

  task automatic position_hblank(input logic [15:0] line);
    begin
      io_write(A_VCOUNT, line);
      io_write(A_HCOUNT, 16'd5);
      // HCOUNT advances to HSBLNK=6 on the first edge and the display
      // scheduler samples that equality on the second.
      repeat (2) @(negedge clk);
    end
  endtask

  task automatic pulse_ack;
    begin
      @(negedge clk);
      screen_ack = 1'b1;
      @(negedge clk);
      screen_ack = 1'b0;
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
    failures  = 0;
    req       = 1'b0;
    we        = 1'b0;
    addr      = A_DPYADR;
    wdata     = 16'h0000;
    screen_ack = 1'b0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    check_value("DPYADR reset", dpyadr, 16'h0000);
    check_bit("screen request reset", screen_req, 1'b0);
    rst = 1'b0;

    // Compact internal/noninterlaced timing. Only HSBLNK/HTOTAL and the
    // vertical active-window boundaries are required by this scheduler test.
    io_write(A_HSBLNK, 16'd6);
    io_write(A_HTOTAL, 16'd7);
    io_write(A_VEBLNK, 16'd1);
    io_write(A_VSBLNK, 16'd3);
    io_write(A_DPYSTRT, {14'h0120, 2'd0});
    io_write(A_DPYTAP, 16'hBEEF);
    addr = A_DPYTAP;
    #1;
    check_value("DPYTAP reserved bits read zero", rdata, 16'h3EEF);

    // DPYADR reads are sourced from the live owner.
    io_write(A_DPYADR, {14'h0200, 2'd2});
    addr = A_DPYADR;
    #1;
    check_value("processor live DPYADR read", rdata, {14'h0200, 2'd2});

    // Frame-start equality reloads SRFADR while preserving LNCNT.
    position_hblank(16'd3);
    check_value("frame reload through video event",
                dpyadr, {14'h0120, 2'd2});
    check_bit("SRE=0 suppresses request", screen_req, 1'b0);

    // Enable automatic refresh and position the first active-line HBLANK.
    // LCSTRT=0 requests every active scan line.
    io_write(A_DPYCTL, SRE_DUDATE1);
    position_hblank(16'd1);
    check_bit("first-active screen request", screen_req, 1'b1);
    check_addr("integrated SRFADR payload", screen_srfaddr, 14'h0120);
    check_value("integrated DPYTAP payload masks reserved bits",
                screen_dpytap, 16'h3EEF);

    // A later DPYTAP write does not perturb the already-held bus payload.
    io_write(A_DPYTAP, 16'hCAFE);
    repeat (3) @(negedge clk);
    check_bit("integrated request held", screen_req, 1'b1);
    check_value("held tap remains stable", screen_dpytap, 16'h3EEF);

    pulse_ack();
    check_bit("integrated ack clears request", screen_req, 1'b0);
    check_value("integrated ack advances live DPYADR",
                dpyadr, {14'h0121, 2'd0});
    addr = A_DPYADR;
    #1;
    check_value("processor reads advanced DPYADR",
                rdata, {14'h0121, 2'd0});

    // LCSTRT=0 schedules the next active line immediately and captures the
    // newly programmed tap value.
    position_hblank(16'd2);
    check_bit("next-line request", screen_req, 1'b1);
    check_addr("next-line SRFADR", screen_srfaddr, 14'h0121);
    check_value("next-line DPYTAP", screen_dpytap, 16'h0AFE);
    pulse_ack();
    check_value("second completion update", dpyadr, {14'h0122, 2'd0});

    if (failures == 0)
      $display("TEST_RESULT: PASS (I/O display: live DPYADR, held screen request, completion update)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_io_display hard timeout");
    $fatal(1);
  end

endmodule : tb_io_display
