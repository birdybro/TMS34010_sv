// -----------------------------------------------------------------------------
// tb_line_abort.sv
//
// LINE window abort modes, CONTROL.W=2 (miss) and W=1 (hit) — Task 0116. Per
// 1988 UG §7.10.1/2: a windowed LINE aborts on a violation, setting INTPEND.WV
// and V. The V bit at the end is NOT-last-pixel-inside for every windowed mode.
//   W=2 (miss): draws inside pixels; on an OUTSIDE pixel the write is inhibited,
//               V=1, WVP set, and the LINE aborts.
//   W=1 (hit):  draws OUTSIDE pixels; on an INSIDE pixel the write is inhibited,
//               V=0 (inside found), WVP set, and the LINE aborts.
// (The WVP -> INTPEND.WV interrupt is then handled by the maskable interrupt
//  subsystem. W=3 clip is in tb_line_win.)
//
// Two vertical 4-pixel lines (PSIZE=8, CONVDP=0x1B, OFFSET=0x800, COLOR1=0xAA):
//   W=2: line (0x20,1..4), window (0x20,1)..(0x20,2). Draws words145,146;
//        aborts at (0x20,3) (outside) → 147,148 stay 0, V=1.
//   W=1: line (0x10,1..4), window (0x10,3)..(0x10,4). Draws words137,138
//        (outside); aborts at (0x10,3) (inside) → 139,140 stay 0, V=0.
//   Both set INTPEND.WV.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_line_abort;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                          mem_req, mem_we, mem_ack;
  logic [ADDR_WIDTH-1:0]         mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0]   mem_size;
  logic [DATA_WIDTH-1:0]         mem_wdata, mem_rdata;
  core_state_t                   state_w;
  logic [ADDR_WIDTH-1:0]         pc_w;
  instr_word_t                   instr_w;
  logic                          illegal_w;

  tms34010_core u_core (
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .rst(rst), .vclk_rst_i(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_srt(), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .hcs_n_i(1'b0), .host_req_i(1'b0), .host_we_i(1'b0), .host_reg_i(HOST_REG_HSTCTL), .host_be_i(2'b00), .host_wdata_i(16'h0000), .host_rdata_o(), .host_ack_o(), .host_busy_o(), .hint_n_o(), .host_mem_req_o(), .host_mem_we_o(), .host_mem_addr_o(), .host_mem_wdata_o(), .host_mem_rdata_i(16'h0000), .host_mem_ack_i(1'b0), .dpyint_set_i(1'b0), .refresh_req_o(), .refresh_row_o(), .refresh_cbr_o(), .video_hsync_o(), .video_vsync_o(), .video_hblank_o(), .video_vblank_o(), .video_blank_o(), .video_hsync_oe_o(), .video_vsync_oe_o(), .screen_refresh_req_o(), .screen_refresh_ack_i(1'b0), .screen_refresh_srfaddr_o(), .screen_refresh_dpytap_o()
  );
  sim_memory_model #(.DEPTH_WORDS(256)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t movi_il_b_enc(input reg_idx_t i);
    movi_il_b_enc = 16'h09F0 | instr_word_t'(i);
  endfunction
  function automatic instr_word_t setf_enc(input logic [4:0] fs, input logic fe, f_sel);
    setf_enc = 16'b0000_0100_0000_0000
             | (instr_word_t'(f_sel) << 9) | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000 | (instr_word_t'(fe) << 5) | instr_word_t'(fs);
  endfunction
  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction
  function automatic int unsigned place_movi_il(input int unsigned p, input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]=movi_il_enc(i); u_mem.mem[p+1]=imm[15:0]; u_mem.mem[p+2]=imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_movi_il_b(input int unsigned p, input reg_idx_t i,
                                                  input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]=movi_il_b_enc(i); u_mem.mem[p+1]=imm[15:0]; u_mem.mem[p+2]=imm[31:16];
    place_movi_il_b = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p]=w; place_word=p+1;
  endfunction
  function automatic int unsigned place_store_abs(input int unsigned p, input reg_idx_t rs,
                                                  input logic [31:0] addr);
    u_mem.mem[p]=16'h0580|instr_word_t'(rs); u_mem.mem[p+1]=addr[15:0]; u_mem.mem[p+2]=addr[31:16];
    place_store_abs = p + 3;
  endfunction
  // Set the 8 LINE params for a vertical 4-pixel line at (sx,1).
  function automatic int unsigned place_vline(input int unsigned p, input logic [15:0] sx,
                                              input logic [31:0] wstart, input logic [31:0] wend);
    p = place_movi_il_b(p, 4'd0,  32'hFFFF_FFFD);   // d = -3
    p = place_movi_il_b(p, 4'd2,  {16'h0001, sx});  // DADDR (sx,1)
    p = place_movi_il_b(p, 4'd5,  wstart);          // WSTART
    p = place_movi_il_b(p, 4'd6,  wend);            // WEND
    p = place_movi_il_b(p, 4'd7,  32'h0000_0003);   // DYDX {b=0,a=3}
    p = place_movi_il_b(p, 4'd10, 32'h0000_0004);   // COUNT=4
    p = place_movi_il_b(p, 4'd11, 32'h0001_0000);   // INC1
    p = place_movi_il_b(p, 4'd12, 32'h0001_0000);   // INC2 (+1 Y)
    place_vline = p;
  endfunction

  int unsigned failures;
  int unsigned checkpoint_count;
  int unsigned setup_count;

  always @(posedge clk) begin
    if (rst) begin
      checkpoint_count <= 0;
      setup_count <= 0;
    end else begin
      if (state_w == CORE_LINE_CKPT_COUNT)
        checkpoint_count <= checkpoint_count + 1;
      if (state_w == CORE_LINE_SETUP1)
        setup_count <= setup_count + 1;
    end
  end
  task automatic check_word(input string label, input int unsigned widx, input logic [15:0] expected);
    if (u_mem.mem[widx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, widx, expected, u_mem.mem[widx]);
      failures++;
    end
  endtask
  task automatic check_v(input string label, input reg_idx_t areg, input logic exp);
    if (u_core.u_regfile.a_regs[areg][ST_V_BIT] !== exp) begin
      $display("TEST_RESULT: FAIL: %s: V expected %b, A%0d=%08h",
               label, exp, areg, u_core.u_regfile.a_regs[areg]);
      failures++;
    end
  endtask

  localparam logic [31:0] A_PSIZE   = IO_BASE_ADDR + (IO_IDX_PSIZE   << 4);
  localparam logic [31:0] A_CONVDP  = IO_BASE_ADDR + (IO_IDX_CONVDP  << 4);
  localparam logic [31:0] A_CONTROL = IO_BASE_ADDR + (IO_IDX_CONTROL << 4);
  function automatic logic [15:0] ctrl_w(input logic [1:0] w);
    ctrl_w = 16'(w) << CTRL_W_LO;
  endfunction

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;
    for (i = 130; i < 200; i++) u_mem.mem[i] = 16'h0000;

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8
    p = place_movi_il  (p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVDP);              // CONVDP = 0x1B
    p = place_movi_il_b(p, 4'd4,  32'h0000_0800);        // OFFSET
    p = place_movi_il_b(p, 4'd9,  32'hAAAA_AAAA);        // uniform COLOR1

    // W=2 (miss): line (0x20,1..4), window (0x20,1)..(0x20,2). Aborts at Y=3.
    p = place_movi_il  (p, 4'd0, {16'h0, ctrl_w(2'd2)});
    p = place_store_abs(p, 4'd0, A_CONTROL);
    p = place_vline(p, 16'h0020, 32'h0001_0020, 32'h0002_0020);
    p = place_word(p, 16'hDF1A);                         // LINE
    p = place_word(p, getst_enc(4'd8));                  // A8 <- ST (V=1)

    // W=1 (hit): line (0x10,1..4), window (0x10,3)..(0x10,4). Aborts at Y=3.
    p = place_movi_il  (p, 4'd0, {16'h0, ctrl_w(2'd1)});
    p = place_store_abs(p, 4'd0, A_CONTROL);
    p = place_vline(p, 16'h0010, 32'h0003_0010, 32'h0004_0010);
    p = place_word(p, 16'hDF1A);                         // LINE
    p = place_word(p, getst_enc(4'd9));                  // A9 <- ST (V=0)
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (6000) @(posedge clk);
    #1;

    // W=2: drew the two inside pixels, aborted before the first outside one.
    check_word("W=2: word145 (inside) drawn",  145, 16'h00AA);
    check_word("W=2: word146 (inside) drawn",  146, 16'h00AA);
    check_word("W=2: word147 (abort) skipped", 147, 16'h0000);
    check_word("W=2: word148 skipped",         148, 16'h0000);
    check_v("W=2: V=1 (aborted on outside)", 4'd8, 1'b1);
    // W=1: drew the two outside pixels, aborted at the first inside one.
    check_word("W=1: word137 (outside) drawn", 137, 16'h00AA);
    check_word("W=1: word138 (outside) drawn", 138, 16'h00AA);
    check_word("W=1: word139 (abort) skipped", 139, 16'h0000);
    check_word("W=1: word140 skipped",         140, 16'h0000);
    check_v("W=1: V=0 (inside found)", 4'd9, 1'b0);
    // Both aborts set the window-violation interrupt pending bit.
    if (u_core.u_io_regs.io_reg[IO_IDX_INTPEND][INT_WV_BIT] !== 1'b1) begin
      $display("TEST_RESULT: FAIL: INTPEND.WV not set after abort: %04h",
               u_core.u_io_regs.io_reg[IO_IDX_INTPEND]);
      failures++;
    end
    // Each line publishes its two successfully completed pre-abort pixels.
    // The violating third pixel takes the final completion path, so it cannot
    // create a restart image or a RETI-style second setup.
    if (checkpoint_count != 4 || setup_count != 2) begin
      $display("TEST_RESULT: FAIL: LINE abort continuation count checkpoint=%0d/4 setup=%0d/2",
               checkpoint_count, setup_count);
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (LINE W=1/W=2 abort: draw-then-abort on violation, V + INTPEND.WV)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #6_000_000;
    $display("TEST_RESULT: FAIL: tb_line_abort hard timeout");
    $fatal(1);
  end
endmodule : tb_line_abort
