// -----------------------------------------------------------------------------
// tb_two_gsp_sys.sv
//
// 1988 UG 9.9.1, "A Two-GSP System", at system level: two tms34010_system
// instances, each with its own local memory and program, as on the
// Exterminator. Each CPU writes its own video registers (the values the game
// writes, tools/dropin/two_gsp_prog.py): GSP #1 internal video timing
// (DXV=1), GSP #2 external sync (DXV=0, HSD=0) on GSP #1's HSYNC/VSYNC pins,
// programmed as Table 9-1. Both run screen refresh (SRE=1) and a store loop,
// so the video timing runs alongside bus traffic. GSP #2 comes out of reset
// SKEW clocks after GSP #1 (+SKEW, default 1237), so the two start out of step
// and GSP #2 has to lock to the pins.
//
// After both programs have written DPYCTL and two frames have passed, checks
// for four frames that BLANK and HBLANK of the two are equal on every clock
// ("the BLANK signals from GSP #1 and GSP #2 are the same, and switch in
// unison"). The internal VBLANK flags may differ for the 3 clocks by which GSP
// #2's line starts later (tb_two_gsp_sync); they are counted and must fall in
// horizontal blanking. +NOSYNC leaves GSP #2's sync inputs unconnected: the
// check must then fail (shows the bench can see a broken sync).
// Programs: tools/dropin/two_gsp_prog.py -> +PROG1=<file> +PROG2=<file>.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_two_gsp_sys;
  import tms34010_pkg::*;

  parameter bit          CYCLE_ACCURATE = 1'b1;
  parameter int unsigned CLKS_PER_STATE = 8;
  localparam int unsigned CPS = CYCLE_ACCURATE ? CLKS_PER_STATE : 1;

  // the Exterminator's GSP #1 frame (two_gsp_prog.py): HTOTAL 0x13D, VTOTAL 0x107
  localparam int unsigned FRAME = (16'h13D + 1) * (16'h107 + 1);

  logic clk = 1'b0;
  always #1 clk = ~clk;
  logic rst1 = 1'b1, rst2 = 1'b1;

  logic hs1, vs1, hs1_oe, vs1_oe, hb1, vb1, bl1;
  logic hs2, vs2, hb2, vb2, bl2;
  logic nosync;
  logic hs2_n_in, vs2_n_in;
  assign hs2_n_in = (nosync || !hs1_oe) ? 1'b1 : !hs1;
  assign vs2_n_in = (nosync || !vs1_oe) ? 1'b1 : !vs1;

  logic [15:0] count1, count2;
  int unsigned srf1, srf2;

  two_gsp_node #(.ID(1), .CYCLE_ACCURATE(CYCLE_ACCURATE), .CPS(CPS)) u_gsp1 (
    .clk(clk), .rst(rst1), .hsync_n_i(1'b1), .vsync_n_i(1'b1),
    .hsync_o(hs1), .vsync_o(vs1), .hsync_oe_o(hs1_oe), .vsync_oe_o(vs1_oe),
    .hblank_o(hb1), .vblank_o(vb1), .blank_o(bl1), .count_o(count1), .srf_o(srf1)
  );
  two_gsp_node #(.ID(2), .CYCLE_ACCURATE(CYCLE_ACCURATE), .CPS(CPS)) u_gsp2 (
    .clk(clk), .rst(rst2), .hsync_n_i(hs2_n_in), .vsync_n_i(vs2_n_in),
    .hsync_o(hs2), .vsync_o(vs2), .hsync_oe_o(), .vsync_oe_o(),
    .hblank_o(hb2), .vblank_o(vb2), .blank_o(bl2), .count_o(count2), .srf_o(srf2)
  );

  int unsigned failures = 0;

  initial begin
    int unsigned skew, bad, checked, vdiff, srf1_0, srf2_0;
    string tag;
    longint unsigned t0;
    if (!$value$plusargs("SKEW=%d", skew)) skew = 1237;
    nosync = $test$plusargs("NOSYNC");
    repeat (4) @(posedge clk);
    @(negedge clk) rst1 = 1'b0;
    repeat (skew) @(negedge clk);
    rst2 = 1'b0;
    // both programs have written DPYCTL once their store loops run
    t0 = 0;
    while ((count1 < 16'd50 || count2 < 16'd50) && t0 < 2_000_000) begin
      @(negedge clk);
      t0++;
    end
    if (count1 < 16'd50 || count2 < 16'd50) begin
      $display("TEST_RESULT: FAIL: programs did not reach their loops (%0d, %0d)", count1, count2);
      $finish;
    end
    // let GSP #2 lock: two full frames
    repeat (2 * FRAME) @(negedge clk);
    bad = 0; checked = 0; vdiff = 0;
    srf1_0 = srf1; srf2_0 = srf2;
    repeat (4 * FRAME) begin
      @(negedge clk);
      checked++;
      if (vb1 !== vb2) vdiff++;
      // BLANK and HBLANK equal; a VBLANK difference only in horizontal blanking
      if (bl1 !== bl2 || hb1 !== hb2 || (vb1 !== vb2 && !(hb1 && hb2))) begin
        if (bad < 5)
          $display("  GSP1 blank %0b/%0b/%0b  GSP2 blank %0b/%0b/%0b",
                   bl1, hb1, vb1, bl2, hb2, vb2);
        bad++;
      end
    end
    if (bad != 0) begin
      $display("FAIL: BLANK differs in %0d of %0d clocks", bad, checked);
      failures++;
    end else
      $display("ok: BLANK and HBLANK equal on all %0d clocks (VBLANK flags differ in %0d, all in horizontal blanking)",
               checked, vdiff);
    $display("    over the 4 frames: screen-refresh cycles %0d / %0d; stores %0d / %0d",
             srf1 - srf1_0, srf2 - srf2_0, count1, count2);
    if (srf1 == srf1_0 || srf2 == srf2_0) begin
      $display("FAIL: no screen refresh (SRE not set?)");
      failures++;
    end
    tag = nosync ? " NOSYNC" : "";
    if (failures == 0)
      $display("TEST_RESULT: PASS (two GSPs at system level, 9.9.1/Table 9-1, CYCLE_ACCURATE=%0d%s)",
               CYCLE_ACCURATE, tag);
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed (CYCLE_ACCURATE=%0d%s)", failures, CYCLE_ACCURATE, tag);
    $finish;
  end
