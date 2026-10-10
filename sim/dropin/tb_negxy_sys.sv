// -----------------------------------------------------------------------------
// tb_negxy_sys.sv
//
// Negative XY coordinates and window clipping through tms34010_system (either
// mode). Runs each case of tools/dropin/negxy.py (+CASES=<file>): loads its
// program and memory, resets, runs until the program writes 0x0D0E at
// 0x00300000, then prints every non-zero word of the drawing area (64 rows of
// 4096 bits from 0x00200000) as "DUMP <case> <word address> <word>" and
// "DONE <case>". negxy.py check compares them with the guide's rules.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_negxy_sys;
  import tms34010_pkg::*;

  parameter bit          CYCLE_ACCURATE = 1'b1;
  parameter int unsigned CLKS_PER_STATE = 8;
  localparam int unsigned CPS = CYCLE_ACCURATE ? CLKS_PER_STATE : 1;
  localparam int unsigned DONE_W = 32'h0030_0000 >> 4;
  localparam int unsigned AREA_LO = 32'h0020_0000 >> 4;
  localparam int unsigned AREA_HI = (32'h0020_0000 + 64 * 4096) >> 4;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #1 clk = ~clk;

  logic                  cycle_req, cycle_ack, cycle_iaq;
  local_cycle_kind_t     cycle_kind;
  logic [ADDR_WIDTH-1:0] cycle_addr;
  local_word_t           cycle_wdata, cycle_io_rdata, cycle_rdata;

  tms34010_system #(
    .CLKS_PER_STATE (CPS),
    .CYCLE_ACCURATE (CYCLE_ACCURATE)
  ) u_system (
    .clk(clk), .vclk_i(clk), .rst(rst), .vclk_rst_i(rst),
    .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .run_emu_n_i(1'b1), .emua_n_o(),
    .hcs_n_i(1'b0),
    .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTADRL), .host_be_i(2'b00),
    .host_wdata_i('0), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(),
    .lint1_n_i(1'b1), .lint2_n_i(1'b1), .dpyint_set_i(1'b0),
    .hold_req_i(1'b0), .hold_ack_o(),
    .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(),
    .video_hsync_oe_o(), .video_vsync_oe_o(),
    .cycle_req_o(cycle_req), .cycle_kind_o(cycle_kind), .cycle_addr_o(cycle_addr),
    .cycle_wdata_o(cycle_wdata), .cycle_io_rdata_o(cycle_io_rdata), .cycle_iaq_o(cycle_iaq),
    .cycle_srfaddr_o(), .cycle_dpytap_o(), .cycle_screen_org_o(), .cycle_dram_row_o(),
    .cycle_rdata_i(cycle_rdata), .cycle_ack_i(cycle_ack),
    .state_o(), .pc_o(), .instr_word_o(), .illegal_opcode_o()
  );

  // local memory, one clock per cycle
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

  initial begin
    string path, tag;
    int fd, n, id, cases, timeouts;
    logic [31:0] start, a;
    local_word_t w;
    if (!$value$plusargs("CASES=%s", path)) path = "work/negxy_cases.txt";
    fd = $fopen(path, "r");
    if (fd == 0) begin
      $display("TEST_RESULT: FAIL: cannot open %s", path);
      $finish;
    end
    cases = 0; timeouts = 0;
    while ($fscanf(fd, "%s", tag) == 1) begin
      if (tag == "CASE") begin
        n = $fscanf(fd, "%d %h", id, start);
        mem.delete();
        mem[32'hFFFF_FFE0 >> 4]       = start[15:0];
        mem[(32'hFFFF_FFE0 >> 4) + 1] = start[31:16];
      end else if (tag == "W") begin
        n = $fscanf(fd, "%h %h", a, w);
        mem[a] = w;
      end else if (tag == "END") begin
        rst = 1'b1;
        repeat (4) @(posedge clk);
        @(negedge clk) rst = 1'b0;
        for (int c = 0; c < 400000 && rd(DONE_W << 4) != 16'h0D0E; c++) @(posedge clk);
        repeat (40) @(posedge clk);      // let a last posted write land
        if (rd(DONE_W << 4) == 16'h0D0E) begin
          foreach (mem[k])
            if (k >= AREA_LO && k < AREA_HI && mem[k] != 16'h0000)
              $display("DUMP %0d %08h %04h", id, k, mem[k]);
          $display("DONE %0d", id);
        end else begin
          $display("TIMEOUT %0d", id);
          timeouts++;
        end
        cases++;
      end
    end
    $fclose(fd);
    $display("RAN %0d cases, %0d timeouts (CYCLE_ACCURATE=%0d)", cases, timeouts, CYCLE_ACCURATE);
    $finish;
  end
endmodule
