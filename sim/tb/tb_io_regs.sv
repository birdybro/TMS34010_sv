// -----------------------------------------------------------------------------
// tb_io_regs.sv
//
// Unit test for tms34010_io_regs — the on-chip memory-mapped I/O register
// file (1988 UG Figure 6-1). Drives the access interface directly (no core):
// checks reset-to-0, per-register write/read-back, reserved fields/locations,
// the I/O-space address decode (is_io), index mapping (addr[8:4]), and that
// writes to non-I/O addresses are ignored.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_io_regs;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                  req, we;
  logic [ADDR_WIDTH-1:0] addr;
  logic [15:0]           wdata;
  logic [15:0]           rdata;
  logic                  is_io;
  logic [15:0]           psize_w;
  logic [15:0]           convdp_w;
  logic [15:0]           convsp_w;
  logic [15:0]           control_w;
  logic [15:0]           pmask_w;
  logic [15:0]           intenb_w;
  logic [15:0]           intpend_w;
  logic [15:0]           hstctlh_w;

  tms34010_io_regs u_io (
    .clk(clk), .vclk_i(clk), .rst(rst),
    .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1),
    .video_hsync_oe_o(), .video_vsync_oe_o(),
    .req(req), .we(we), .addr(addr), .wdata(wdata),
    .rdata(rdata), .is_io(is_io),
    .psize_o(psize_w), .convdp_o(convdp_w), .convsp_o(convsp_w),
    .control_o(control_w), .pmask_o(pmask_w), .pixel_srt_o(),
    .intenb_o(intenb_w), .intpend_o(intpend_w),
    .hstctlh_o(hstctlh_w), .refcnt_o(), .refresh_req_o(),
    .refresh_row_o(), .refresh_cbr_o(),
    .hcount_o(), .vcount_o(),
    .video_hsync_o(), .video_vsync_o(),
    .video_hblank_o(), .video_vblank_o(), .video_blank_o(),
    .dpyadr_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0),
    .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o(),
    .screen_refresh_org_o(),
    .nmi_clear(1'b0), .wvp_set(1'b0),
    .dpyint_set(1'b0), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .hlt_o(),
    .host_mem_is_io_o(), .host_mem_io_rdata_o(),
    .lint1_n_i(1'b1), .lint2_n_i(1'b1)
  );

  int unsigned failures;

  // Synchronous write over the access interface.
  task automatic io_write(input logic [ADDR_WIDTH-1:0] a, input logic [15:0] d);
    @(negedge clk);
    req = 1'b1; we = 1'b1; addr = a; wdata = d;
    @(negedge clk);
    req = 1'b0; we = 1'b0;
  endtask

  // Async read: drive the address, settle, return rdata.
  task automatic io_read(input logic [ADDR_WIDTH-1:0] a, output logic [15:0] d);
    req = 1'b1; we = 1'b0; addr = a;
    #1;
    d = rdata;
    req = 1'b0;
  endtask

  task automatic check_read(input string label, input logic [ADDR_WIDTH-1:0] a,
                            input logic [15:0] expected);
    logic [15:0] got;
    io_read(a, got);
    if (got !== expected) begin
      $display("TEST_RESULT: FAIL: %s: addr=%08h expected=%04h actual=%04h",
               label, a, expected, got);
      failures++;
    end
  endtask

  task automatic check_isio(input string label, input logic [ADDR_WIDTH-1:0] a,
                            input logic expected);
    addr = a; #1;
    if (is_io !== expected) begin
      $display("TEST_RESULT: FAIL: %s: addr=%08h is_io expected=%0b actual=%0b",
               label, a, expected, is_io);
      failures++;
    end
  endtask

  // A few register addresses (IO_BASE + index*0x10).
  localparam logic [ADDR_WIDTH-1:0] A_PSIZE =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_PSIZE) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_PMASK =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_PMASK) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_CONVSP =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_CONVSP) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_CONVDP =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_CONVDP) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_CONTROL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_CONTROL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYCTL =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYCTL) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_DPYTAP =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_DPYTAP) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_RESERVED_17 =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_RESERVED_17) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_RESERVED_18 =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_RESERVED_18) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_RESERVED_19 =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_RESERVED_19) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_RESERVED_1A =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_RESERVED_1A) << 4);
  localparam logic [ADDR_WIDTH-1:0] A_HESYNC =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_HESYNC) << 4); // idx 0
  localparam logic [ADDR_WIDTH-1:0] A_REFCNT =
      IO_BASE_ADDR + (ADDR_WIDTH'(IO_IDX_REFCNT) << 4); // idx 31

  initial begin : main
    failures = 0;
    req = 1'b0; we = 1'b0; addr = '0; wdata = '0;

    // Confirm the address arithmetic matches the spec map.
    if (A_PSIZE !== 32'hC000_0150) begin
      $display("TEST_RESULT: FAIL: PSIZE addr = %08h, expected C0000150", A_PSIZE);
      failures++;
    end

    repeat (3) @(posedge clk);
    @(negedge clk);

    // 1) Reset clears every register to 0. Check while reset remains asserted:
    // after release CONTROL.RR=00 makes the live REFCNT decrement immediately.
    check_read("1: PSIZE reset 0",  A_PSIZE,  16'h0000);
    check_read("1: REFCNT reset 0", A_REFCNT, 16'h0000);
    check_read("1: HESYNC reset 0", A_HESYNC, 16'h0000);
    rst = 1'b0;

    // 2) Write/read-back the graphics control registers, no aliasing.
    io_write(A_PSIZE,  16'h0008);   // 8 bpp
    io_write(A_PMASK,  16'hFF00);
    io_write(A_CONVSP, 16'h000B);
    io_write(A_CONVDP, 16'h000A);
    io_write(A_CONTROL,16'hFFFF);
    check_read("2: PSIZE = 0x0008",   A_PSIZE,   16'h0008);
    if (psize_w !== 16'h0008) begin
      $display("TEST_RESULT: FAIL: 2: psize_o tap = %04h, expected 0008", psize_w);
      failures++;
    end
    check_read("2: PMASK = 0xFF00",   A_PMASK,   16'hFF00);
    check_read("2: CONVSP = 0x000B",  A_CONVSP,  16'h000B);
    check_read("2: CONVDP = 0x000A",  A_CONVDP,  16'h000A);
    check_read("2: CONTROL reserved bits zero",
               A_CONTROL, CONTROL_WRITABLE_MASK);
    if (control_w !== CONTROL_WRITABLE_MASK) begin
      $display("TEST_RESULT: FAIL: 2: control_o tap = %04h, expected %04h",
               control_w, CONTROL_WRITABLE_MASK);
      failures++;
    end

    // 3) Every remaining stored reserved field is forced low. REFCNT's
    // software-written bits 1:0 intentionally follow A0033 and are tested in
    // tb_refresh/tb_io_refresh instead of this ordinary-storage rule.
    io_write(A_DPYCTL, 16'hFFFF);
    check_read("3: DPYCTL reserved bit zero",
               A_DPYCTL, DPYCTL_WRITABLE_MASK);
    io_write(A_DPYTAP, 16'hFFFF);
    check_read("3: DPYTAP reserved bits zero", A_DPYTAP, DPYTAP_MASK);

    // 4) Figure 6-1 reserves indices 17h-1Ah. In particular, the PMASK
    // compatibility word at 17h must ignore writes.
    io_write(A_RESERVED_17, 16'h1111);
    io_write(A_RESERVED_18, 16'h2222);
    io_write(A_RESERVED_19, 16'h4444);
    io_write(A_RESERVED_1A, 16'h8888);
    check_read("4: reserved 17h remains zero", A_RESERVED_17, 16'h0000);
    check_read("4: reserved 18h remains zero", A_RESERVED_18, 16'h0000);
    check_read("4: reserved 19h remains zero", A_RESERVED_19, 16'h0000);
    check_read("4: reserved 1Ah remains zero", A_RESERVED_1A, 16'h0000);

    // 5) Boundary registers (index 0 and 31).
    io_write(A_HESYNC, 16'hABCD);
    io_write(A_REFCNT, 16'h5A5A);
    check_read("5: HESYNC = 0xABCD", A_HESYNC, 16'hABCD);
    check_read("5: REFCNT = 0x5A5A", A_REFCNT, 16'h5A5A);

    // 6) is_io address decode.
    check_isio("6: PSIZE in I/O space",     A_PSIZE,        1'b1);
    check_isio("6: top of range C00001F0",  32'hC000_01F0,  1'b1);
    check_isio("6: just past range C0000200",32'hC000_0200, 1'b0);
    check_isio("6: wrong MSBs 0x40000150",  32'h4000_0150,  1'b0);
    check_isio("6: low memory 0x00001000",  32'h0000_1000,  1'b0);

    // 7) A write to a NON-I/O address must not disturb I/O storage.
    //    0x00000150 shares the low bits with PSIZE but is not I/O space.
    io_write(32'h0000_0150, 16'hAAAA);
    check_read("7: PSIZE unchanged (0x0008)", A_PSIZE, 16'h0008);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (io_regs: storage, reserved fields/locations, decode)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_io_regs hard timeout");
    $fatal(1);
  end

endmodule : tb_io_regs
