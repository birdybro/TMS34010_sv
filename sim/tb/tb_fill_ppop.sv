// -----------------------------------------------------------------------------
// tb_fill_ppop.sv
//
// FILL pixel processing (Task 0093). FILL now applies the CONTROL pixel engine
// per pixel (read-modify-write): merged = PPOP(COLOR1, dest), then transparency
// and plane mask. This test fills a small array over preloaded destination
// pixels with an XOR PPOP, a transparent COLOR1, and a plane mask, checking the
// processed results. SPVU001A FILL / CONTROL. PSIZE=8.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_fill_ppop;
  import tms34010_pkg::*;

  logic clk = 1'b0;
  logic rst = 1'b1;
  always #5 clk = ~clk;

  logic                          mem_req;
  logic                          mem_we;
  logic [ADDR_WIDTH-1:0]         mem_addr;
  logic [FIELD_SIZE_WIDTH-1:0]   mem_size;
  logic [DATA_WIDTH-1:0]         mem_wdata;
  logic [DATA_WIDTH-1:0]         mem_rdata;
  logic                          mem_ack;
  core_state_t                   state_w;
  logic [ADDR_WIDTH-1:0]         pc_w;
  instr_word_t                   instr_w;
  logic                          illegal_w;

  tms34010_core u_core (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack),
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w)
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
  function automatic instr_word_t setf_enc(input logic [4:0] fs,
                                           input logic fe, input logic f_sel);
    setf_enc = 16'b0000_0100_0000_0000
             | (instr_word_t'(f_sel) << 9) | 16'b0000_0001_0000_0000
             | 16'b0000_0000_0100_0000 | (instr_word_t'(fe) << 5)
             | instr_word_t'(fs);
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_movi_il_b(input int unsigned p,
                                                  input reg_idx_t i,
                                                  input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_b_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il_b = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p] = w;  place_word = p + 1;
  endfunction
  function automatic int unsigned place_store_abs(input int unsigned p,
                                                  input reg_idx_t rs,
                                                  input logic [31:0] addr);
    u_mem.mem[p]     = 16'h0580 | instr_word_t'(rs);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_store_abs = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_word(input string label, input int unsigned widx,
                            input logic [15:0] expected);
    if (u_mem.mem[widx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, widx, expected, u_mem.mem[widx]);
      failures++;
    end
  endtask

  localparam logic [31:0] A_PSIZE   = IO_BASE_ADDR + (IO_IDX_PSIZE   << 4);
  localparam logic [31:0] A_CONTROL = IO_BASE_ADDR + (IO_IDX_CONTROL << 4);
  localparam logic [31:0] A_PMASK   = IO_BASE_ADDR + (IO_IDX_PMASK   << 4);

  // One FILL: set CONTROL/PMASK, B-regs, then FILL L. dst is a 1x2 row.
  function automatic int unsigned place_fill(input int unsigned pp,
                                             input logic [31:0] control,
                                             input logic [31:0] pmask,
                                             input logic [31:0] color,
                                             input logic [31:0] daddr);
    pp = place_movi_il  (pp, 4'd0, control);
    pp = place_store_abs(pp, 4'd0, A_CONTROL);
    pp = place_movi_il  (pp, 4'd0, pmask);
    pp = place_store_abs(pp, 4'd0, A_PMASK);
    pp = place_movi_il_b(pp, 4'd2, daddr);            // DADDR (B2)
    pp = place_movi_il_b(pp, 4'd3, 32'h0000_0080);    // DPTCH (B3)
    pp = place_movi_il_b(pp, 4'd7, 32'h0001_0002);    // DYDX: DY=1, DX=2
    pp = place_movi_il_b(pp, 4'd9, color);            // COLOR1 (B9)
    pp = place_word(pp, 16'h0FC0);                    // FILL L
    place_fill = pp;
  endfunction

  int unsigned p;
  initial begin : main
    int unsigned i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 200; i++) u_mem.mem[i] = 16'h0000;
    // Preload destination pixels: two pixels per word.
    u_mem.mem[128] = 16'hF00F;  // case 1 (XOR): pixels 0x0F, 0xF0 at 0x800,0x808
    u_mem.mem[136] = 16'hAAAA;  // case 2 (transparent COLOR1=0): both 0xAA
    u_mem.mem[144] = 16'hCCCC;  // case 3 (PMASK 0x0F): both 0xCC

    p = 0;
    p = place_word(p, setf_enc(5'd16, 1'b0, 1'b0));      // FS0=16 for MOVE-to-I/O
    p = place_movi_il  (p, 4'd0, 32'h0000_0008);
    p = place_store_abs(p, 4'd0, A_PSIZE);               // PSIZE = 8

    // 1) PPOP = XOR (0x0A): COLOR1=0xFF over dest {0x0F,0xF0} -> {0xF0,0x0F}.
    p = place_fill(p, {16'h0, 1'b0, 5'h0A, 10'h0}, 32'h0, 32'h0000_00FF, 32'h0000_0800);
    // 2) Transparency: COLOR1=0 with T=1 -> dest unchanged (0xAA both).
    p = place_fill(p, {16'h0, 1'b0, 5'h00, 4'h0, 1'b1, 5'h0}, 32'h0, 32'h0000_0000, 32'h0000_0880);
    // 3) PMASK = 0x0F (low nibble protected): COLOR1=0x55 over dest 0xCC ->
    //    (0x55 & 0xF0) | (0xCC & 0x0F) = 0x50 | 0x0C = 0x5C, both pixels.
    p = place_fill(p, {16'h0, 1'b0, 5'h00, 10'h0}, 32'h0000_000F, 32'h0000_0055, 32'h0000_0900);

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (6000) @(posedge clk);
    #1;

    // 1) XOR fill: word128 = {0x0F, 0x00... } -> pixel0=0x0F^0xFF=0xF0,
    //    pixel1=0xF0^0xFF=0x0F -> word = 0x0FF0.
    check_word("1: XOR fill word128 = 0x0FF0", 128, 16'h0FF0);
    // 2) Transparent (COLOR1=0): destination unchanged.
    check_word("2: transparent word136 = 0xAAAA", 136, 16'hAAAA);
    // 3) PMASK 0x0F: each pixel -> 0x5C, word = 0x5C5C.
    check_word("3: PMASK fill word144 = 0x5C5C", 144, 16'h5C5C);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (FILL pixel processing: PPOP XOR, transparency, plane mask)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #6_000_000;
    $display("TEST_RESULT: FAIL: tb_fill_ppop hard timeout");
    $fatal(1);
  end

endmodule : tb_fill_ppop
