// -----------------------------------------------------------------------------
// tb_io_interrupts.sv
//
// Direct register-boundary regression for the source-specific INTENB,
// INTPEND, and HSTCTLL rules in the 1988 User's Guide pages 6-36 through
// 6-42. Covers synchronized active-low external levels, read-only pending
// bits, hardware-set/write-zero-to-clear internal latches, coincident set
// priority, host INTIN reflection/clear, and reserved INTENB bits.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_io_interrupts;
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
  logic [15:0]           intenb;
  logic [15:0]           intpend;
  logic [15:0]           hstctlh;
  logic                  nmi_clear;
  logic                  wvp_set;
  logic                  dpyint_set;
  logic                  host_req;
  logic                  host_we;
  logic [1:0]            host_be;
  logic [15:0]           host_wdata;
  logic                  host_ack;
  logic                  lint1_n;
  logic                  lint2_n;

  localparam logic [ADDR_WIDTH-1:0] A_HSTCTLL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HSTCTLL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_INTENB =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_INTENB) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_INTPEND =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_INTPEND) << 4);
  localparam logic [15:0] DI_MASK = 16'h0001 << INT_DI_BIT;
  localparam logic [15:0] WV_MASK = 16'h0001 << INT_WV_BIT;
  localparam logic [15:0] X1_MASK = 16'h0001 << INT_X1_BIT;
  localparam logic [15:0] X2_MASK = 16'h0001 << INT_X2_BIT;
  localparam logic [15:0] HI_MASK = 16'h0001 << INT_HI_BIT;

  tms34010_io_regs u_dut (
    .clk         (clk), .vclk_i(clk),
    .rst         (rst),
    .hcs_n_i     (1'b0),
    .host_req_i  (host_req),
    .host_we_i   (host_we),
    .host_reg_i  (HOST_REG_HSTCTL),
    .host_be_i   (host_be),
    .host_wdata_i(host_wdata),
    .host_rdata_o(),
    .host_ack_o  (host_ack),
    .host_busy_o (),
    .hint_n_o    (),
    .hlt_o       (),
    .host_mem_req_o(),
    .host_mem_we_o(),
    .host_mem_addr_o(),
    .host_mem_wdata_o(),
    .host_mem_rdata_i(16'h0000),
    .host_mem_ack_i(1'b0),
    .req         (req),
    .we          (we),
    .addr        (addr),
    .wdata       (wdata),
    .rdata       (rdata),
    .is_io       (is_io),
    .psize_o     (),
    .convdp_o    (),
    .convsp_o    (),
    .control_o   (),
    .pmask_o     (),
    .intenb_o    (intenb),
    .intpend_o   (intpend),
    .hstctlh_o   (hstctlh),
    .refcnt_o    (),
    .refresh_req_o(),
    .refresh_row_o(),
    .refresh_cbr_o(),
    .hcount_o    (),
    .vcount_o    (),
    .video_hsync_o(),
    .video_vsync_o(),
    .video_hblank_o(),
    .video_vblank_o(),
    .video_blank_o(),
    .dpyadr_o    (),
    .screen_refresh_req_o(),
    .screen_refresh_ack_i(1'b0),
    .screen_refresh_srfaddr_o(),
    .screen_refresh_dpytap_o(),
    .nmi_clear   (nmi_clear),
    .wvp_set     (wvp_set),
    .dpyint_set  (dpyint_set),
    .lint1_n_i   (lint1_n),
    .lint2_n_i   (lint2_n)
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

  task automatic host_write(input logic [15:0] write_data);
    begin
      @(negedge clk);
      host_req   = 1'b1;
      host_we    = 1'b1;
      host_be    = 2'b11;
      host_wdata = write_data;
      while (!host_ack) begin
        @(posedge clk);
        #1;
      end
      @(negedge clk);
      host_req = 1'b0;
      host_we  = 1'b0;
      host_be  = 2'b00;
      @(posedge clk);
      #1;
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

  task automatic pulse_source(
    ref logic source
  );
    begin
      @(negedge clk);
      source = 1'b1;
      @(negedge clk);
      source = 1'b0;
    end
  endtask

  initial begin : main
    failures     = 0;
    req          = 1'b0;
    we           = 1'b0;
    addr         = A_INTPEND;
    wdata        = 16'h0000;
    nmi_clear    = 1'b0;
    wvp_set      = 1'b0;
    dpyint_set   = 1'b0;
    host_req       = 1'b0;
    host_we        = 1'b0;
    host_be        = 2'b00;
    host_wdata     = 16'h0000;
    lint1_n      = 1'b1;
    lint2_n      = 1'b1;

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    check_value("reset pending", intpend, 16'h0000);

    // Only architected enable bits are writable.
    io_write(A_INTENB, 16'hFFFF);
    check_value("INTENB reserved bits", intenb, INT_SOURCE_MASK);

    // Active-low LINT pins pass through two destination-clock flops. Their
    // pending bits are level-sensitive and cannot be changed by a write.
    @(negedge clk);
    lint1_n = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    check_value("LINT1 synchronized active", intpend & X1_MASK, X1_MASK);
    io_write(A_INTPEND, 16'h0000);
    check_value("X1P write ignored", intpend & X1_MASK, X1_MASK);

    @(negedge clk);
    lint2_n = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    check_value("LINT2 synchronized active", intpend & (X1_MASK | X2_MASK),
                X1_MASK | X2_MASK);

    @(negedge clk);
    lint1_n = 1'b1;
    lint2_n = 1'b1;
    repeat (2) @(posedge clk);
    #1;
    check_value("external levels released", intpend & (X1_MASK | X2_MASK),
                16'h0000);

    // Internal pending bits latch hardware events. A written one preserves,
    // while a written zero clears. The two latches clear independently.
    pulse_source(dpyint_set);
    pulse_source(wvp_set);
    check_value("DIP/WVP hardware set", intpend & (DI_MASK | WV_MASK),
                DI_MASK | WV_MASK);
    io_write(A_INTPEND, 16'hFFFF);
    check_value("written ones retain DIP/WVP", intpend & (DI_MASK | WV_MASK),
                DI_MASK | WV_MASK);
    io_write(A_INTPEND, WV_MASK);
    check_value("zero clears DIP only", intpend & (DI_MASK | WV_MASK),
                WV_MASK);

    // A same-cycle hardware event wins over a processor clear.
    @(negedge clk);
    req     = 1'b1;
    we      = 1'b1;
    addr    = A_INTPEND;
    wdata   = 16'h0000;
    wvp_set = 1'b1;
    @(negedge clk);
    req     = 1'b0;
    we      = 1'b0;
    wvp_set = 1'b0;
    check_value("same-cycle WVP set wins", intpend & WV_MASK, WV_MASK);
    io_write(A_INTPEND, 16'h0000);
    check_value("DIP/WVP cleared", intpend & (DI_MASK | WV_MASK), 16'h0000);

    // HIP is the read-only copy of HSTCTLL.INTIN. A host set latches it;
    // INTPEND writes do nothing; the processor clears it through HSTCTLL.
    host_write(16'h0008);
    check_value("host INTIN reflected as HIP", intpend & HI_MASK, HI_MASK);
    io_write(A_INTPEND, 16'h0000);
    check_value("HIP INTPEND write ignored", intpend & HI_MASK, HI_MASK);
    io_write(A_HSTCTLL, 16'h0000);
    check_value("processor clears INTIN/HIP", intpend & HI_MASK, 16'h0000);

    // Processor may write MSGOUT and set (but not clear) INTOUT.
    io_write(A_HSTCTLL, 16'h00D0);
    addr = A_HSTCTLL;
    #1;
    check_value("HSTCTLL MSGOUT/INTOUT write", rdata, 16'h00D0);
    io_write(A_HSTCTLL, 16'h0000);
    addr = A_HSTCTLL;
    #1;
    check_value("processor cannot clear INTOUT", rdata, 16'h0080);

    addr = A_INTPEND;
    #1;
    check_value("INTPEND read matches tap", rdata, intpend);

    if (failures == 0)
      $display("TEST_RESULT: PASS (I/O interrupt sources: synchronized levels, RO bits, set/clear latches, HIP)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_io_interrupts hard timeout");
    $fatal(1);
  end

endmodule : tb_io_interrupts