endmodule

// One GSP: tms34010_system with its own local memory (one clock per cycle).
module two_gsp_node #(
  parameter int unsigned ID = 1,
  parameter bit          CYCLE_ACCURATE = 1'b1,
  parameter int unsigned CPS = 8
) (
  input  logic        clk,
  input  logic        rst,
  input  logic        hsync_n_i,
  input  logic        vsync_n_i,
  output logic        hsync_o,
  output logic        vsync_o,
  output logic        hsync_oe_o,
  output logic        vsync_oe_o,
  output logic        hblank_o,
  output logic        vblank_o,
  output logic        blank_o,
  output logic [15:0] count_o,
  output int unsigned srf_o
);
  import tms34010_pkg::*;

  logic                  cycle_req, cycle_ack, cycle_iaq;
  local_cycle_kind_t     cycle_kind;
  logic [ADDR_WIDTH-1:0] cycle_addr;
  local_word_t           cycle_wdata, cycle_io_rdata, cycle_rdata;

  tms34010_system #(
    .CLKS_PER_STATE (CPS),
    .CYCLE_ACCURATE (CYCLE_ACCURATE)
  ) u_system (
    .clk(clk), .vclk_i(clk), .rst(rst), .vclk_rst_i(rst),
    .video_hsync_n_i(hsync_n_i), .video_vsync_n_i(vsync_n_i), .run_emu_n_i(1'b1), .emua_n_o(),
    .hcs_n_i(1'b0),
    .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTADRL), .host_be_i(2'b00),
    .host_wdata_i('0), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(),
    .lint1_n_i(1'b1), .lint2_n_i(1'b1), .dpyint_set_i(1'b0),
    .hold_req_i(1'b0), .hold_ack_o(),
    .video_hsync_o(hsync_o), .video_vsync_o(vsync_o), .video_hblank_o(hblank_o),
    .video_vblank_o(vblank_o), .video_blank_o(blank_o),
    .video_hsync_oe_o(hsync_oe_o), .video_vsync_oe_o(vsync_oe_o),
    .cycle_req_o(cycle_req), .cycle_kind_o(cycle_kind), .cycle_addr_o(cycle_addr),
    .cycle_wdata_o(cycle_wdata), .cycle_io_rdata_o(cycle_io_rdata), .cycle_iaq_o(cycle_iaq),
    .cycle_srfaddr_o(), .cycle_dpytap_o(), .cycle_screen_org_o(), .cycle_dram_row_o(),
    .cycle_rdata_i(cycle_rdata), .cycle_ack_i(cycle_ack),
    .state_o(), .pc_o(), .instr_word_o(), .illegal_opcode_o()
  );

  local_word_t mem [int unsigned];
  function automatic local_word_t rd(logic [ADDR_WIDTH-1:0] a);
    int unsigned w = a >> 4;
    if (mem.exists(w)) return mem[w];
    return 16'h0000;
  endfunction

  logic                  t_busy = 1'b0;
  local_cycle_kind_t     t_kind;
  logic [ADDR_WIDTH-1:0] t_addr;
  local_word_t           t_wdata, t_io_rdata;
  assign cycle_ack   = t_busy;
  assign cycle_rdata = (t_kind == LOCAL_CYCLE_IO_READ) ? t_io_rdata : rd(t_addr);
  always @(posedge clk) begin
    if (rst) t_busy <= 1'b0;
    else if (!t_busy && cycle_req) begin
      t_kind <= cycle_kind; t_addr <= cycle_addr; t_wdata <= cycle_wdata;
      t_io_rdata <= cycle_io_rdata; t_busy <= 1'b1;
    end else if (t_busy) begin
      if (t_kind == LOCAL_CYCLE_WORD_WRITE) mem[t_addr >> 4] = t_wdata;
      t_busy <= 1'b0;
    end
  end
  assign count_o = rd(32'h0020_0000);
  // screen-refresh cycles, to show SRE is on (the programs set it)
  always @(posedge clk)
    if (rst) srf_o <= 0;
    else if (!t_busy && cycle_req && cycle_kind == LOCAL_CYCLE_SCREEN_REFRESH) srf_o <= srf_o + 1;

  initial begin
    string prog;
    int fd;
    logic [31:0] a;
    local_word_t w;
    if (ID == 1) begin
      if (!$value$plusargs("PROG1=%s", prog)) prog = "work/two_gsp_prog_1.txt";
    end else begin
      if (!$value$plusargs("PROG2=%s", prog)) prog = "work/two_gsp_prog_2.txt";
    end
    fd = $fopen(prog, "r");
    if (fd == 0) begin
      $display("TEST_RESULT: FAIL: cannot open %s", prog);
      $finish;
    end
    while ($fscanf(fd, "%h %h", a, w) == 2) mem[a] = w;
    $fclose(fd);
  end
endmodule
