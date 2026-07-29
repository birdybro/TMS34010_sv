// -----------------------------------------------------------------------------
// tb_pixblt_w1.sv
//
// PIXBLT XY window HIT detection, CONTROL.W=1 (Task 0110). Mirrors FILL W=1
// (Task 0109) for the block-transfer engine (1988 UG §7.10.1): no pixels are
// drawn; if the dest array lies entirely outside the window → V=1, no
// interrupt; if it overlaps → V=0 and INTPEND.WV is set. Completes window
// checking (W=0/1/2/3) for both graphics engines.
//
// Geometry (tb_pixblt_xy): PSIZE=8, CONVSP=CONVDP=0x1B, OFFSET=0x800, DYDX =
// DX=2,DY=1, source word128 = 0x2211. Neither blt draws (W=1):
//   #1 DADDR=(0x20,0), window (0x80,0)..(0x90,0) — array outside → V=1, no WVP
//      (INTPEND captured into A10 after).
//   #2 DADDR=(0x20,2), window (0x20,2)..(0x21,2) — overlaps → V=0, WVP set.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pixblt_w1;
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
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0)
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
  function automatic int unsigned place_load_abs(input int unsigned p, input reg_idx_t rd,
                                                 input logic [31:0] addr);
    u_mem.mem[p]=16'h05A0|instr_word_t'(rd); u_mem.mem[p+1]=addr[15:0]; u_mem.mem[p+2]=addr[31:16];
    place_load_abs = p + 3;
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
  localparam logic [31:0] A_CONVSP  = IO_BASE_ADDR + (IO_IDX_CONVSP  << 4);
  localparam logic [31:0] A_CONVDP  = IO_BASE_ADDR + (IO_IDX_CONVDP  << 4);
  localparam logic [31:0] A_CONTROL = IO_BASE_ADDR + (IO_IDX_CONTROL << 4);
  localparam logic [31:0] A_INTPEND = IO_BASE_ADDR + (IO_IDX_INTPEND << 4);
  localparam logic [15:0] CTRL_W1   = 16'(2'd1 << CTRL_W_LO);

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;
    u_mem.mem[128] = 16'h2211;

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);
    p = place_movi_il  (p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVSP);
    p = place_movi_il  (p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVDP);
    p = place_movi_il  (p, 4'd0, {16'h0, CTRL_W1});
    p = place_store_abs(p, 4'd0, A_CONTROL);             // CONTROL.W=1
    p = place_movi_il_b(p, 4'd1, 32'h0000_0080);         // SPTCH
    p = place_movi_il_b(p, 4'd3, 32'h0000_0080);         // DPTCH
    p = place_movi_il_b(p, 4'd4, 32'h0000_0800);         // OFFSET
    p = place_movi_il_b(p, 4'd7, 32'h0001_0002);         // DYDX (DY=1,DX=2)

    // #1: dest outside window → no draw, V=1, no WVP.
    p = place_movi_il_b(p, 4'd0, 32'h0000_0000);         // SADDR (0,0)
    p = place_movi_il_b(p, 4'd2, 32'h0000_0020);         // DADDR (0x20,0)
    p = place_movi_il_b(p, 4'd5, 32'h0000_0080);         // WSTART (0x80,0)
    p = place_movi_il_b(p, 4'd6, 32'h0000_0090);         // WEND   (0x90,0)
    p = place_word(p, 16'h0F60);                         // PIXBLT XY,XY
    p = place_word(p, getst_enc(4'd8));                  // A8 <- ST (V=1)
    p = place_load_abs(p, 4'd10, A_INTPEND);             // A10 <- INTPEND (WV=0)

    // #2: dest overlaps window → no draw, V=0, WVP.
    p = place_movi_il_b(p, 4'd0, 32'h0000_0000);         // SADDR (0,0)
    p = place_movi_il_b(p, 4'd2, 32'h0002_0020);         // DADDR (0x20,2)
    p = place_movi_il_b(p, 4'd5, 32'h0002_0020);         // WSTART (0x20,2)
    p = place_movi_il_b(p, 4'd6, 32'h0002_0021);         // WEND   (0x21,2)
    p = place_word(p, 16'h0F60);                         // PIXBLT XY,XY
    p = place_word(p, getst_enc(4'd9));                  // A9 <- ST (V=0)
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (5000) @(posedge clk);
    #1;

    check_word("PIXBLT#1 word144 = 0 (W=1 never draws)", 144, 16'h0000);
    check_word("PIXBLT#2 word146 = 0 (W=1 never draws)", 146, 16'h0000);
    if (u_core.u_regfile.a_regs[8][ST_V_BIT] !== 1'b1) begin
      $display("TEST_RESULT: FAIL: #1 (outside) V expected 1, A8=%08h", u_core.u_regfile.a_regs[8]);
      failures++;
    end
    if (u_core.u_regfile.a_regs[9][ST_V_BIT] !== 1'b0) begin
      $display("TEST_RESULT: FAIL: #2 (overlap) V expected 0, A9=%08h", u_core.u_regfile.a_regs[9]);
      failures++;
    end
    if (u_core.u_regfile.a_regs[10][INT_WV_BIT] !== 1'b0) begin
      $display("TEST_RESULT: FAIL: #1 (outside) set WV, A10=%08h", u_core.u_regfile.a_regs[10]);
      failures++;
    end
    if (u_core.u_io_regs.io_reg[IO_IDX_INTPEND][INT_WV_BIT] !== 1'b1) begin
      $display("TEST_RESULT: FAIL: INTPEND.WV not set after W=1 hit: %04h",
               u_core.u_io_regs.io_reg[IO_IDX_INTPEND]);
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (PIXBLT XY W=1: never draws; outside→V=1/no-WVP, overlap→V=0/INTPEND.WV)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #4_000_000;
    $display("TEST_RESULT: FAIL: tb_pixblt_w1 hard timeout");
    $fatal(1);
  end
endmodule : tb_pixblt_w1
