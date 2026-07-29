// -----------------------------------------------------------------------------
// tb_host_control.sv
//
// Direct register-boundary regression for HSTCTL (1988 User's Guide pages
// 6-31 through 6-37). The synchronous host boundary represents completed
// host-bus cycles; a later pin wrapper supplies asynchronous timing and CDC.
//
// Covers HCS-selected HLT reset state, byte enables, combined host reads,
// per-side MSG/interrupt ownership, active-low HINT, reserved high-byte bits,
// and deterministic producer-wins/simultaneous-high-write arbitration.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_host_control;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                  hcs_n;
  logic                  host_ctl_we;
  logic [1:0]            host_ctl_be;
  logic [15:0]           host_ctl_wdata;
  logic [15:0]           host_ctl_rdata;
  logic                  hint_n;
  logic                  hlt;
  logic                  req;
  logic                  we;
  logic [ADDR_WIDTH-1:0] addr;
  logic [15:0]           wdata;
  logic [15:0]           rdata;
  logic                  is_io;
  logic [15:0]           intpend;
  logic [15:0]           hstctlh;
  logic                  nmi_clear;

  localparam logic [ADDR_WIDTH-1:0] A_HSTCTLL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HSTCTLL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HSTCTLH =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HSTCTLH) << 4);
  localparam logic [15:0] NMI_MASK =
      16'h0001 << HSTCTL_NMI_BIT;
  localparam logic [15:0] HLT_MASK =
      16'h0001 << HSTCTL_HLT_BIT;
  localparam logic [15:0] HIP_MASK =
      16'h0001 << INT_HI_BIT;

  tms34010_io_regs u_dut (
    .clk           (clk),
    .rst           (rst),
    .hcs_n_i       (hcs_n),
    .host_ctl_we_i (host_ctl_we),
    .host_ctl_be_i (host_ctl_be),
    .host_ctl_wdata_i(host_ctl_wdata),
    .host_ctl_rdata_o(host_ctl_rdata),
    .hint_n_o      (hint_n),
    .hlt_o         (hlt),
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
    .hstctlh_o     (hstctlh),
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
    .dpyadr_o      (),
    .screen_refresh_req_o(),
    .screen_refresh_ack_i(1'b0),
    .screen_refresh_srfaddr_o(),
    .screen_refresh_dpytap_o(),
    .nmi_clear     (nmi_clear),
    .wvp_set       (1'b0),
    .dpyint_set    (1'b0),
    .lint1_n_i     (1'b1),
    .lint2_n_i     (1'b1)
  );

  int unsigned failures;

  task automatic host_write(
    input logic [1:0]  byte_enable,
    input logic [15:0] write_data
  );
    begin
      @(negedge clk);
      host_ctl_we    = 1'b1;
      host_ctl_be    = byte_enable;
      host_ctl_wdata = write_data;
      @(negedge clk);
      host_ctl_we = 1'b0;
      host_ctl_be = 2'b00;
    end
  endtask

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

  task automatic check_word(
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
    failures      = 0;
    hcs_n         = 1'b1;
    host_ctl_we   = 1'b0;
    host_ctl_be   = 2'b00;
    host_ctl_wdata = 16'h0000;
    req           = 1'b0;
    we            = 1'b0;
    addr          = A_HSTCTLL;
    wdata         = 16'h0000;
    nmi_clear     = 1'b0;

    repeat (3) @(posedge clk);
    #1;
    check_word("host-present reset HSTCTL", host_ctl_rdata, HLT_MASK);
    check_bit("host-present reset HLT output", hlt, 1'b1);
    check_bit("reset HINT inactive", hint_n, 1'b1);
    rst = 1'b0;

    // High byte is shared by both sides; reserved bits always read zero.
    host_write(2'b10, 16'hFFFF);
    check_word("host high-byte writable mask", host_ctl_rdata,
               HSTCTLH_WRITABLE_MASK);
    check_word("processor HSTCTLH tap matches host read",
               hstctlh, HSTCTLH_WRITABLE_MASK);
    check_bit("host high-byte HLT set", hlt, 1'b1);

    host_write(2'b10, 16'h0000);
    check_word("host clears high byte", host_ctl_rdata, 16'h0000);
    check_bit("host clears HLT", hlt, 1'b0);

    // Host owns MSGIN, sets INTIN with one, cannot modify MSGOUT, and cannot
    // clear INTOUT by writing one.
    host_write(2'b01, 16'h008D);
    check_word("host low ownership", host_ctl_rdata, 16'h000D);
    check_word("host INTIN reflected as HIP",
               intpend & HIP_MASK, HIP_MASK);

    // Processor owns MSGOUT, clears INTIN with zero, and sets INTOUT with one.
    io_write(A_HSTCTLL, 16'h00F0);
    check_word("processor low ownership", host_ctl_rdata, 16'h00F5);
    check_word("processor clears INTIN/HIP",
               intpend & HIP_MASK, 16'h0000);
    check_bit("INTOUT asserts active-low HINT", hint_n, 1'b0);

    // Host changes MSGIN, sets INTIN, and clears INTOUT. Processor MSGOUT
    // remains intact.
    host_write(2'b01, 16'h000B);
    check_word("host complementary low update", host_ctl_rdata, 16'h007B);
    check_word("host re-sets INTIN/HIP", intpend & HIP_MASK, HIP_MASK);
    check_bit("host clears INTOUT/HINT", hint_n, 1'b1);

    // A high-only write cannot disturb the low byte and vice versa.
    host_write(2'b10, 16'h8100);
    check_word("high-only byte enable", host_ctl_rdata, 16'h817B);
    host_write(2'b01, 16'h0086);
    check_word("low-only byte enable", host_ctl_rdata, 16'h817E);

    // Processor high-byte writes receive the same reserved-bit mask.
    io_write(A_HSTCTLH, 16'hFFFF);
    addr = A_HSTCTLH;
    #1;
    check_word("processor high-byte writable mask",
               rdata, HSTCTLH_WRITABLE_MASK);

    // Simultaneous low-byte operations retain the producer's event: host
    // INTIN set wins processor clear, and processor INTOUT set wins host clear.
    @(negedge clk);
    req            = 1'b1;
    we             = 1'b1;
    addr           = A_HSTCTLL;
    wdata          = 16'h0080;
    host_ctl_we    = 1'b1;
    host_ctl_be    = 2'b01;
    host_ctl_wdata = 16'h0008;
    @(negedge clk);
    req         = 1'b0;
    we          = 1'b0;
    host_ctl_we = 1'b0;
    host_ctl_be = 2'b00;
    check_word("simultaneous low producer wins",
               host_ctl_rdata & 16'h0088, 16'h0088);
    check_bit("simultaneous processor INTOUT asserts HINT", hint_n, 1'b0);

    // Original-silicon conflicting high writes are unpredictable. This
    // synchronous boundary deliberately selects the host value.
    @(negedge clk);
    req            = 1'b1;
    we             = 1'b1;
    addr           = A_HSTCTLH;
    wdata          = NMI_MASK;
    host_ctl_we    = 1'b1;
    host_ctl_be    = 2'b10;
    host_ctl_wdata = HLT_MASK;
    @(negedge clk);
    req         = 1'b0;
    we          = 1'b0;
    host_ctl_we = 1'b0;
    host_ctl_be = 2'b00;
    check_word("simultaneous high host priority",
               host_ctl_rdata & 16'hFF00, HLT_MASK);

    // A host NMI set also wins the automatic clear on the same edge.
    @(negedge clk);
    host_ctl_we    = 1'b1;
    host_ctl_be    = 2'b10;
    host_ctl_wdata = NMI_MASK;
    nmi_clear      = 1'b1;
    @(negedge clk);
    host_ctl_we = 1'b0;
    host_ctl_be = 2'b00;
    nmi_clear   = 1'b0;
    check_word("host NMI write wins auto-clear",
               host_ctl_rdata & NMI_MASK, NMI_MASK);

    // Reassert reset with HCS active low: all fields, including HLT, clear.
    @(negedge clk);
    hcs_n = 1'b0;
    rst   = 1'b1;
    repeat (2) @(posedge clk);
    #1;
    check_word("self-bootstrap reset HSTCTL", host_ctl_rdata, 16'h0000);
    check_bit("self-bootstrap reset HLT", hlt, 1'b0);
    check_bit("self-bootstrap reset HINT", hint_n, 1'b1);

    if (failures == 0)
      $display("TEST_RESULT: PASS (direct HSTCTL ownership, HCS/HLT, HINT, byte enables, collisions)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_host_control hard timeout");
    $fatal(1);
  end

endmodule : tb_host_control
