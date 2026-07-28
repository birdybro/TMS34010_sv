// -----------------------------------------------------------------------------
// tb_movb.sv
//
// MOVB (move byte) — Task 0080. A special form of MOVE with the field size
// fixed at 8 bits (SPVU001A 12-118ff): the encoding has no FS field, and a
// MOVB load is always right-justified and SIGN-extended to 32 bits with an
// implicit compare-to-0. Stores leave all status bits Unaffected. MOVB has no
// auto inc/dec forms. This test exercises the 7 forms that reuse the MOVE
// field/offset/absolute datapaths (force_byte): register<->indirect,
// indirect<->indirect, offset, and absolute (incl. an unaligned byte).
//
// The test deliberately does NOT issue SETF — force_byte must override the
// reset ST (FS0=16), proving MOVB is independent of ST.FS.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_movb;
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
  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t movb_store_enc(input reg_idx_t rs, input reg_idx_t rd);
    movb_store_enc = 16'h8C00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t movb_load_enc(input reg_idx_t rs, input reg_idx_t rd);
    movb_load_enc = 16'h8E00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t movb_m2m_enc(input reg_idx_t rs, input reg_idx_t rd);
    movb_m2m_enc = 16'h9C00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_idx_t i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction
  function automatic int unsigned place_word(input int unsigned p, input instr_word_t w);
    u_mem.mem[p] = w;  place_word = p + 1;
  endfunction
  // MOVB Rs,*Rd(off) store: 0xAC00 | (Rs<<5) | Rd, then offset.
  function automatic int unsigned place_movb_store_off(input int unsigned p,
                                                       input reg_idx_t rs, input reg_idx_t rd,
                                                       input logic [15:0] off);
    u_mem.mem[p]     = 16'hAC00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
    u_mem.mem[p + 1] = off;
    place_movb_store_off = p + 2;
  endfunction
  // MOVB *Rs(off),Rd load: 0xAE00 | (Rs<<5) | Rd, then offset.
  function automatic int unsigned place_movb_load_off(input int unsigned p,
                                                      input reg_idx_t rs, input reg_idx_t rd,
                                                      input logic [15:0] off);
    u_mem.mem[p]     = 16'hAE00 | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
    u_mem.mem[p + 1] = off;
    place_movb_load_off = p + 2;
  endfunction
  // MOVB Rs,@DAddr store: 0x05E0 | Rs, then addr LSW, MSW.
  function automatic int unsigned place_movb_store_abs(input int unsigned p,
                                                       input reg_idx_t rs,
                                                       input logic [31:0] addr);
    u_mem.mem[p]     = 16'h05E0 | instr_word_t'(rs);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_movb_store_abs = p + 3;
  endfunction
  // MOVB @SAddr,Rd load: 0x07E0 | Rd, then addr LSW, MSW.
  function automatic int unsigned place_movb_load_abs(input int unsigned p,
                                                      input reg_idx_t rd,
                                                      input logic [31:0] addr);
    u_mem.mem[p]     = 16'h07E0 | instr_word_t'(rd);
    u_mem.mem[p + 1] = addr[15:0];
    u_mem.mem[p + 2] = addr[31:16];
    place_movb_load_abs = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_word(input string label, input int unsigned widx,
                            input logic [15:0] expected);
    if (u_mem.mem[widx] !== expected) begin
      $display("TEST_RESULT: FAIL: %s: mem[%0d] expected=%04h actual=%04h",
               label, widx, expected, u_mem.mem[widx]);
      failures++;
    end
  endtask
  task automatic check_nz(input string label, input logic [DATA_WIDTH-1:0] st,
                          input logic n, input logic z);
    if (st[ST_N_BIT] !== n || st[ST_Z_BIT] !== z) begin
      $display("TEST_RESULT: FAIL: %s: exp NZ=%0b%0b got %0b%0b",
               label, n, z, st[ST_N_BIT], st[ST_Z_BIT]);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 256; i++) u_mem.mem[i] = 16'h0300;   // NOP fill
    for (i = 120; i < 210; i++) u_mem.mem[i] = 16'h0000; // clear data region

    p = 0;
    // 1) Store byte 0xC3 to *A2, then 2) load it back sign-extended.
    p = place_movi_il(p, 4'd1, 32'h0000_00C3);   // data
    p = place_movi_il(p, 4'd2, 32'h0000_0800);   // ptr (word128)
    p = place_word(p, movb_store_enc(4'd1, 4'd2));   // mem[0x800] <- 0xC3 (8b)
    p = place_word(p, movb_load_enc(4'd2, 4'd3));    // A3 <- sext(byte) = 0xFFFFFFC3
    p = place_word(p, getst_enc(4'd8));              // snapshot N/Z

    // 3) Positive byte: store 0x5A, load -> 0x0000005A (N=0).
    p = place_movi_il(p, 4'd4, 32'h0000_005A);
    p = place_movi_il(p, 4'd5, 32'h0000_0880);   // ptr (word136)
    p = place_word(p, movb_store_enc(4'd4, 4'd5));
    p = place_word(p, movb_load_enc(4'd5, 4'd6));    // A6 <- 0x0000005A
    p = place_word(p, getst_enc(4'd7));

    // 4) M2M: copy the byte at 0x800 (0xC3) to 0x900.
    p = place_movi_il(p, 4'd9, 32'h0000_0900);   // dst ptr (word144)
    p = place_word(p, movb_m2m_enc(4'd2, 4'd9));     // mem[0x900] <- mem[0x800]

    // 5) Offset: store 0xC3 at A10(0x40)=0xA40, load back sign-extended.
    p = place_movi_il(p, 4'd10, 32'h0000_0A00);  // base ptr (word160)
    p = place_movb_store_off(p, 4'd1, 4'd10, 16'h0040);  // mem[0xA40] <- 0xC3
    p = place_movb_load_off (p, 4'd10, 4'd11, 16'h0040); // A11 <- 0xFFFFFFC3

    // 6) Absolute: store 0xC3 @ 0xB00, load back sign-extended.
    p = place_movb_store_abs(p, 4'd1, 32'h0000_0B00);    // mem[0xB00] <- 0xC3
    p = place_movb_load_abs (p, 4'd12, 32'h0000_0B00);   // A12 <- 0xFFFFFFC3

    // 7) Unaligned absolute byte: store 0x5A @ bit 0xC04 (word192, boff 4),
    //    load back -> 0x0000005A.
    p = place_movb_store_abs(p, 4'd4, 32'h0000_0C04);    // mem byte @ boff4
    p = place_movb_load_abs (p, 4'd13, 32'h0000_0C04);   // A13 <- 0x0000005A

    p = place_word(p, 16'hC0FF);

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (3000) @(posedge clk);
    #1;

    // 1/2) Store + sign-extend load.
    check_word("1: mem[128] = 0x00C3", 128, 16'h00C3);
    check_reg ("2: A3 = 0xFFFFFFC3",   u_core.u_regfile.a_regs[3], 32'hFFFF_FFC3);
    check_nz  ("2: load N=1 Z=0",      u_core.u_regfile.a_regs[8], 1'b1, 1'b0);
    // 3) Positive byte.
    check_word("3: mem[136] = 0x005A", 136, 16'h005A);
    check_reg ("3: A6 = 0x0000005A",   u_core.u_regfile.a_regs[6], 32'h0000_005A);
    check_nz  ("3: load N=0 Z=0",      u_core.u_regfile.a_regs[7], 1'b0, 1'b0);
    // 4) M2M byte copy.
    check_word("4: mem[144] = 0x00C3", 144, 16'h00C3);
    // 5) Offset store/load.
    check_word("5: mem[164] = 0x00C3", 164, 16'h00C3);
    check_reg ("5: A11 = 0xFFFFFFC3",  u_core.u_regfile.a_regs[11], 32'hFFFF_FFC3);
    // 6) Absolute store/load.
    check_word("6: mem[176] = 0x00C3", 176, 16'h00C3);
    check_reg ("6: A12 = 0xFFFFFFC3",  u_core.u_regfile.a_regs[12], 32'hFFFF_FFC3);
    // 7) Unaligned absolute byte: 0x5A at boff4 -> word192 = 0x05A0.
    check_word("7: mem[192] = 0x05A0", 192, 16'h05A0);
    check_reg ("7: A13 = 0x0000005A",  u_core.u_regfile.a_regs[13], 32'h0000_005A);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVB: 7 forms, FS forced 8, sign-extend load, unaligned byte)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #3_000_000;
    $display("TEST_RESULT: FAIL: tb_movb hard timeout");
    $fatal(1);
  end

endmodule : tb_movb
