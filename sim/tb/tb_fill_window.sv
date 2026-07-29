// -----------------------------------------------------------------------------
// tb_fill_window.sv
//
// FILL XY with window clipping, CONTROL.W = 3 (Task 0105). Per 1988 UG §7.10.3
// (W=3 Window Clipping): pixels of the destination array that fall outside the
// inclusive rectangle [WSTART..WEND] (XY) are not drawn; pixels inside are
// drawn normally. WSTART (B5) / WEND (B6) are XY (X in [15:0], Y in [31:16]).
//
// Reuses the tb_fill_xy geometry (PSIZE=8, CONVDP=0x1B, OFFSET=0x800):
//   DADDR(B2) XY=(X=0x20,Y=1), DYDX = DX=2,DY=2, DPTCH=0x80, COLOR1=0xAA.
//   2x2 array; row0 -> word 145, row1 -> word 153, two 8-bit pixels per word
//   (X=0x20 = low byte, X=0x21 = high byte).
// Window WSTART=(0x20,1), WEND=(0x20,2): includes X=0x20 (both rows), excludes
// X=0x21. So only the low byte of each row word is written; the high byte
// (X=0x21, outside) keeps its initial 0. Expected words = 0x00AA (vs 0xAAAA
// without the window).
//
// W=3 also sets V when any preclipping is required. A seeded full-status
// snapshot verifies that this operation changes V and leaves N/C/Z untouched.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_fill_window;
  import tms34010_pkg::*;

  localparam logic [DATA_WIDTH-1:0] ST_SEED = 32'hE000_0010;

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
  function automatic instr_word_t putst_enc(input reg_idx_t rs);
    putst_enc = 16'h01A0 | instr_word_t'(rs);
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
  localparam logic [15:0] CTRL_W3   = 16'(2'd3 << CTRL_W_LO);  // W=3 (clip)

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-I/O
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8
    p = place_movi_il  (p, 4'd0, 32'h0000_001B);
    p = place_store_abs(p, 4'd0, A_CONVDP);              // CONVDP = 0x1B
    p = place_movi_il  (p, 4'd0, {16'h0, CTRL_W3});
    p = place_store_abs(p, 4'd0, A_CONTROL);             // CONTROL.W = 3 (clip)
    p = place_movi_il_b(p, 4'd2, 32'h0001_0020);         // DADDR XY (X=0x20,Y=1)
    p = place_movi_il_b(p, 4'd3, 32'h0000_0080);         // DPTCH
    p = place_movi_il_b(p, 4'd4, 32'h0000_0800);         // OFFSET
    p = place_movi_il_b(p, 4'd5, 32'h0001_0020);         // WSTART XY (X=0x20,Y=1)
    p = place_movi_il_b(p, 4'd6, 32'h0002_0020);         // WEND   XY (X=0x20,Y=2)
    p = place_movi_il_b(p, 4'd7, 32'h0002_0002);         // DYDX (DY=2,DX=2)
    p = place_movi_il_b(p, 4'd9, 32'h0000_00AA);         // COLOR1
    p = place_movi_il  (p, 4'd14, ST_SEED);
    p = place_word(p, putst_enc(4'd14));                 // NCZ=111, V=0
    p = place_word(p, 16'h0FE0);                         // FILL XY
    p = place_word(p, getst_enc(4'd8));                  // preclipping sets V only
    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // Window keeps X=0x20 (low byte), clips X=0x21 (high byte) → 0x00AA.
    check_word("row0 word145 clipped to 0x00AA", 145, 16'h00AA);
    check_word("row1 word153 clipped to 0x00AA", 153, 16'h00AA);
    // Pixels fully outside (the gap) remain zero.
    check_word("gap word146 = 0", 146, 16'h0000);
    check_word("gap word152 = 0", 152, 16'h0000);
    // DADDR (B2) still advances over the whole array (clip doesn't change it).
    if (u_core.u_regfile.b_regs[2] !== 32'h0000_09A0) begin
      $display("TEST_RESULT: FAIL: DADDR(B2)=%08h expected 000009A0",
               u_core.u_regfile.b_regs[2]);
      failures++;
    end
    if (u_core.u_regfile.a_regs[8] !== 32'hF000_0010) begin
      $display("TEST_RESULT: FAIL: W=3 clipped ST expected=F0000010 actual=%08h",
               u_core.u_regfile.a_regs[8]);
      failures++;
    end
    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set"); failures++;
    end

    if (failures == 0)
      $display("TEST_RESULT: PASS (FILL XY W=3 clip and V-only preclipping status)");
    else
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_fill_window hard timeout");
    $fatal(1);
  end
endmodule : tb_fill_window
