// -----------------------------------------------------------------------------
// tb_move_indirect_incdec.sv
//
// MOVE indirect with auto inc/dec, field-size 32, word-aligned (Task 0060).
// Per SPVU001A pages 12-129/12-130 (store post/pre) and 12-139/12-143
// (load post/pre):
//
//   MOVE Rs,*Rd+ : 1001 00FS (0x9000) store. mem[Rd] <- Rs; Rd += 32.
//   MOVE Rs,-*Rd : 1010 00FS (0xA000) store. Rd -= 32; mem[Rd] <- Rs.
//   MOVE *Rs+,Rd : 1001 01FS (0x9400) load.  Rd <- mem[Rs]; Rs += 32.
//   MOVE -*Rs,Rd : 1010 01FS (0xA400) load.  Rs -= 32; Rd <- mem[Rs].
//
// Stores leave all flags Unaffected; loads do an implicit compare-to-0
// (N=data[31], Z=(data==0), V=0, C Unaffected). Step is the field size
// (32 here). Scope: FS=32, word-aligned (same limitation as Task 0059).
//
// Edge case (SPVU001A 12-143): if a load's pointer (Rs) and destination
// (Rd) are the same register, the fetched DATA wins (not the updated
// pointer). The core writes the pointer during CORE_MEMORY and the data
// at WRITEBACK, so data naturally overwrites — verified in Case C.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_move_indirect_incdec;
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

  sim_memory_model #(.DEPTH_WORDS(512)) u_mem (
    .clk(clk), .rst(rst),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_size(mem_size),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_ack(mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_idx_t i);
    movi_il_enc = 16'h09E0 | instr_word_t'(i);
  endfunction
  // Rs=instr[8:5], R=instr[4]=0 (A file), Rd=instr[3:0], F=0.
  function automatic instr_word_t mv_enc(input instr_word_t base,
                                         input reg_idx_t rs, input reg_idx_t rd);
    mv_enc = base | (instr_word_t'(rs) << 5) | instr_word_t'(rd);
  endfunction
  function automatic instr_word_t getst_enc(input reg_idx_t rd);
    getst_enc = 16'h0180 | instr_word_t'(rd);
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

  localparam instr_word_t STORE_POSTINC = 16'h9000;
  localparam instr_word_t LOAD_POSTINC  = 16'h9400;
  localparam instr_word_t STORE_PREDEC  = 16'hA000;
  localparam instr_word_t LOAD_PREDEC   = 16'hA400;

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_mem32(input string label, input int unsigned w,
                             input logic [DATA_WIDTH-1:0] expected);
    logic [DATA_WIDTH-1:0] actual;
    actual = {u_mem.mem[w + 1], u_mem.mem[w]};
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h", label, expected, actual);
      failures++;
    end
  endtask
  task automatic check_bit(input string label, input logic actual, expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b", label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p, i;
    failures = 0;
    for (i = 0; i < 512; i++) u_mem.mem[i] = 16'h0300;

    p = 0;
    // ===== Case A: postincrement store then postincrement load =========
    //   A1=data, A2=0x800 ; MOVE A1,*A2+  -> mem[0x800]=data, A2=0x820
    //   A3=0x800          ; MOVE *A3+,A4  -> A4=data, A3=0x820 ; GETST A10
    p = place_movi_il(p, 4'd1, 32'hAAAA_1111);     // negative value (N=1 on load)
    p = place_movi_il(p, 4'd2, 32'h0000_0800);
    p = place_word(p, mv_enc(STORE_POSTINC, 4'd1, 4'd2));  // MOVE A1,*A2+
    p = place_movi_il(p, 4'd3, 32'h0000_0800);
    p = place_word(p, mv_enc(LOAD_POSTINC, 4'd3, 4'd4));   // MOVE *A3+,A4
    p = place_word(p, getst_enc(4'd10));                   // snapshot load flags

    // ===== Case B: predecrement store then predecrement load ===========
    //   A5=data, A6=0x920 ; MOVE A5,-*A6 -> A6=0x900, mem[0x900]=data
    //   A7=0x920          ; MOVE -*A7,A8 -> A7=0x900, A8=data
    p = place_movi_il(p, 4'd5, 32'hBBBB_2222);
    p = place_movi_il(p, 4'd6, 32'h0000_0920);
    p = place_word(p, mv_enc(STORE_PREDEC, 4'd5, 4'd6));   // MOVE A5,-*A6
    p = place_movi_il(p, 4'd7, 32'h0000_0920);
    p = place_word(p, mv_enc(LOAD_PREDEC, 4'd7, 4'd8));    // MOVE -*A7,A8

    // ===== Case C: predec load with Rs==Rd (data must win) =============
    //   A9=0x920 ; MOVE -*A9,A9 -> addr=0x900, read mem[0x900]=data ;
    //   final A9 = data (NOT the decremented pointer 0x900).
    p = place_movi_il(p, 4'd9, 32'h0000_0920);
    p = place_word(p, mv_enc(LOAD_PREDEC, 4'd9, 4'd9));    // MOVE -*A9,A9

    p = place_word(p, 16'hC0FF);                            // halt

    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (2000) @(posedge clk);
    #1;

    // ---- Case A ----
    check_mem32("A: mem[0x800] = data (postinc store)", 32'h800 >> 4, 32'hAAAA_1111);
    check_reg("A: A2 = 0x820 (ptr += 32)",  u_core.u_regfile.a_regs[2], 32'h0000_0820);
    check_reg("A: A4 = data (postinc load)", u_core.u_regfile.a_regs[4], 32'hAAAA_1111);
    check_reg("A: A3 = 0x820 (ptr += 32)",  u_core.u_regfile.a_regs[3], 32'h0000_0820);
    check_bit("A: load N=1 (neg data)", u_core.u_regfile.a_regs[10][ST_N_BIT], 1'b1);
    check_bit("A: load Z=0",            u_core.u_regfile.a_regs[10][ST_Z_BIT], 1'b0);

    // ---- Case B ----
    check_mem32("B: mem[0x900] = data (predec store)", 32'h900 >> 4, 32'hBBBB_2222);
    check_reg("B: A6 = 0x900 (ptr -= 32)",  u_core.u_regfile.a_regs[6], 32'h0000_0900);
    check_reg("B: A8 = data (predec load)", u_core.u_regfile.a_regs[8], 32'hBBBB_2222);
    check_reg("B: A7 = 0x900 (ptr -= 32)",  u_core.u_regfile.a_regs[7], 32'h0000_0900);

    // ---- Case C: data wins over the decremented pointer ----
    check_reg("C: A9 = data, not 0x900 (Rs==Rd data wins)",
              u_core.u_regfile.a_regs[9], 32'hBBBB_2222);

    if (illegal_w !== 1'b0) begin
      $display("TEST_RESULT: FAIL: illegal_opcode_o was set");
      failures++;
    end

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (MOVE inc/dec: post/pre store+load, FS=32, Rs==Rd data-wins)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end
    $finish;
  end

  initial begin : watchdog
    #5_000_000;
    $display("TEST_RESULT: FAIL: tb_move_indirect_incdec hard timeout");
    $fatal(1);
  end

endmodule : tb_move_indirect_incdec
