// -----------------------------------------------------------------------------
// tb_cpw.sv
//
// CPW Rs,Rd — Compare Point to Window. Per SPVU001A page 12-57. Encoding
// 1110 011S SSSR DDDD (0xE600). Compares the signed XY point in Rs against
// the window corners WSTART = B5 and WEND = B6 (implied B-file operands),
// and loads a 4-bit out-of-window code into Rd[8:5]:
//   bit5 = WSTART.X > Rs.X    bit6 = Rs.X > WEND.X
//   bit7 = WSTART.Y > Rs.Y    bit8 = Rs.Y > WEND.Y
// all other bits 0. X = low 16 (signed), Y = high 16 (signed). Status:
// N/C/Z Unaffected; V = 1 iff the point is outside the window.
//
// Cases from TI's example table (WSTART=5,5; WEND=A,A) plus a negative-X
// point to confirm the comparisons are SIGNED.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_cpw;
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
    .state_o(state_w), .pc_o(pc_w), .instr_word_o(instr_w), .illegal_opcode_o(illegal_w), .run_emu_n_i(1'b1), .emua_n_o(), .lint1_n_i(1'b1), .lint2_n_i(1'b1), .host_int_set_i(1'b0), .dpyint_set_i(1'b0)
  );

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  // MOVI IL: 0x09E0 | (R<<4) | idx.
  function automatic instr_word_t movi_il_enc(input logic r, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(r) << 4) | instr_word_t'(i);
  endfunction
  function automatic instr_word_t cpw_enc(input reg_idx_t rs, input reg_idx_t rd);
    cpw_enc = 16'hE600 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input logic r, input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(r, i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p] = w;  place_word = p + 1;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_v(input string label, input logic [DATA_WIDTH-1:0] st, input logic v);
    if (st[ST_V_BIT] !== v) begin
      $display("TEST_RESULT: FAIL: %s: expected V=%0b actual=%0b", label, v, st[ST_V_BIT]);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 128; i++) u_mem.mem[i] = 16'h0300;

    p = 0;
    // Window: WSTART=B5=(5,5), WEND=B6=(0xA,0xA).
    p = place_movi_il(p, 1'b1, 4'd5, 32'h0005_0005);
    p = place_movi_il(p, 1'b1, 4'd6, 32'h000A_000A);

    // A: point (5,5) inside -> code 0, V=0.
    p = place_movi_il(p, 1'b0, 4'd1, 32'h0005_0005);
    p = place_word(p, cpw_enc(4'd1, 4'd0));
    p = place_word(p, getst_enc(4'd2));
    // B: point (4,4) -> WSTART.X>X & WSTART.Y>Y -> code 0xA0, V=1.
    p = place_movi_il(p, 1'b0, 4'd3, 32'h0004_0004);
    p = place_word(p, cpw_enc(4'd3, 4'd4));
    p = place_word(p, getst_enc(4'd5));
    // C: point (0xB,0xB) -> X>WEND.X & Y>WEND.Y -> code 0x140, V=1.
    p = place_movi_il(p, 1'b0, 4'd6, 32'h000B_000B);
    p = place_word(p, cpw_enc(4'd6, 4'd7));
    p = place_word(p, getst_enc(4'd8));
    // D: point X=4,Y=5 -> only WSTART.X>X (bit5) -> code 0x20, V=1.
    p = place_movi_il(p, 1'b0, 4'd9, 32'h0005_0004);
    p = place_word(p, cpw_enc(4'd9, 4'd10));
    p = place_word(p, getst_enc(4'd11));
    // E: point X=-1 (0xFFFF),Y=5 -> SIGNED: WSTART.X(5) > -1 -> bit5 set,
    //    code 0x20, V=1. (Unsigned would give code 0, V=0 -> locks signed.)
    p = place_movi_il(p, 1'b0, 4'd12, 32'h0005_FFFF);
    p = place_word(p, cpw_enc(4'd12, 4'd13));
    p = place_word(p, getst_enc(4'd14));

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2000) @(posedge clk);
    #1;

    check_reg("A: inside -> code 0",  u_core.u_regfile.a_regs[0], 32'h0000_0000);
    check_v  ("A: V=0 (inside)",      u_core.u_regfile.a_regs[2], 1'b0);
    check_reg("B: (4,4) -> 0xA0",     u_core.u_regfile.a_regs[4], 32'h0000_00A0);
    check_v  ("B: V=1",               u_core.u_regfile.a_regs[5], 1'b1);
    check_reg("C: (B,B) -> 0x140",    u_core.u_regfile.a_regs[7], 32'h0000_0140);
    check_v  ("C: V=1",               u_core.u_regfile.a_regs[8], 1'b1);
    check_reg("D: (4,5) -> 0x20",     u_core.u_regfile.a_regs[10], 32'h0000_0020);
    check_v  ("D: V=1",               u_core.u_regfile.a_regs[11], 1'b1);
    check_reg("E: (-1,5) signed -> 0x20", u_core.u_regfile.a_regs[13], 32'h0000_0020);
    check_v  ("E: V=1 (signed)",      u_core.u_regfile.a_regs[14], 1'b1);
    // WSTART/WEND unchanged.
    check_reg("WSTART B5 unchanged", u_core.u_regfile.b_regs[5], 32'h0005_0005);
    check_reg("WEND   B6 unchanged", u_core.u_regfile.b_regs[6], 32'h000A_000A);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (CPW: window codes + V per TI table; signed compare)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #2_000_000;
    $display("TEST_RESULT: FAIL: tb_cpw hard timeout");
    $fatal(1);
  end

endmodule : tb_cpw
