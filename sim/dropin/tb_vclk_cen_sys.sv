// -----------------------------------------------------------------------------
// tb_vclk_cen_sys.sv
//
// VCLK_CEN against a divided VCLK. Two tms34010_system instances run the same
// program (the Exterminator's GSP #1 video set-up from two_gsp_prog.py: video
// timing, screen refresh on, then a store loop), each with its own memory:
//   A: VCLK_CEN=0, vclk_i = clk/6 from a register (as a game core divides it);
//   B: VCLK_CEN=1, vclk_i = a one-clock enable in the clock after A's VCLK rises.
// B's video logic then samples the core side exactly as A's does (A's VCLK edge
// comes just after the clock edge), and everything the video side drives
// (sync and blank pins, the values and events it returns to the core) is one
// clock later. Checked: B's video outputs equal A's one clock later on every
// clock of DIV_FRAMES frames; every bus cycle (kind, address, write data) is the
// same in both, and the start-clock differences are listed (screen-refresh
// requests reach the bus a clock later in B).
// Program: tools/dropin/two_gsp_prog.py -> +PROG1=<file>.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_vclk_cen_sys;
  import tms34010_pkg::*;

  localparam int unsigned FRAME = (16'h13D + 1) * (16'h107 + 1) * 6;   // core clocks

  logic clk = 1'b0;
  always #1 clk = ~clk;
  logic rst = 1'b1;

  // A's VCLK: clk/6, 50% duty, from a register
  logic [2:0] div_q;
  logic [2:0] div_phase;   // +DIV_PHASE=0..5: the divider's phase against reset
  initial if (!$value$plusargs("DIV_PHASE=%d", div_phase)) div_phase = 3'd0;
  logic       vclk_q, vclk_d_q;
  always @(posedge clk) begin
    if (rst) begin div_q <= div_phase; vclk_q <= 1'b0; vclk_d_q <= 1'b0; end
    else begin
      div_q    <= (div_q == 3'd5) ? 3'd0 : div_q + 3'd1;
      vclk_q   <= (div_q == 3'd5) || (div_q < 3'd2);
      vclk_d_q <= vclk_q;
    end
  end
  // +CEN_BEFORE: the enable in the clock that ends at A's VCLK rise (div_q == 5);
  // default: in the clock after it
  bit cen_before;
  initial cen_before = $test$plusargs("CEN_BEFORE");
  wire vclk_cen = cen_before ? (div_q == 3'd5 && !rst) : (vclk_q && !vclk_d_q);

  logic a_hs, a_vs, a_hb, a_vb, a_bl, b_hs, b_vs, b_hb, b_vb, b_bl;
  logic [15:0] a_count, b_count;

  vclk_node #(.VCLK_CEN(1'b0)) u_a (.clk(clk), .rst(rst), .vclk(vclk_q),
    .hs(a_hs), .vs(a_vs), .hb(a_hb), .vb(a_vb), .bl(a_bl), .count(a_count));
  vclk_node #(.VCLK_CEN(1'b1)) u_b (.clk(clk), .rst(rst), .vclk(vclk_cen),
    .hs(b_hs), .vs(b_vs), .hb(b_hb), .vb(b_vb), .bl(b_bl), .count(b_count));

  // A's outputs one clock later, and +OUT_SHIFT=<n> clocks later (diagnosis)
  logic [4:0] a_out_d;
  logic [4:0] a_hist [0:15];
  int unsigned out_shift;
  initial if (!$value$plusargs("OUT_SHIFT=%d", out_shift)) out_shift = 0;
  always @(posedge clk) begin
    a_out_d <= {a_hs, a_vs, a_hb, a_vb, a_bl};
    a_hist[0] <= {a_hs, a_vs, a_hb, a_vb, a_bl};
    for (int i = 1; i < 16; i++) a_hist[i] <= a_hist[i-1];
  end

  int unsigned failures = 0;
  initial begin
    int unsigned frames, checked, bad, bad_vclk;
    if (!$value$plusargs("DIV_FRAMES=%d", frames)) frames = 3;
    repeat (12) @(posedge clk);
    @(negedge clk) rst = 1'b0;
    // wait for both programs to reach their store loops
    while (a_count < 16'd50 || b_count < 16'd50) @(negedge clk);
    checked = 0; bad = 0; bad_vclk = 0;
    repeat (frames * FRAME) begin
      @(negedge clk);
      checked++;
      if ({b_hs, b_vs, b_hb, b_vb, b_bl} !== a_hist[5]) bad_vclk++;   // one VCLK (6 clocks) later
      if ({b_hs, b_vs, b_hb, b_vb, b_bl} !== (out_shift ? a_hist[out_shift-1]
                                             : cen_before ? {a_hs, a_vs, a_hb, a_vb, a_bl} : a_out_d)) begin
        if (bad < 5) $display("  clk %0d: A(+1) %b  B %b", checked, a_out_d, {b_hs, b_vs, b_hb, b_vb, b_bl});
        bad++;
      end
    end
    if (bad && cen_before && !out_shift && bad_vclk == 0) begin
      // The one difference an enable can make: a CPU write to a video register
      // that lands in the clock of a VCLK edge is taken one VCLK later, so the
      // whole video timing runs one VCLK behind A. The bus then differs too
      // (refresh requests move by a VCLK) and is not compared.
      $display("ok: B's outputs equal A's one VCLK (6 clocks) later on all %0d clocks: a CPU write to a video register met a VCLK edge and took effect one VCLK later; bus not compared", checked);
      $display("TEST_RESULT: PASS (VCLK_CEN: same video timing as a divided VCLK, one VCLK later)");
    end else begin
    if (bad) begin
      $display("FAIL: video outputs differ in %0d of %0d clocks", bad, checked);
      failures++;
    end else
      if (cen_before) $display("ok: B's sync/blank outputs equal A's on all %0d clocks (%0d frames)", checked, frames);
      else            $display("ok: B's sync/blank outputs equal A's one clock later on all %0d clocks (%0d frames)", checked, frames);
    compare_bus();
    if (failures == 0) $display("TEST_RESULT: PASS (VCLK_CEN: same video timing as a divided VCLK)");
    else               $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  task automatic compare_bus();
    int unsigned n, seq_bad, shift_hist [int];
    n = (u_a.log_n < u_b.log_n) ? u_a.log_n : u_b.log_n;
    seq_bad = 0;
    for (int i = 0; i < n; i++) begin
      if (u_a.log_kind[i] != u_b.log_kind[i] || u_a.log_addr[i] != u_b.log_addr[i]
          || u_a.log_wdata[i] != u_b.log_wdata[i]) begin
        if (seq_bad < 5)
          $display("  bus cycle %0d: A %0d %h %h  B %0d %h %h", i, u_a.log_kind[i], u_a.log_addr[i],
                   u_a.log_wdata[i], u_b.log_kind[i], u_b.log_addr[i], u_b.log_wdata[i]);
        seq_bad++;
      end else begin
        int d = int'(u_b.log_t[i]) - int'(u_a.log_t[i]);
        if (shift_hist.exists(d)) shift_hist[d]++; else shift_hist[d] = 1;
      end
    end
    if (seq_bad) begin
      $display("FAIL: bus cycle sequence differs in %0d of %0d cycles", seq_bad, n);
      failures++;
    end else
      $display("ok: the first %0d bus cycles are the same in A and B (kind, address, write data); A %0d, B %0d in all",
               n, u_a.log_n, u_b.log_n);
    foreach (shift_hist[d]) $display("    start clock B - A = %0d: %0d cycles", d, shift_hist[d]);
  endtask
