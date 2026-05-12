// -----------------------------------------------------------------------------
// tb_neg_not.sv
//
// Tests NEG Rd and NOT Rd (single-register unary ops).
//
// Encoding (SPVU001A A-14):
//   NEG Rd  = 0000 0011 101R DDDD   (bits[6:5] = 01)
//   NOT Rd  = 0000 0011 111R DDDD   (bits[6:5] = 11)
//
// Operations:
//   NEG:  0 - Rd → Rd      Flags: N, C, Z, V from the negation.
//                          V = 1 only when Rd was 0x8000_0000 (MIN_INT)
//                          since -MIN = MIN (per A0009 / SPVU001A).
//   NOT:  ~Rd → Rd         Flags: N, Z from result; C and V cleared
//                          (logical ops convention, A0009).
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_neg_not;
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
  // bits[15:8]=0x03, bits[7:5]=101 for NEG → low byte = 1010_RRRR? No:
  //   bit7=1, bit6=0, bit5=1, bit4=R, bits[3:0]=N → low byte = `0101_0000 | (R<<4) | N`? wait
  // Let me recompute: 0000 0011 101R DDDD →
  //   bits[15:8] = 0x03; bits[7:0] = 1010_RDDD with bit 7=1, 6=0, 5=1, 4=R, 3..0=D.
  //   That's 8'b101?_RDDD = (R<<4 | D) + 0x_A0 if bits[7:5]=101.
  function automatic instr_word_t neg_enc(input reg_file_t rf, input reg_idx_t rd);
    neg_enc = 16'h03A0
            | (instr_word_t'(rf) << 4)
            | (instr_word_t'(rd));
  endfunction
  function automatic instr_word_t not_enc(input reg_file_t rf, input reg_idx_t rd);
    // bits[7:5] = 111 → 0xE0 in the low byte.
    not_enc = 16'h03E0
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
    //   NEG A0 = 0000 0011 1010 0000 = 0x03A0
    //   NEG A5 = 0000 0011 1010 0101 = 0x03A5
    //   NOT B3 = 0000 0011 1111 0011 = 0x03F3
    if (neg_enc(REG_FILE_A, 4'd0) !== 16'h03A0) begin
      $display("TEST_RESULT: FAIL: neg(A0)=%04h, expected 03A0", neg_enc(REG_FILE_A, 4'd0));
      failures++;
    end
    if (neg_enc(REG_FILE_A, 4'd5) !== 16'h03A5) begin
      $display("TEST_RESULT: FAIL: neg(A5)=%04h, expected 03A5", neg_enc(REG_FILE_A, 4'd5));
      failures++;
    end
    if (not_enc(REG_FILE_B, 4'd3) !== 16'h03F3) begin
      $display("TEST_RESULT: FAIL: not(B3)=%04h, expected 03F3", not_enc(REG_FILE_B, 4'd3));
      failures++;
    end

    // Program:
    //   MOVI 5, A1 ; NEG A1 → A1 = -5 = 0xFFFFFFFB
    //   MOVI 0, A2 ; NEG A2 → A2 = 0 (Z=1)
    //   MOVI 0x80000000, A3 ; NEG A3 → A3 = 0x80000000 (V=1, N=1)
    //   MOVI 0xF0F0_0F0F, A4 ; NOT A4 → A4 = 0x0F0F_F0F0
    //   MOVI 0, A5 ; NOT A5 → A5 = 0xFFFFFFFF (N=1)
    //   MOVI 0xFFFFFFFF, B1 ; NOT B1 → B1 = 0 (Z=1; B-file)
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'd5);
    u_mem.mem[p] = neg_enc(REG_FILE_A, 4'd1); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'd0);
    u_mem.mem[p] = neg_enc(REG_FILE_A, 4'd2); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'h8000_0000);
    u_mem.mem[p] = neg_enc(REG_FILE_A, 4'd3); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'hF0F0_0F0F);
    u_mem.mem[p] = not_enc(REG_FILE_A, 4'd4); p = p + 1;

    p = place_movi_il(p, REG_FILE_A, 4'd5, 32'd0);
    u_mem.mem[p] = not_enc(REG_FILE_A, 4'd5); p = p + 1;

    p = place_movi_il(p, REG_FILE_B, 4'd1, 32'hFFFF_FFFF);
    u_mem.mem[p] = not_enc(REG_FILE_B, 4'd1); p = p + 1;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (300) @(posedge clk);
    #1;

    check_reg("NEG 5 → -5",          u_core.u_regfile.a_regs[1], 32'hFFFF_FFFB);
    check_reg("NEG 0 → 0",            u_core.u_regfile.a_regs[2], 32'h0000_0000);
    check_reg("NEG MIN → MIN (V)",   u_core.u_regfile.a_regs[3], 32'h8000_0000);
    check_reg("NOT 0xF0F0_0F0F",     u_core.u_regfile.a_regs[4], 32'h0F0F_F0F0);
    check_reg("NOT 0 → all-ones",    u_core.u_regfile.a_regs[5], 32'hFFFF_FFFF);
    check_reg("NOT 0xFFFFFFFF → 0 (B)", u_core.u_regfile.b_regs[1], 32'h0000_0000);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (6 cases: NEG 5/0/MIN, NOT pattern/0/-1; A and B files)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #500_000;
    $display("TEST_RESULT: FAIL: tb_neg_not hard timeout");
    $fatal(1);
  end

endmodule : tb_neg_not
