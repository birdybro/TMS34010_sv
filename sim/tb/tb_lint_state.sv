`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_lint_state.sv
//
// LINT1/LINT2 timing with CYCLE_ACCURATE and 8 core clocks per state (1988 UG
// 8.3): the pins are sampled at each high-to-low transition of LCLK1 (half way
// through a state) and X1P/X2P follow one to two states after the pin. For a
// pin edge at every clock of three states, checks that X1P (X2P) changes 8 to
// 15 clocks later, only in the clock where LCLK1 falls, and at the same clock
// for every pin edge between two falls. Both edges, both pins.
// -----------------------------------------------------------------------------
module tb_lint_state;
  import tms34010_pkg::*;
  localparam int unsigned CPS = 8;

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


  tms34010_io_regs #(.CLKS_PER_STATE(CPS), .CYCLE_ACCURATE(1'b1)) u_dut (
    .clk         (clk), .vclk_i(clk),
    .rst         (rst), .vclk_rst_i(rst),
    .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1),
    .video_hsync_oe_o(), .video_vsync_oe_o(),
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
    .req_addr_i  (addr),
    .wdata       (wdata),
    .req_next_i  (1'b0),
    .req_next_addr_i('0),
    .wdata_next_i('0),
    .rdata       (rdata),
    .rdata_next  (),
    .is_io       (is_io),
    .psize_o     (),
    .convdp_o    (),
    .convsp_o    (),
    .control_o   (),
    .pmask_o     (), .pixel_srt_o(),
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

  int unsigned failures = 0;
  int unsigned cyc = 0;
  always @(posedge clk) cyc <= rst ? 0 : cyc + 1;

  // One run: reset, pin edge after `off` clocks, return the clock at which the
  // INTPEND bit first shows it and the state phase of that clock.
  task automatic run(input int unsigned off, input bit pin2, input bit fall,
                     output int unsigned chg, output int unsigned ph);
    logic [15:0] m;
    m = pin2 ? (16'h0001 << INT_X2_BIT) : (16'h0001 << INT_X1_BIT);
    rst = 1'b1; lint1_n = fall; lint2_n = fall;
    repeat (3) @(posedge clk);
    @(negedge clk); rst = 1'b0;
    repeat (40) @(posedge clk);          // settle: both stages hold the old level
    while (cyc != 40 + off) @(posedge clk);
    @(negedge clk);
    if (pin2) lint2_n = !fall; else lint1_n = !fall;
    chg = 0;
    while (chg == 0) begin
      @(negedge clk);
      if (((intpend & m) != 0) == fall) begin
        chg = cyc;
        ph  = cyc % CPS;
      end
      if (cyc > 200) begin
        $display("FAIL: no change (off %0d)", off); failures++; chg = 1;
      end
    end
  endtask

  initial begin
    int unsigned chg, ph, d, first_chg[int];
    req = 0; we = 0; addr = '0; wdata = '0; nmi_clear = 0; wvp_set = 0; dpyint_set = 0;
    host_req = 0; host_we = 0; host_be = 0; host_wdata = '0; lint1_n = 1; lint2_n = 1;
    for (int p = 0; p < 2; p++)
      for (int f = 0; f < 2; f++) begin
        first_chg.delete();
        for (int unsigned off = 0; off < 3 * CPS; off++) begin
          run(off, p[0], f[0], chg, ph);
          // the pin is first seen by the input flop at clock 41 + off
          d = chg - (41 + off);
          if (d < CPS || d > 2 * CPS - 1) begin
            $display("FAIL: pin%0d %s off %0d: X bit after %0d clocks", p + 1,
                     f ? "fall" : "rise", off, d);
            failures++;
          end
          if (!first_chg.exists(chg)) first_chg[chg] = off;
          else if (off - first_chg[chg] >= CPS) begin
            $display("FAIL: edges %0d and %0d share change clock %0d", first_chg[chg], off, chg);
            failures++;
          end
          // cyc counts from the first clock after reset, as the state phase
          // does: the bit changes in the clock where LCLK1 falls
          if (ph != CPS / 2) begin
            $display("FAIL: pin%0d off %0d: change at phase %0d", p + 1, off, ph);
            failures++;
          end
        end
        // every change clock is used by exactly CPS consecutive edges (except
        // the ends of the range)
        if (first_chg.num() > 4 || first_chg.num() < 3) begin
          $display("FAIL: pin%0d %s: %0d distinct change clocks for %0d edges", p + 1,
                   f ? "fall" : "rise", first_chg.num(), 3 * CPS);
          failures++;
        end
      end
    if (failures == 0)
      $display("TEST_RESULT: PASS (LINT1/LINT2 sampled once per state: 1-2 states, one change clock per state, both edges)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end
  initial begin
    #2000000;
    $display("TEST_RESULT: FAIL: tb_lint_state hard timeout");
    $finish;
  end
endmodule