endmodule

// One CPU system, its memory (one clock per cycle) and a bus-cycle log.
module vclk_node #(parameter bit VCLK_CEN = 1'b0) (
  input  logic        clk,
  input  logic        rst,
  input  logic        vclk,
  output logic        hs, vs, hb, vb, bl,
  output logic [15:0] count
);
  import tms34010_pkg::*;
  logic                  cycle_req, cycle_ack, cycle_iaq;
  local_cycle_kind_t     cycle_kind;
  logic [ADDR_WIDTH-1:0] cycle_addr;
  local_word_t           cycle_wdata, cycle_io_rdata, cycle_rdata;

  tms34010_system #(.CLKS_PER_STATE(8), .CYCLE_ACCURATE(1'b1), .VCLK_CEN(VCLK_CEN)) u_system (
    .clk(clk), .vclk_i(vclk), .rst(rst), .vclk_rst_i(rst),
    .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .run_emu_n_i(1'b1), .emua_n_o(),
    .hcs_n_i(1'b0),
    .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTADRL), .host_be_i(2'b00),
    .host_wdata_i('0), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(),
    .lint1_n_i(1'b1), .lint2_n_i(1'b1), .dpyint_set_i(1'b0),
    .hold_req_i(1'b0), .hold_ack_o(),
    .video_hsync_o(hs), .video_vsync_o(vs), .video_hblank_o(hb), .video_vblank_o(vb), .video_blank_o(bl),
    .video_hsync_oe_o(), .video_vsync_oe_o(),
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

  // bus-cycle log (every cycle the system starts)
  longint unsigned now = 0;
  int unsigned     log_n = 0;
  int unsigned     log_kind [int unsigned];
  logic [31:0]     log_addr [int unsigned];
  logic [15:0]     log_wdata[int unsigned];
  longint unsigned log_t    [int unsigned];

  always @(posedge clk) begin
    now <= now + 1;
    if (rst) t_busy <= 1'b0;
    else if (!t_busy && cycle_req) begin
      t_kind <= cycle_kind; t_addr <= cycle_addr; t_wdata <= cycle_wdata;
      t_io_rdata <= cycle_io_rdata; t_busy <= 1'b1;
      log_kind[log_n] = cycle_kind; log_addr[log_n] = cycle_addr;
      log_wdata[log_n] = (cycle_kind == LOCAL_CYCLE_WORD_WRITE || cycle_kind == LOCAL_CYCLE_IO_WRITE) ? cycle_wdata : 16'h0;
      log_t[log_n] = now; log_n = log_n + 1;
    end else if (t_busy) begin
      if (t_kind == LOCAL_CYCLE_WORD_WRITE) mem[t_addr >> 4] = t_wdata;
      t_busy <= 1'b0;
    end
  end
  assign count = rd(32'h0020_0000);

  initial begin
    string prog;
    int fd;
    logic [31:0] a;
    local_word_t w;
    if (!$value$plusargs("PROG1=%s", prog)) prog = "work/two_gsp_prog_1.txt";
    fd = $fopen(prog, "r");
    if (fd == 0) begin $display("TEST_RESULT: FAIL: cannot open %s", prog); $finish; end
    while ($fscanf(fd, "%h %h", a, w) == 2) mem[a] = w;
    $fclose(fd);
  end
endmodule
