// -----------------------------------------------------------------------------
// tb_fill_w2.sv
//
// FILL XY window MISS detection, CONTROL.W=2 (Task 0107). Per 1988 UG §7.10.2:
// a PIXBLT/FILL in W=2 draws the destination array ONLY if it lies entirely
// within the window. If so → V=0, no interrupt. If any pixel is outside → the
// array is NOT drawn, V=1, and a window-violation interrupt is requested
// (INTPEND.WV set). It is an all-or-nothing rectangle-containment test (not the
// per-pixel clip of W=3).
//
// Two FILL XY ops (PSIZE=8, CONVDP=0x1B, OFFSET=0x800, DYDX = DX=2,DY=2,
// COLOR1=0xAA), each captured with GETST:
//   #1 DADDR=(0x20,1), window (0x20,1)..(0x21,2) CONTAINS the array → drawn
//      (words 145/153 = 0xAAAA), V=0.
//   #2 DADDR=(0x20,5), window (0x20,5)..(0x20,6) excludes X=0x21 → MISS: not
//      drawn (words 149/157 stay 0), V=1, INTPEND.WV set.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_fill_w2;
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
    .clk(clk), .vclk_i(clk), .video_hsync_n_i(1'b1), .video_vsync_n_i(1'b1), .rst(rst),
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

  int unsigned failures;
  task automatic check_word(input string label, input int unsigned widx, input logic [15:0] expected);
    if (u_mem.mem[widx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, widx, expected, u_mem.mem[widx]);
      failures++;
    end
  endtask

  localparam logic [31:0] A_PSIZE   = IO_BASE_ADDR + (IO_IDX_PSIZE   << 4);
  localparam logic [31:0] A_CONVDP  = IO_BASE_ADDR + (IO_IDX_CONVDP  << 4);
  localparam logic [31:0] A_CONTROL = IO_BASE_ADDR + (IO_IDX_CONTROL << 4);
  localparam logic [15:0] CTRL_W2   = 16'(2'd2 << CTRL_W_LO);

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE=8
    p = place_movi_il  (p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVDP);              // CONVDP=0x1B
    p = place_movi_il  (p, 4'd0, {16'h0, CTRL_W2});
    p = place_store_abs(p, 4'd0, A_CONTROL);             // CONTROL.W=2
    p = place_movi_il_b(p, 4'd3, 32'h0000_0080);         // DPTCH
    p = place_movi_il_b(p, 4'd4, 32'h0000_0800);         // OFFSET
    p = place_movi_il_b(p, 4'd7, 32'h0002_0002);         // DYDX (DY=2,DX=2)
    p = place_movi_il_b(p, 4'd9, 32'h0000_00AA);         // COLOR1

    // FILL #1: array inside window → drawn, V=0.
    p = place_movi_il_b(p, 4'd2, 32'h0001_0020);         // DADDR (0x20,1)
    p = place_movi_il_b(p, 4'd5, 32'h0001_0020);         // WSTART (0x20,1)
    p = place_movi_il_b(p, 4'd6, 32'h0002_0021);         // WEND   (0x21,2)
    p = place_word(p, 16'h0FE0);                         // FILL XY
    p = place_word(p, getst_enc(4'd8));                  // A8 <- ST (V=0 expected)

    // FILL #2: array crosses X=0x21 > WEND.X=0x20 → MISS, not drawn, V=1, WVP.
    p = place_movi_il_b(p, 4'd2, 32'h0005_0020);         // DADDR (0x20,5)
    p = place_movi_il_b(p, 4'd5, 32'h0005_0020);         // WSTART (0x20,5)
    p = place_movi_il_b(p, 4'd6, 32'h0006_0020);         // WEND   (0x20,6)
    p = place_word(p, 16'h0FE0);                         // FILL XY
    p = place_word(p, getst_enc(4'd9));                  // A9 <- ST (V=1 expected)
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (5000) @(posedge clk);
    #1;

    // FILL #1 drawn (inside window).
    check_word("FILL#1 word145 = 0xAAAA", 145, 16'hAAAA);
    check_word("FILL#1 word153 = 0xAAAA", 153, 16'hAAAA);
    // FILL #2 NOT drawn (window miss).
    check_word("FILL#2 word149 = 0 (miss, not drawn)", 149, 16'h0000);
    check_word("FILL#2 word157 = 0 (miss, not drawn)", 157, 16'h0000);
    // V flags captured by GETST: #1 inside → V=0; #2 miss → V=1.
    if (u_core.u_regfile.a_regs[8][ST_V_BIT] !== 1'b0) begin
      $display("TEST_RESULT: FAIL: FILL#1 V expected 0, A8=%08h", u_core.u_regfile.a_regs[8]);
      failures++;
    end
    if (u_core.u_regfile.a_regs[9][ST_V_BIT] !== 1'b1) begin
      $display("TEST_RESULT: FAIL: FILL#2 V expected 1, A9=%08h", u_core.u_regfile.a_regs[9]);
      failures++;
    end
    // INTPEND.WV set by the FILL#2 window violation.
    if (u_core.u_io_regs.io_reg[IO_IDX_INTPEND][INT_WV_BIT] !== 1'b1) begin
      $display("TEST_RESULT: FAIL: INTPEND.WV not set after window miss: %04h",
               u_core.u_io_regs.io_reg[IO_IDX_INTPEND]);
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (FILL XY W=2: inside→drawn/V=0, miss→not-drawn/V=1/INTPEND.WV)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_fill_w2 hard timeout");
    $fatal(1);
  end
endmodule : tb_fill_w2
