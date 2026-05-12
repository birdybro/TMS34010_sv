// -----------------------------------------------------------------------------
// tb_addk_subk.sv
//
// Tests ADDK K, Rd and SUBK K, Rd (K-form arithmetic).
//
// Encoding (SPVU001A A-14):
//   ADDK K,Rd  = 0001 00KK KKKR DDDD
//   SUBK K,Rd  = 0001 01KK KKKR DDDD
//   K in bits[9:5] (5-bit unsigned, zero-extended to 32 bits per A0018).
//
// Operations:
//   ADDK:   K + Rd → Rd   (flags N/C/Z/V from sum)
//   SUBK:   Rd - K → Rd   (flags N/C/Z/V from difference; C = borrow)
//
// Test does not exercise K=0 — that interpretation is hypothesis-tagged
// in A0018. Use ADDK 1 / SUBK 1 if you need increment/decrement at K=1.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_addk_subk;
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
    .clk             (clk),
    .rst             (rst),
    .mem_req         (mem_req),
    .mem_we          (mem_we),
    .mem_addr        (mem_addr),
    .mem_size        (mem_size),
    .mem_wdata       (mem_wdata),
    .mem_rdata       (mem_rdata),
    .mem_ack         (mem_ack),
    .state_o         (state_w),
    .pc_o            (pc_w),
    .instr_word_o    (instr_w),
    .illegal_opcode_o(illegal_w)
  );

  sim_memory_model #(.DEPTH_WORDS(64)) u_mem (
    .clk      (clk),
    .rst      (rst),
    .mem_req  (mem_req),
    .mem_we   (mem_we),
    .mem_addr (mem_addr),
    .mem_size (mem_size),
    .mem_wdata(mem_wdata),
    .mem_rdata(mem_rdata),
    .mem_ack  (mem_ack)
  );

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
  endfunction
  function automatic instr_word_t addk_enc(input logic [4:0] k,
                                           input reg_file_t  rf,
                                           input reg_idx_t   rd);
    addk_enc = 16'h1000
             | (instr_word_t'(k)  << 5)
             | (instr_word_t'(rf) << 4)
             | (instr_word_t'(rd));
  endfunction
  function automatic instr_word_t subk_enc(input logic [4:0] k,
                                           input reg_file_t  rf,
                                           input reg_idx_t   rd);
    subk_enc = 16'h1400
             | (instr_word_t'(k)  << 5)
             | (instr_word_t'(rf) << 4)
             | (instr_word_t'(rd));
  endfunction

  function automatic int unsigned place_movi_il(input int unsigned p,
                                                input reg_file_t   rf,
                                                input reg_idx_t    i,
                                                input logic [DATA_WIDTH-1:0] imm);
    u_mem.mem[p]     = movi_il_enc(rf, i);
    u_mem.mem[p + 1] = imm[15:0];
    u_mem.mem[p + 2] = imm[31:16];
    place_movi_il = p + 3;
  endfunction

  int unsigned failures;
  task automatic check_reg(input string label,
                           input logic [DATA_WIDTH-1:0] actual,
                           input logic [DATA_WIDTH-1:0] expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%08h actual=%08h",
               label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p;
    failures = 0;

    // Encoding sanity:
    //   ADDK 1, A0  = 0001 00_00001_0_0000 = 0001 0000 0010 0000 = 0x1020
    //   SUBK 31, A0 = 0001 01_11111_0_0000 = 0001 0111 1110 0000 = 0x17E0
    //   ADDK 7, B5  = 0001 00_00111_1_0101 = 0001 0000 1111 0101 = 0x10F5
    if (addk_enc(5'd1, REG_FILE_A, 4'd0) !== 16'h1020) begin
      $display("TEST_RESULT: FAIL: addk(1,A0)=%04h, expected 1020",
               addk_enc(5'd1, REG_FILE_A, 4'd0));
      failures++;
    end
    if (subk_enc(5'd31, REG_FILE_A, 4'd0) !== 16'h17E0) begin
      $display("TEST_RESULT: FAIL: subk(31,A0)=%04h, expected 17E0",
               subk_enc(5'd31, REG_FILE_A, 4'd0));
      failures++;
    end
    if (addk_enc(5'd7, REG_FILE_B, 4'd5) !== 16'h10F5) begin
      $display("TEST_RESULT: FAIL: addk(7,B5)=%04h, expected 10F5",
               addk_enc(5'd7, REG_FILE_B, 4'd5));
      failures++;
    end

    // Program:
    //   MOVI 100, A1
    //   ADDK 5, A1     → A1 = 105
    //   MOVI 100, A2
    //   SUBK 1, A2     → A2 = 99 (decrement)
    //   MOVI 0, A3
    //   ADDK 31, A3    → A3 = 31 (max K)
    //   MOVI 0xFFFFFFFF, A4
    //   ADDK 1, A4     → A4 = 0 (unsigned wrap; C=1, Z=1)
    //   MOVI 5, B1
    //   SUBK 5, B1     → B1 = 0 (Z=1)
    //   MOVI 0x100, B2
    //   ADDK 16, B2    → B2 = 0x110 (B-file)
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'd100);
    u_mem.mem[p] = addk_enc(5'd5, REG_FILE_A, 4'd1);  p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'd100);
    u_mem.mem[p] = subk_enc(5'd1, REG_FILE_A, 4'd2);  p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'd0);
    u_mem.mem[p] = addk_enc(5'd31, REG_FILE_A, 4'd3); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'hFFFF_FFFF);
    u_mem.mem[p] = addk_enc(5'd1, REG_FILE_A, 4'd4);  p = p + 1;

    p = place_movi_il(p, REG_FILE_B, 4'd1, 32'd5);
    u_mem.mem[p] = subk_enc(5'd5, REG_FILE_B, 4'd1);  p = p + 1;

    p = place_movi_il(p, REG_FILE_B, 4'd2, 32'h0000_0100);
    u_mem.mem[p] = addk_enc(5'd16, REG_FILE_B, 4'd2); p = p + 1;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (300) @(posedge clk);
    #1;

    check_reg("ADDK 5 → A1 = 105",  u_core.u_regfile.a_regs[1], 32'd105);
    check_reg("SUBK 1 → A2 = 99",   u_core.u_regfile.a_regs[2], 32'd99);
    check_reg("ADDK 31 → A3 = 31",  u_core.u_regfile.a_regs[3], 32'd31);
    check_reg("ADDK 1 wrap → A4 = 0", u_core.u_regfile.a_regs[4], 32'd0);
    check_reg("SUBK 5 → B1 = 0",    u_core.u_regfile.b_regs[1], 32'd0);
    check_reg("ADDK 16 → B2 = 0x110", u_core.u_regfile.b_regs[2], 32'h0000_0110);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (6 ADDK/SUBK cases: increment, decrement, max-K, unsigned-wrap, zero-result, B-file)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #500_000;
    $display("TEST_RESULT: FAIL: tb_addk_subk hard timeout");
    $fatal(1);
  end

endmodule : tb_addk_subk
