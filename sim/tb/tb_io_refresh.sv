// -----------------------------------------------------------------------------
// tb_io_refresh.sv
//
// I/O-boundary integration regression for CONTROL.RM/RR and the live REFCNT
// register. Processor writes load REFCNT, reads observe automatic decrements,
// and refresh request/row/mode outputs provide the future arbiter boundary.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_io_refresh;
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
  logic [15:0]           refcnt;
  logic                  refresh_req;
  logic [7:0]            refresh_row;
  logic                  refresh_cbr;

  localparam logic [ADDR_WIDTH-1:0] A_CONTROL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_CONTROL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_REFCNT =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_REFCNT) << 4);
  localparam logic [15:0] CONTROL_RR01_CBR =
      (16'h0001 << CTRL_RR_LO) | (16'h0001 << CTRL_RM_BIT);
  localparam logic [15:0] CONTROL_RR11 =
      (16'h0003 << CTRL_RR_LO);

  tms34010_io_regs u_dut (
    .clk          (clk),
    .rst          (rst),
    .req          (req),
    .we           (we),
    .addr         (addr),
    .wdata        (wdata),
    .rdata        (rdata),
    .is_io        (is_io),
    .psize_o      (),
    .convdp_o     (),
    .convsp_o     (),
    .control_o    (),
    .pmask_o      (),
    .intenb_o     (),
    .intpend_o    (),
    .hstctlh_o    (),
    .refcnt_o     (refcnt),
    .refresh_req_o(refresh_req),
    .refresh_row_o(refresh_row),
    .refresh_cbr_o(refresh_cbr),
    .hcount_o     (),
    .vcount_o     (),
    .video_hsync_o(),
    .video_vsync_o(),
    .video_hblank_o(),
    .video_vblank_o(),
    .video_blank_o(),
    .nmi_clear    (1'b0),
    .wvp_set      (1'b0),
    .dpyint_set   (1'b0),
    .host_int_set (1'b0),
    .lint1_n_i    (1'b1),
    .lint2_n_i    (1'b1)
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
    logic [15:0] held_refcnt;

    failures = 0;
    req      = 1'b0;
    we       = 1'b0;
    addr     = A_REFCNT;
    wdata    = 16'h0000;

    repeat (3) @(posedge clk);
    @(negedge clk);
    check_value("REFCNT reset", refcnt, 16'h0000);
    rst = 1'b0;

    // Disable automatic refresh before loading REFCNT, as recommended by the
    // guide. The live register must return the exact processor-written word.
    io_write(A_CONTROL, CONTROL_RR11);
    io_write(A_REFCNT, 16'h0103);
    addr = A_REFCNT;
    #1;
    check_value("processor reads loaded live REFCNT", rdata, 16'h0103);
    check_value("REFCNT output matches read", refcnt, 16'h0103);
    check_bit("RAS-only mode", refresh_cbr, 1'b0);
    check_bit("disabled load has no request", refresh_req, 1'b0);

    // Enable 64-clock refresh and CAS-before-RAS. Since RINTVL is zero, the
    // first active count borrows immediately: row 1 -> 0, interval -> 63.
    io_write(A_CONTROL, CONTROL_RR01_CBR);
    @(negedge clk);
    addr = A_REFCNT;
    #1;
    check_value("live REFCNT after underflow", rdata, 16'h00FF);
    check_value("arbiter row after underflow",
                {8'h00, refresh_row}, 16'h0000);
    check_bit("refresh request exported", refresh_req, 1'b1);
    check_bit("CAS-before-RAS mode exported", refresh_cbr, 1'b1);

    @(negedge clk);
    addr = A_REFCNT;
    #1;
    check_value("live REFCNT keeps counting", rdata, 16'h00FB);
    check_bit("request returns low", refresh_req, 1'b0);

    // Disabling can coincide with one final old-mode decrement because both
    // CONTROL and REFCNT are synchronous state. Once the write has landed,
    // the observed counter must remain stable.
    io_write(A_CONTROL, CONTROL_RR11);
    held_refcnt = refcnt;
    repeat (10) @(negedge clk);
    check_value("disabled REFCNT holds", refcnt, held_refcnt);
    check_bit("disabled request low", refresh_req, 1'b0);

    // A second load replaces the live counter rather than a stale mirror.
    io_write(A_REFCNT, 16'hA5A7);
    addr = A_REFCNT;
    #1;
    check_value("second live REFCNT load", rdata, 16'hA5A7);

    if (failures == 0)
      $display("TEST_RESULT: PASS (I/O refresh: CONTROL drives live REFCNT and arbiter boundary)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_io_refresh hard timeout");
    $fatal(1);
  end

endmodule : tb_io_refresh
