// -----------------------------------------------------------------------------
// tb_immi_iw.sv
//
// Tests the IW-form immediate-arithmetic instructions:
//   ADDI IW K, Rd     Rd + sign_extend(K16) → Rd       (flags N/C/Z/V)
//   SUBI IW K, Rd     Rd - sign_extend(K16) → Rd       (flags N/C/Z/V)
//   CMPI IW K, Rd     flags from Rd - sign_extend(K16); Rd unchanged
//
// Encoding (SPVU001A A-14):
//   ADDI IW K, Rd  = 0000 1011 000R DDDD  + 16-bit imm
//   SUBI IW K, Rd  = 0000 1011 111R DDDD  + 16-bit imm
//   CMPI IW K, Rd  = 0000 1011 010R DDDD  + 16-bit imm
//
// All three reuse MOVI IW's CORE_FETCH_IMM_LO path.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module tb_immi_iw;
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

  sim_memory_model #(.DEPTH_WORDS(128)) u_mem (
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

  // Encoding helpers.
  // Top 11 bits are the prefix; bottom 5 are {R, Rd}. We place the
  // top-11 in the upper part of the instruction word.
  function automatic instr_word_t imm_iw_enc(input logic [10:0] top11,
                                             input reg_file_t   rf,
                                             input reg_idx_t    rd);
    imm_iw_enc = (instr_word_t'(top11) << 5)
               | (instr_word_t'(rf) << 4)
               | (instr_word_t'(rd));
  endfunction

  localparam logic [10:0] ADDI_IW_TOP11 = 11'b0000_1011_000;
  localparam logic [10:0] SUBI_IW_TOP11 = 11'b0000_1011_111;
  localparam logic [10:0] CMPI_IW_TOP11 = 11'b0000_1011_010;

  function automatic instr_word_t movi_il_enc(input reg_file_t rf, input reg_idx_t i);
    movi_il_enc = 16'h09E0 | (instr_word_t'(rf) << 4) | (instr_word_t'(i));
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

  function automatic int unsigned place_imm_iw(input int unsigned p,
                                               input logic [10:0] top11,
                                               input reg_file_t   rf,
                                               input reg_idx_t    rd,
                                               input logic [15:0] imm);
    u_mem.mem[p]     = imm_iw_enc(top11, rf, rd);
    u_mem.mem[p + 1] = imm;
    place_imm_iw = p + 2;
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
  task automatic check_bit(input string label, input logic actual, input logic expected);
    if (actual !== expected) begin
      $display("TEST_RESULT: FAIL: %s: expected=%0b actual=%0b",
               label, expected, actual);
      failures++;
    end
  endtask

  initial begin : main
    int unsigned p;
    failures = 0;

    // Encoding sanity:
    //   ADDI IW _, A0 = 0000_1011_000_0_0000 = 0x0B00
    //   SUBI IW _, A0 = 0000_1011_111_0_0000 = 0x0BE0
    //   CMPI IW _, A0 = 0000_1011_010_0_0000 = 0x0B40
    if (imm_iw_enc(ADDI_IW_TOP11, REG_FILE_A, 4'd0) !== 16'h0B00) begin
      $display("TEST_RESULT: FAIL: ADDI IW _,A0 = %04h, expected 0B00",
               imm_iw_enc(ADDI_IW_TOP11, REG_FILE_A, 4'd0));
      failures++;
    end
    if (imm_iw_enc(SUBI_IW_TOP11, REG_FILE_A, 4'd0) !== 16'h0BE0) begin
      $display("TEST_RESULT: FAIL: SUBI IW _,A0 = %04h, expected 0BE0",
               imm_iw_enc(SUBI_IW_TOP11, REG_FILE_A, 4'd0));
      failures++;
    end
    if (imm_iw_enc(CMPI_IW_TOP11, REG_FILE_A, 4'd0) !== 16'h0B40) begin
      $display("TEST_RESULT: FAIL: CMPI IW _,A0 = %04h, expected 0B40",
               imm_iw_enc(CMPI_IW_TOP11, REG_FILE_A, 4'd0));
      failures++;
    end

    // Program:
    //   MOVI 100, A1  ; ADDI IW 50, A1   → A1 = 150
    //   MOVI 100, A2  ; SUBI IW 100, A2  → A2 = 0 (Z=1)
    //   MOVI 50, A3   ; ADDI IW -10, A3  → A3 = 40 (sign-extension of -10)
    //   MOVI 5, A4    ; CMPI IW 5, A4    → flags from 5-5=0 (Z=1); A4 stays 5
    //   MOVI 100, B1  ; ADDI IW 200, B1  → B1 = 300 (B-file)
    p = 0;
    p = place_movi_il(p, REG_FILE_A, 4'd1, 32'd100);
    p = place_imm_iw (p, ADDI_IW_TOP11, REG_FILE_A, 4'd1, 16'd50);

    p = place_movi_il(p, REG_FILE_A, 4'd2, 32'd100);
    p = place_imm_iw (p, SUBI_IW_TOP11, REG_FILE_A, 4'd2, 16'd100);

    p = place_movi_il(p, REG_FILE_A, 4'd3, 32'd50);
    p = place_imm_iw (p, ADDI_IW_TOP11, REG_FILE_A, 4'd3, 16'hFFF6);  // -10

    p = place_movi_il(p, REG_FILE_A, 4'd4, 32'd5);
    p = place_imm_iw (p, CMPI_IW_TOP11, REG_FILE_A, 4'd4, 16'd5);

    p = place_movi_il(p, REG_FILE_B, 4'd1, 32'd100);
    p = place_imm_iw (p, ADDI_IW_TOP11, REG_FILE_B, 4'd1, 16'd200);

    repeat (3) @(posedge clk);
    rst = 1'b0;

    repeat (400) @(posedge clk);
    #1;

    check_reg("ADDI IW: 100 + 50 = 150",            u_core.u_regfile.a_regs[1], 32'd150);
    check_reg("SUBI IW: 100 - 100 = 0",              u_core.u_regfile.a_regs[2], 32'd0);
    check_reg("ADDI IW: 50 + (-10) = 40 (sign-ext)", u_core.u_regfile.a_regs[3], 32'd40);
    check_reg("CMPI IW: A4 unchanged",                u_core.u_regfile.a_regs[4], 32'd5);
    check_reg("ADDI IW (B): 100 + 200 = 300",        u_core.u_regfile.b_regs[1], 32'd300);

    // ST should reflect the LAST flag-affecting instruction, which is
    // the ADDI IW B1 (300 result: positive, nonzero, no overflow).
    check_bit("ST.N final (positive)",            u_core.u_status_reg.n_o, 1'b0);
    check_bit("ST.Z final (nonzero)",              u_core.u_status_reg.z_o, 1'b0);
    check_bit("ST.C final (no unsigned overflow)", u_core.u_status_reg.c_o, 1'b0);
    check_bit("ST.V final (no signed overflow)",   u_core.u_status_reg.v_o, 1'b0);

    if (failures == 0) begin
      $display("TEST_RESULT: PASS (3 IW-immediate instructions verified across 5 program cases)");
    end else begin
      $display("TEST_RESULT: FAIL: %0d check(s) failed", failures);
    end

    $finish;
  end

  initial begin : watchdog
    #1_000_000;
    $display("TEST_RESULT: FAIL: tb_immi_iw hard timeout");
    $fatal(1);
  end

endmodule : tb_immi_iw
