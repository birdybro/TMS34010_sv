// -----------------------------------------------------------------------------
// tb_pixt_win.sv
//
// PIXT (XY) per-pixel window checking, CONTROL.W (Task 0117). Mirrors the DRAV
// window for the single-pixel PIXT store (1988 UG §7.10): the pointer's XY is
// tested; W=2/W=3 draw inside, W=1 never draws; V (W!=0) = NOT inside; WVP on a
// W=1 hit (inside) or W=2 miss (outside). The store path is shared with regular
// MOVE — the window logic is gated by pixt_xy_win (force_pixel & xy_addr & W!=0).
//
// PIXT A1,*A0.XY (encoding 0xF020): A0 = XY pointer, A1 = COLOR pixel.
// PSIZE=8, CONVDP=0x1B, OFFSET(B4)=0x800, window (0x20,1)..(0x21,2).
//   #1 W=3, A0=(0x20,1) inside  -> word145 low = 0xAA, V=0.
//   #2 W=3, A0=(0x20,5) outside -> word149 stays 0,    V=1.
//   #3 W=2, A0=(0x20,5) outside -> not drawn, V=1, INTPEND.WV set.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_pixt_win;
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
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o()
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
  function automatic instr_word_t pixt_xy_store_enc(input reg_idx_t rs, rd);
    pixt_xy_store_enc = 16'hF000 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
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
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));
    p = place_movi_il  (p, 4'd2, 32'h0000_0008);
    p = place_store_abs(p, 4'd2, A_PSIZE);               // PSIZE = 8
    p = place_movi_il  (p, 4'd2, 32'h0000_001B);
    p = place_store_abs(p, 4'd2, A_CONVDP);              // CONVDP = 0x1B
    p = place_movi_il_b(p, 4'd4, 32'h0000_0800);         // OFFSET (B4)
    p = place_movi_il_b(p, 4'd5, 32'h0001_0020);         // WSTART (0x20,1)
    p = place_movi_il_b(p, 4'd6, 32'h0002_0021);         // WEND   (0x21,2)
    p = place_movi_il  (p, 4'd1, 32'h0000_00AA);         // A1 = pixel 0xAA

    // #1: W=3, pointer inside the window -> drawn, V=0.
    p = place_movi_il  (p, 4'd0, {16'h0, ctrl_w(2'd3)});
    p = place_store_abs(p, 4'd0, A_CONTROL);
    p = place_movi_il  (p, 4'd0, 32'h0001_0020);         // A0 = XY (0x20,1) inside
    p = place_word(p, pixt_xy_store_enc(4'd1, 4'd0));     // PIXT A1,*A0.XY
    p = place_word(p, getst_enc(4'd4));                  // A4 <- ST (V=0)
    // #2: W=3, pointer outside -> not drawn, V=1.
    p = place_movi_il  (p, 4'd0, 32'h0005_0020);         // A0 = XY (0x20,5) outside
    p = place_word(p, pixt_xy_store_enc(4'd1, 4'd0));
    p = place_word(p, getst_enc(4'd5));                  // A5 <- ST (V=1)
    // #3: W=2, pointer outside -> not drawn, V=1, WVP.
    p = place_movi_il  (p, 4'd2, {16'h0, ctrl_w(2'd2)});
    p = place_store_abs(p, 4'd2, A_CONTROL);
    p = place_movi_il  (p, 4'd0, 32'h0005_0020);         // A0 = XY (0x20,5) outside
    p = place_word(p, pixt_xy_store_enc(4'd1, 4'd0));
    p = place_word(p, getst_enc(4'd6));                  // A6 <- ST (V=1)
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (4000) @(posedge clk);
    #1;

    check_word("PIXT W=3 inside: word145 = 0x00AA",  145, 16'h00AA);
    check_word("PIXT W=3 outside: word149 = 0",      149, 16'h0000);
    check_v("#1 W=3 inside  V=0", 4'd4, 1'b0);
    check_v("#2 W=3 outside V=1", 4'd5, 1'b1);
    check_v("#3 W=2 outside V=1", 4'd6, 1'b1);
    if (u_core.u_io_regs.io_reg[IO_IDX_INTPEND][INT_WV_BIT] !== 1'b1) begin
      $display("TEST_RESULT: FAIL: INTPEND.WV not set after W=2 miss: %04h",
               u_core.u_io_regs.io_reg[IO_IDX_INTPEND]);
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (PIXT XY window: per-pixel draw/skip, V, INTPEND.WV)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_pixt_win hard timeout");
    $fatal(1);
  end
endmodule : tb_pixt_win
